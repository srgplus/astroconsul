import AVFoundation
import SwiftUI

/// Looping footage behind a weather screen.
///
/// The gradient in `WeatherSky` stays underneath: states without a clip keep
/// it, and a clip that has not decoded its first frame yet fades in over it
/// rather than flashing black. One file per feels-like state, so two readings
/// that share a zone no longer share a sky.
struct SkyVideo: View {

    /// A profile card is a 358×108pt sliver, so it gets its own crop of the
    /// footage at roughly an eighth of the pixels. Decoding the full-screen
    /// clip for a row would make scrolling a list of thirty profiles expensive
    /// for detail nobody can see at that size.
    enum Variant {
        case screen
        case card

        var prefix: String {
            switch self {
            case .screen: return "sky"
            case .card: return "card"
            }
        }
    }

    let state: SkyState
    var variant: Variant = .screen

    /// Cards of the same state share one clip, so without an offset a list of
    /// them plays in lockstep and reads as a repeated image rather than as
    /// separate skies. Callers pass something stable per card, like a profile
    /// id, and the clip starts at its own point in the loop.
    var phase: String?

    @State private var isReady = false

    /// A state whose clip is missing from the bundle falls back to the
    /// gradient rather than to a black rectangle.
    private var asset: URL? {
        Bundle.main.url(forResource: Self.clipName(for: state, variant: variant), withExtension: "mp4")
    }

    /// 0..<1 position in the loop to start at. Hashing the caller's key by hand
    /// rather than with `hashValue`, which is seeded per launch and would move
    /// a card's sky every time the app starts.
    private var phaseFraction: Double {
        guard let phase, !phase.isEmpty else { return 0 }
        let digest = phase.unicodeScalars.reduce(UInt64(5381)) { hash, scalar in
            hash &* 33 &+ UInt64(scalar.value)
        }
        return Double(digest % 1000) / 1000
    }

    static func clipName(for state: SkyState, variant: Variant) -> String {
        "\(variant.prefix)_\(state.rawValue)"
    }

    var body: some View {
        ZStack {
            if let asset {
                SkyPlayerLayer(url: asset, phase: phaseFraction, variant: variant, isReady: $isReady)
                    .opacity(isReady ? 1 : 0)
                    .animation(.easeIn(duration: 0.35), value: isReady)
            }
        }
        // Only the full-screen sky bleeds past the insets; a card must stay
        // inside the rounded rect its parent clips it to.
        .modifier(BleedToEdges(isEnabled: variant == .screen))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BleedToEdges: ViewModifier {

    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.ignoresSafeArea()
        } else {
            content
        }
    }
}

/// `AVPlayerLayer` in a `UIViewRepresentable` because `VideoPlayer` insists on
/// its own controls and pauses when the app backgrounds.
///
/// The view SwiftUI owns here is an empty host. The player itself comes from
/// `SkyPlayerPool` and goes back to it when the row leaves, because a `List`
/// destroys a row the moment it scrolls off and building a player per row is
/// what a scroll of profile cards cannot afford.
private struct SkyPlayerLayer: UIViewRepresentable {

    let url: URL
    let phase: Double
    let variant: SkyVideo.Variant
    @Binding var isReady: Bool

    func makeUIView(context: Context) -> SkyClipHost {
        let host = SkyClipHost()
        host.onReady = { isReady = true }
        host.show(url: url, phase: phase, variant: variant)
        return host
    }

    func updateUIView(_ host: SkyClipHost, context: Context) {
        host.onReady = { isReady = true }
        host.show(url: url, phase: phase, variant: variant)
    }

    /// The label matters: spelled anything but `coordinator` this does not
    /// satisfy the protocol and is never called, which left every row's player
    /// to be collected whenever ARC got round to it instead of when the row
    /// went away.
    static func dismantleUIView(_ host: SkyClipHost, coordinator: ()) {
        host.release()
    }
}

/// The empty view SwiftUI owns, holding whichever pooled clip it has borrowed.
final class SkyClipHost: UIView {

    var onReady: (() -> Void)?

    private var clip: SkyClipView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(url: URL, phase: Double, variant: SkyVideo.Variant) {
        if let clip, clip.url == url { return }
        release()

        let borrowed = SkyPlayerPool.shared.borrow(url: url, phase: phase, variant: variant)
        borrowed.frame = bounds
        borrowed.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        borrowed.onReady = { [weak self] in self?.onReady?() }
        addSubview(borrowed)
        clip = borrowed

        // A borrowed player already has a frame up, so nothing will call the
        // layer's observer again. Async because this runs inside SwiftUI's own
        // update, and `isReady` is its state.
        if borrowed.isReadyForDisplay {
            DispatchQueue.main.async { [weak self] in self?.onReady?() }
        }
    }

    func release() {
        guard let clip else { return }
        self.clip = nil
        SkyPlayerPool.shared.giveBack(clip)
    }
}
