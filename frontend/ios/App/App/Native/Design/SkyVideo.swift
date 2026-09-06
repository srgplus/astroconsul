import AVFoundation
import SwiftUI

/// Looping footage behind a weather screen.
///
/// The gradient in `WeatherSky` stays underneath: zones without a clip keep it,
/// and a clip that has not decoded its first frame yet fades in over it rather
/// than flashing black. One file per zone, graded to that zone's palette so the
/// sky still reads as the reading even when it moves.
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

    let zone: TiiZone
    var variant: Variant = .screen

    /// Cards of the same zone share one clip, so without an offset a list of
    /// them plays in lockstep and reads as a repeated image rather than as
    /// separate skies. Callers pass something stable per card, like a profile
    /// id, and the clip starts at its own point in the loop.
    var phase: String?

    @State private var isReady = false

    /// A zone whose clip is missing from the bundle falls back to the gradient
    /// rather than to a black rectangle.
    private var asset: URL? {
        Bundle.main.url(forResource: Self.clipName(for: zone, variant: variant), withExtension: "mp4")
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

    static func clipName(for zone: TiiZone, variant: Variant) -> String {
        "\(variant.prefix)_\(zone.rawValue)"
    }

    var body: some View {
        ZStack {
            if let asset {
                SkyPlayerLayer(url: asset, phase: phaseFraction, isReady: $isReady)
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
private struct SkyPlayerLayer: UIViewRepresentable {

    let url: URL
    let phase: Double
    @Binding var isReady: Bool

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.onReady = { isReady = true }
        view.load(url: url, phase: phase)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.load(url: url, phase: phase)
    }

    static func dismantleUIView(_ view: PlayerView, coordinate: ()) {
        view.stop()
    }

    final class PlayerView: UIView {

        override class var layerClass: AnyClass { AVPlayerLayer.self }

        var onReady: (() -> Void)?

        private var looper: AVPlayerLooper?
        private var queue: AVQueuePlayer?
        private var observation: NSKeyValueObservation?
        private var currentURL: URL?

        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        func load(url: URL, phase: Double) {
            guard currentURL != url else { return }
            currentURL = url
            stop()

            let item = AVPlayerItem(url: url)
            seekToPhase(item: item, phase: phase)
            let player = AVQueuePlayer()
            // Muted so the clip never ducks the user's music.
            player.isMuted = true
            player.actionAtItemEnd = .advance

            looper = AVPlayerLooper(player: player, templateItem: item)
            queue = player

            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill

            // The looper plays *copies* of the template item, so the template's
            // own status never leaves `.unknown`. The layer knows when it has a
            // frame to show, which is the thing being faded in anyway.
            observation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) {
                [weak self] layer, _ in
                guard layer.isReadyForDisplay else { return }
                DispatchQueue.main.async { self?.onReady?() }
            }

            player.play()
            observeLifecycle()
        }

        /// Start this clip part-way through its loop. Seeking the template item
        /// before the looper wraps it means the offset survives into every copy
        /// the looper makes, so the card keeps its own phase forever.
        private func seekToPhase(item: AVPlayerItem, phase: Double) {
            guard phase > 0 else { return }

            Task { @MainActor in
                guard let duration = try? await item.asset.load(.duration),
                      duration.isNumeric, duration.seconds > 0
                else { return }

                let target = CMTime(
                    seconds: duration.seconds * phase.truncatingRemainder(dividingBy: 1),
                    preferredTimescale: duration.timescale
                )
                await item.seek(to: target, toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
            }
        }

        func stop() {
            observation?.invalidate()
            observation = nil
            queue?.pause()
            looper?.disableLooping()
            looper = nil
            queue = nil
            playerLayer.player = nil
            NotificationCenter.default.removeObserver(self)
        }

        /// AVFoundation pauses on background; resume so the sky is moving the
        /// moment the app comes back rather than a frozen frame.
        private func observeLifecycle() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(resume),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )
        }

        @objc private func resume() {
            queue?.play()
        }

        deinit {
            observation?.invalidate()
            NotificationCenter.default.removeObserver(self)
        }
    }
}
