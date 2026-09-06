import AVFoundation
import SwiftUI

/// Looping footage behind a weather screen.
///
/// The gradient in `WeatherSky` stays underneath: zones without a clip keep it,
/// and a clip that has not decoded its first frame yet fades in over it rather
/// than flashing black. One file per zone, graded to that zone's palette so the
/// sky still reads as the reading even when it moves.
struct SkyVideo: View {

    let zone: TiiZone

    @State private var isReady = false

    /// Zones ship footage one at a time; the rest fall back to the gradient.
    private var asset: URL? {
        guard let name = Self.clipName(for: zone) else { return nil }
        return Bundle.main.url(forResource: name, withExtension: "mp4")
    }

    static func clipName(for zone: TiiZone) -> String? {
        switch zone {
        case .quiet: return nil          // no clip yet, gradient holds
        case .active: return "sky_active"
        case .hot: return "sky_hot"
        case .extreme: return "sky_extreme"
        }
    }

    var body: some View {
        ZStack {
            if let asset {
                SkyPlayerLayer(url: asset, isReady: $isReady)
                    .opacity(isReady ? 1 : 0)
                    .animation(.easeIn(duration: 0.35), value: isReady)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// `AVPlayerLayer` in a `UIViewRepresentable` because `VideoPlayer` insists on
/// its own controls and pauses when the app backgrounds.
private struct SkyPlayerLayer: UIViewRepresentable {

    let url: URL
    @Binding var isReady: Bool

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.onReady = { isReady = true }
        view.load(url: url)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.load(url: url)
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

        func load(url: URL) {
            guard currentURL != url else { return }
            currentURL = url
            stop()

            let item = AVPlayerItem(url: url)
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
