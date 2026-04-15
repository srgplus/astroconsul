import StoreKit
import WebKit

/// Manages StoreKit2 in-app purchases and communicates with the WKWebView via JavaScript.
///
/// Product IDs (configured in App Store Connect):
///   - me.big3.pro.monthly  ($7.99/mo)
///   - me.big3.pro.annual   ($59.99/yr)
///
/// JS → Swift bridge:  window.webkit.messageHandlers.storekit.postMessage({ action, ... })
/// Swift → JS callback: window.__storekit_callback(jsonString)
@available(iOS 15.0, *)
class StoreKit2Manager: NSObject, WKScriptMessageHandler {

    static let productIDs: Set<String> = [
        "me.big3.pro.monthly",
        "me.big3.pro.annual",
    ]

    private weak var webView: WKWebView?
    private var products: [Product] = []
    private var transactionListener: Task<Void, Never>?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        startTransactionListener()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            sendCallback(["error": "Invalid message format"])
            return
        }

        switch action {
        case "loadProducts":
            Task { await loadProducts() }
        case "purchase":
            guard let productId = body["productId"] as? String,
                  let userId = body["userId"] as? String else {
                sendCallback(["error": "Missing productId or userId", "action": "purchaseResult"])
                return
            }
            Task { await purchase(productId: productId, userId: userId) }
        case "restorePurchases":
            Task { await restorePurchases() }
        default:
            sendCallback(["error": "Unknown action: \(action)"])
        }
    }

    // MARK: - Load Products

    private func loadProducts() async {
        do {
            products = try await Product.products(for: StoreKit2Manager.productIDs)

            let productData = products.map { product -> [String: Any] in
                return [
                    "id": product.id,
                    "displayName": product.displayName,
                    "displayPrice": product.displayPrice,
                    "price": NSDecimalNumber(decimal: product.price).doubleValue,
                    "type": product.type == .autoRenewable ? "autoRenewable" : "other",
                    "period": subscriptionPeriodString(product),
                ]
            }.sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }

            sendCallback([
                "action": "productsLoaded",
                "products": productData,
            ])
        } catch {
            print("[StoreKit2] Failed to load products: \(error)")
            sendCallback([
                "action": "productsLoaded",
                "error": error.localizedDescription,
                "products": [],
            ])
        }
    }

    // MARK: - Purchase

    private func purchase(productId: String, userId: String) async {
        guard let product = products.first(where: { $0.id == productId }) else {
            sendCallback(["action": "purchaseResult", "error": "Product not found: \(productId)"])
            return
        }

        do {
            // Pass userId as appAccountToken so Apple webhook can map back to our user
            let uuidToken = uuidFromUserId(userId)
            let result = try await product.purchase(options: [
                .appAccountToken(uuidToken)
            ])

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()

                sendCallback([
                    "action": "purchaseResult",
                    "success": true,
                    "transactionId": String(transaction.id),
                    "originalTransactionId": String(transaction.originalID),
                    "productId": transaction.productID,
                ])

            case .userCancelled:
                sendCallback(["action": "purchaseResult", "cancelled": true])

            case .pending:
                sendCallback(["action": "purchaseResult", "pending": true])

            @unknown default:
                sendCallback(["action": "purchaseResult", "error": "Unknown purchase result"])
            }
        } catch {
            print("[StoreKit2] Purchase failed: \(error)")
            sendCallback(["action": "purchaseResult", "error": error.localizedDescription])
        }
    }

    // MARK: - Restore Purchases

    private func restorePurchases() async {
        do {
            try await AppStore.sync()

            var restoredTransactions: [[String: Any]] = []
            for await result in Transaction.currentEntitlements {
                if let transaction = try? checkVerified(result) {
                    restoredTransactions.append([
                        "transactionId": String(transaction.id),
                        "originalTransactionId": String(transaction.originalID),
                        "productId": transaction.productID,
                    ])
                }
            }

            sendCallback([
                "action": "restoreResult",
                "success": true,
                "transactions": restoredTransactions,
            ])
        } catch {
            print("[StoreKit2] Restore failed: \(error)")
            sendCallback([
                "action": "restoreResult",
                "error": error.localizedDescription,
            ])
        }
    }

    // MARK: - Transaction Listener

    private func startTransactionListener() {
        transactionListener = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { return }
                if let transaction = try? self.checkVerified(result) {
                    await transaction.finish()
                    self.sendCallback([
                        "action": "transactionUpdate",
                        "transactionId": String(transaction.id),
                        "originalTransactionId": String(transaction.originalID),
                        "productId": transaction.productID,
                    ])
                }
            }
        }
    }

    // MARK: - Helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    private func subscriptionPeriodString(_ product: Product) -> String {
        guard let sub = product.subscription else { return "" }
        switch sub.subscriptionPeriod.unit {
        case .month: return "monthly"
        case .year: return "annual"
        case .week: return "weekly"
        case .day: return "daily"
        @unknown default: return "unknown"
        }
    }

    /// Convert a user ID string to a deterministic UUID for appAccountToken.
    private func uuidFromUserId(_ userId: String) -> UUID {
        let data = userId.data(using: .utf8) ?? Data()
        var hash = [UInt8](repeating: 0, count: 16)
        data.withUnsafeBytes { ptr in
            let bytes = ptr.bindMemory(to: UInt8.self)
            for i in 0..<min(bytes.count, 16) {
                hash[i] = bytes[i]
            }
            // XOR fold longer IDs
            if bytes.count > 16 {
                for i in 16..<bytes.count {
                    hash[i % 16] ^= bytes[i]
                }
            }
        }
        // Set UUID version 4 bits
        hash[6] = (hash[6] & 0x0F) | 0x40
        hash[8] = (hash[8] & 0x3F) | 0x80
        return UUID(uuid: (hash[0], hash[1], hash[2], hash[3],
                          hash[4], hash[5], hash[6], hash[7],
                          hash[8], hash[9], hash[10], hash[11],
                          hash[12], hash[13], hash[14], hash[15]))
    }

    private func sendCallback(_ data: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        let escaped = jsonString.replacingOccurrences(of: "'", with: "\\'")
        let js = "if(window.__storekit_callback){window.__storekit_callback('\(escaped)');}"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("[StoreKit2] JS callback error: \(error.localizedDescription)")
                }
            }
        }
    }
}
