import Intents
import UIKit
import UserNotifications

/// Turns a push from a person (a message, a like, a follow) into the kind
/// Messages shows: the person's face on the left with the app's icon small in
/// its corner, and their name as the title.
///
/// The app has no photos, so the face is the one the app gives everyone, the
/// Sun sign on a charcoal circle (`ChatAvatar`, in its dark colours: a push
/// is drawn once and read in either appearance). The server says who the
/// push is from in `sender`; iOS draws the rest from an incoming
/// `INSendMessageIntent`, which is what a communication notification is.
///
/// Anything missing or failing leaves the push as the server wrote it, which
/// reads well on its own: the name is in its title or its sentence.
final class NotificationService: UNNotificationServiceExtension {

    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var original: UNNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        original = request.content

        guard let sender = Sender(request.content.userInfo) else {
            finish(with: request.content)
            return
        }

        let content = request.content.mutableCopy() as? UNMutableNotificationContent ?? UNMutableNotificationContent()
        // A like or a follow names the person in its sentence; with the name
        // as the title, the line under it says only what they did.
        if let short = request.content.userInfo["short_body"] as? String, !short.isEmpty {
            content.body = short
        }

        let image = Avatar.image(sign: sender.sign)
        let person = INPerson(
            personHandle: INPersonHandle(value: sender.id, type: .unknown),
            nameComponents: nil,
            displayName: sender.name,
            image: image,
            contactIdentifier: nil,
            customIdentifier: sender.id
        )
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: nil,
            conversationIdentifier: content.threadIdentifier.isEmpty ? sender.id : content.threadIdentifier,
            serviceName: nil,
            sender: person,
            attachments: nil
        )
        intent.setImage(image, forParameterNamed: \.sender)

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate { [weak self] error in
            if let error {
                NSLog("[Push] donating the message failed: \(error.localizedDescription)")
            }
            do {
                self?.finish(with: try content.updating(from: intent))
            } catch {
                NSLog("[Push] drawing the sender failed: \(error.localizedDescription)")
                self?.finish(with: content)
            }
        }
    }

    /// iOS is about to give up on the extension: the push goes as it came.
    override func serviceExtensionTimeWillExpire() {
        if let original { finish(with: original) }
    }

    /// Hands iOS the push once, whichever of the drawing and the deadline
    /// gets here first.
    private func finish(with content: UNNotificationContent) {
        lock.lock()
        let handler = contentHandler
        contentHandler = nil
        lock.unlock()
        handler?(content)
    }
}

/// Who a push is from, as the server wrote it: an id that stays the same for
/// the person, their name, and the sign their Sun is in.
private struct Sender {
    let id: String
    let name: String
    let sign: String?

    init?(_ userInfo: [AnyHashable: Any]) {
        guard let sender = userInfo["sender"] as? [String: Any],
              let id = sender["id"] as? String, !id.isEmpty,
              let name = sender["name"] as? String, !name.isEmpty
        else { return nil }
        self.id = id
        self.name = name
        sign = sender["sign"] as? String
    }
}

/// The face: the Sun sign's glyph on a charcoal circle, a person's outline
/// for someone with no chart, as `ChatAvatar` draws them in the dark.
private enum Avatar {

    /// Drawn at the size Siri's suggestions show it; the banner takes it
    /// smaller.
    private static let side: CGFloat = 120

    private static let circle = UIColor(red: 0.16, green: 0.16, blue: 0.16, alpha: 1)

    /// Aries to Pisces, U+2648 to U+2653, as `AstroGlyph.sign` has them.
    private static let signs = [
        "Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo",
        "Libra", "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces",
    ]

    static func image(sign: String?) -> INImage? {
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        let drawn = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            circle.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()

            if let glyph = glyph(sign) {
                // Pinned to its text form with U+FE0E, or it is an emoji tile.
                let text = NSAttributedString(
                    string: glyph + "\u{FE0E}",
                    attributes: [
                        .font: UIFont.systemFont(ofSize: side * 0.72),
                        .foregroundColor: UIColor.white,
                    ]
                )
                let box = text.size()
                text.draw(at: CGPoint(x: (side - box.width) / 2, y: (side - box.height) / 2))
            } else if let person = UIImage(
                systemName: "person.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: side * 0.42, weight: .medium)
            )?.withTintColor(UIColor.white.withAlphaComponent(0.9), renderingMode: .alwaysOriginal) {
                person.draw(at: CGPoint(x: (side - person.size.width) / 2, y: (side - person.size.height) / 2))
            }
        }
        guard let data = drawn.pngData() else {
            NSLog("[Push] the sender's face could not be encoded")
            return nil
        }
        return INImage(imageData: data)
    }

    private static func glyph(_ sign: String?) -> String? {
        guard let sign, let index = signs.firstIndex(of: sign.capitalized),
              let scalar = Unicode.Scalar(0x2648 + index)
        else { return nil }
        return String(Character(scalar))
    }
}
