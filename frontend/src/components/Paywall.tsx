import { useState, useEffect, useCallback } from "react"
import { createCheckoutSession, verifyAppleTransaction } from "../api"

const isNativeApp = (): boolean =>
  typeof window !== "undefined" && !!(window as any).Capacitor?.isNativePlatform?.()

/** Send a message to the native StoreKit2Manager via WKWebView bridge. */
function sendStoreKit(msg: Record<string, string>) {
  try {
    ;(window as any).webkit?.messageHandlers?.storekit?.postMessage(msg)
  } catch (e) {
    console.error("[Paywall] StoreKit bridge error:", e)
  }
}

interface StoreKitProduct {
  id: string
  displayName: string
  displayPrice: string
  price: number
  type: string
  period: string
}

interface PaywallProps {
  t: (key: string) => string
  lang: string
  feature?: string
  onClose?: () => void
  userId?: string
  onPurchaseComplete?: () => void
}

export function Paywall({ t, lang, feature, onClose, userId, onPurchaseComplete }: PaywallProps) {
  const [loading, setLoading] = useState<string | null>(null)
  const [selectedPlan, setSelectedPlan] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [products, setProducts] = useState<StoreKitProduct[]>([])
  const [productsLoading, setProductsLoading] = useState(false)
  const native = isNativeApp()

  const isRu = lang === "ru"

  // Register StoreKit callback and load products on native
  useEffect(() => {
    if (!native) return

    setProductsLoading(true)

    const handler = (raw: string) => {
      try {
        const data = JSON.parse(raw)
        console.log("[Paywall] StoreKit callback:", data.action, data)

        if (data.action === "productsLoaded") {
          setProducts(data.products || [])
          setProductsLoading(false)
          if (data.error) {
            console.error("[Paywall] StoreKit product load error:", data.error)
          }
        } else if (data.action === "purchaseResult") {
          if (data.success) {
            // Verify transaction with backend
            verifyAppleTransaction(
              data.transactionId,
              data.productId,
              data.originalTransactionId,
            )
              .then(() => {
                setLoading(null)
                onPurchaseComplete?.()
                onClose?.()
              })
              .catch((err) => {
                console.error("[Paywall] Apple verify error:", err)
                setError(isRu ? "Ошибка активации. Попробуйте позже." : "Activation error. Please try again.")
                setLoading(null)
              })
          } else if (data.cancelled) {
            setLoading(null)
          } else if (data.pending) {
            setError(isRu ? "Покупка ожидает подтверждения." : "Purchase is pending approval.")
            setLoading(null)
          } else if (data.error) {
            setError(data.error)
            setLoading(null)
          }
        } else if (data.action === "restoreResult") {
          if (data.success && data.transactions?.length > 0) {
            // Verify the most recent restored transaction
            const txn = data.transactions[0]
            verifyAppleTransaction(txn.transactionId, txn.productId, txn.originalTransactionId)
              .then(() => {
                setLoading(null)
                onPurchaseComplete?.()
                onClose?.()
              })
              .catch(() => {
                setError(isRu ? "Ошибка восстановления." : "Restore error.")
                setLoading(null)
              })
          } else {
            setError(isRu ? "Нет покупок для восстановления." : "No purchases to restore.")
            setLoading(null)
          }
        }
      } catch (e) {
        console.error("[Paywall] StoreKit callback parse error:", e)
      }
    }

    ;(window as any).__storekit_callback = handler

    // Request products from StoreKit
    sendStoreKit({ action: "loadProducts" })

    return () => {
      delete (window as any).__storekit_callback
    }
  }, [native]) // eslint-disable-line react-hooks/exhaustive-deps

  const handleNativePurchase = useCallback(() => {
    if (!selectedPlan || !userId) return
    setLoading(selectedPlan)
    setError(null)
    sendStoreKit({ action: "purchase", productId: selectedPlan, userId })
  }, [selectedPlan, userId])

  const handleRestore = useCallback(() => {
    setLoading("restore")
    setError(null)
    sendStoreKit({ action: "restorePurchases" })
  }, [])

  const handleWebCheckout = async () => {
    if (!selectedPlan) return
    setLoading(selectedPlan)
    setError(null)
    try {
      const { checkout_url } = await createCheckoutSession(selectedPlan)
      if (checkout_url) {
        window.location.href = checkout_url
      } else {
        setError("Could not create checkout session. Please try again.")
        setLoading(null)
      }
    } catch (err) {
      console.error("[Paywall] checkout error:", err)
      setError(err instanceof Error ? err.message : "Payment system error. Please try again later.")
      setLoading(null)
    }
  }

  // Find products by period for native display
  const monthlyProduct = products.find((p) => p.period === "monthly")
  const annualProduct = products.find((p) => p.period === "annual")

  return (
    <div className="paywall-overlay">
      <div className="paywall-card">
        {onClose ? (
          <button type="button" className="paywall-close" onClick={onClose}>&times;</button>
        ) : null}
        <div className="paywall-icon">
          <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
            <path d="M7 11V7a5 5 0 0 1 10 0v4" />
          </svg>
        </div>

        <h3 className="paywall-title">
          {isRu ? "Разблокируйте big3.me Pro" : "Unlock big3.me Pro"}
        </h3>

        {feature && (
          <p className="paywall-feature">
            {isRu ? `${feature} — доступно в Pro` : `${feature} — available with Pro`}
          </p>
        )}

        <ul className="paywall-benefits">
          <li>{isRu ? "Все активные транзитные аспекты дня" : "All active daily transit aspects"}</li>
          <li>{isRu ? "Детальные описания транзитов" : "Detailed transit descriptions"}</li>
          <li>{isRu ? "Полный космический климат" : "Full cosmic climate analysis"}</li>
          <li>{isRu ? "Полные интерпретации натальной карты" : "Full natal chart interpretations"}</li>
        </ul>

        {native ? (
          <>
            {productsLoading ? (
              <div style={{ textAlign: "center", padding: "16px 0" }}>
                <span className="paywall-spinner" />
              </div>
            ) : products.length > 0 ? (
              <>
                <div className="paywall-prices">
                  {monthlyProduct && (
                    <button
                      type="button"
                      className={`paywall-btn paywall-btn--primary${selectedPlan === monthlyProduct.id ? " paywall-btn--selected" : ""}`}
                      onClick={() => setSelectedPlan(monthlyProduct.id)}
                    >
                      <span className="paywall-btn-price">{monthlyProduct.displayPrice}<small>/{isRu ? "мес" : "mo"}</small></span>
                      <span className="paywall-btn-label">{isRu ? "Ежемесячно" : "Monthly"}</span>
                    </button>
                  )}
                  {annualProduct && (
                    <button
                      type="button"
                      className={`paywall-btn paywall-btn--accent${selectedPlan === annualProduct.id ? " paywall-btn--selected" : ""}`}
                      onClick={() => setSelectedPlan(annualProduct.id)}
                    >
                      <span className="paywall-btn-price">{annualProduct.displayPrice}<small>/{isRu ? "год" : "yr"}</small></span>
                      <span className="paywall-btn-label">
                        {isRu ? "Ежегодно (экономия 37%)" : "Annual (save 37%)"}
                      </span>
                      <span className="paywall-badge">{isRu ? "Лучшая цена" : "Best value"}</span>
                    </button>
                  )}
                </div>

                <button
                  type="button"
                  className="paywall-purchase-btn"
                  disabled={!selectedPlan || !!loading}
                  onClick={handleNativePurchase}
                >
                  {loading && loading !== "restore" ? (
                    <span className="paywall-spinner" />
                  ) : (
                    isRu ? "Подписаться" : "Subscribe"
                  )}
                </button>

                <button
                  type="button"
                  className="paywall-restore-btn"
                  disabled={!!loading}
                  onClick={handleRestore}
                >
                  {loading === "restore" ? (
                    <span className="paywall-spinner" />
                  ) : (
                    isRu ? "Восстановить покупки" : "Restore Purchases"
                  )}
                </button>
              </>
            ) : (
              <p className="paywall-contact-text">
                {isRu
                  ? "Подписки временно недоступны. Попробуйте позже."
                  : "Subscriptions temporarily unavailable. Please try again later."}
              </p>
            )}
          </>
        ) : (
          <>
            <div className="paywall-prices">
              <button
                type="button"
                className={`paywall-btn paywall-btn--primary${selectedPlan === "pro_monthly" ? " paywall-btn--selected" : ""}`}
                onClick={() => setSelectedPlan("pro_monthly")}
              >
                <span className="paywall-btn-price">$7.99<small>/mo</small></span>
                <span className="paywall-btn-label">{isRu ? "Ежемесячно" : "Monthly"}</span>
              </button>

              <button
                type="button"
                className={`paywall-btn paywall-btn--accent${selectedPlan === "pro_annual" ? " paywall-btn--selected" : ""}`}
                onClick={() => setSelectedPlan("pro_annual")}
              >
                <span className="paywall-btn-price">$59.99<small>/yr</small></span>
                <span className="paywall-btn-label">
                  {isRu ? "Ежегодно (экономия 37%)" : "Annual (save 37%)"}
                </span>
                <span className="paywall-badge">{isRu ? "Лучшая цена" : "Best value"}</span>
              </button>
            </div>

            <button
              type="button"
              className="paywall-purchase-btn"
              disabled={!selectedPlan || !!loading}
              onClick={handleWebCheckout}
            >
              {loading ? (
                <span className="paywall-spinner" />
              ) : (
                isRu ? "Оформить подписку" : "Purchase"
              )}
            </button>

            <p className="paywall-compare">
              {isRu
                ? "$7.99/мес vs $5.00/мес при годовой подписке"
                : "$7.99/mo vs $5.00/mo with annual plan"
              }
            </p>
          </>
        )}

        {error && <p style={{ color: "#ff453a", fontSize: "0.8rem", marginBottom: 8, textAlign: "center" }}>{error}</p>}
      </div>
    </div>
  )
}
