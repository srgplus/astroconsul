import AVFoundation
import UIKit

/// One looping clip, its layer, and the player behind both.
///
/// A `UIView` rather than a bare `AVPlayer` because the pool hands the whole
/// thing on: re-parenting a view that already has a decoded frame costs a
/// `addSubview`, where handing a player to a fresh `AVPlayerLayer` rebuilds the
/// display pipeline.
final class SkyClipView: UIView {

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    let url: URL
    let variant: SkyVideo.Variant

    /// Called once the layer has a frame, so the borrower can fade it in over
    /// the gradient rather than flashing black.
    var onReady: (() -> Void)?

    private var looper: AVPlayerLooper?
    private var queue: AVQueuePlayer?
    private var observation: NSKeyValueObservation?
    /// Parked in the pool: nothing to play into, and a foreground notification
    /// must not start it again.
    private var isParked = false

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var isReadyForDisplay: Bool { playerLayer.isReadyForDisplay }

    init(url: URL, phase: Double, variant: SkyVideo.Variant) {
        self.url = url
        self.variant = variant
        super.init(frame: .zero)

        isUserInteractionEnabled = false
        backgroundColor = .clear

        let item = AVPlayerItem(url: url)
        seek(item, to: phase)

        let player = AVQueuePlayer()
        // Muted so the clip never ducks the user's music.
        player.isMuted = true
        player.actionAtItemEnd = .advance
        // The file is in the bundle, so there is nothing to buffer for and
        // waiting to minimise stalls only delays the first frame.
        player.automaticallyWaitsToMinimizeStalling = false

        looper = AVPlayerLooper(player: player, templateItem: item)
        queue = player

        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill

        // The looper plays *copies* of the template item, so the template's own
        // status never leaves `.unknown`. The layer knows when it has a frame to
        // show, which is the thing being faded in anyway.
        observation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) {
            [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async { self?.onReady?() }
        }

        if !SkyPlayerPool.shared.isSuspended(variant) {
            player.play()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(resumeAfterBackground),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Back on screen after a spell in the pool.
    func resume() {
        isParked = false
        guard !SkyPlayerPool.shared.isSuspended(variant) else { return }
        queue?.play()
    }

    /// Handed back to the pool: paused and detached, but still holding its
    /// decoded item so the next card that wants this clip gets it instantly.
    func park() {
        isParked = true
        onReady = nil
        queue?.pause()
        removeFromSuperview()
    }

    /// Suspended in place, for a clip that is still on screen but covered.
    func setPlaying(_ playing: Bool) {
        guard !isParked else { return }
        playing ? queue?.play() : queue?.pause()
    }

    /// Gives the decoder back. The view is dead after this.
    func tearDown() {
        observation?.invalidate()
        observation = nil
        queue?.pause()
        looper?.disableLooping()
        looper = nil
        queue = nil
        playerLayer.player = nil
        NotificationCenter.default.removeObserver(self)
        removeFromSuperview()
    }

    /// Start this clip part-way through its loop. Seeking the template item
    /// means the offset carries into the copies the looper makes, so the card
    /// keeps its own phase for as long as it lives.
    private func seek(_ item: AVPlayerItem, to phase: Double) {
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

    /// AVFoundation pauses on background; resume so the sky is moving the
    /// moment the app comes back rather than a frozen frame.
    @objc private func resumeAfterBackground() {
        guard !isParked, superview != nil else { return }
        guard !SkyPlayerPool.shared.isSuspended(variant) else { return }
        queue?.play()
    }

    deinit {
        observation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

/// Sky players are borrowed, not built.
///
/// The profile list is a scroll of cards that all want the same four clips, and
/// `List` throws a row away the moment it leaves the screen. Building an
/// `AVQueuePlayer` costs a round trip to mediaserverd and a decoder session, so
/// paying that per row is what made a list of thirty profiles stutter under the
/// finger. A row that leaves hands its player back here instead, and the next
/// card of that zone takes it over.
@MainActor
final class SkyPlayerPool {

    static let shared = SkyPlayerPool()

    /// Players waiting for the next card, by clip.
    private var idle: [URL: [SkyClipView]] = [:]
    private var idleCount = 0

    /// Every player currently alive, borrowed or parked. Weak, so a torn-down
    /// one drops out on its own.
    private let live = NSHashTable<SkyClipView>.weakObjects()

    private var suspended: Set<String> = []

    /// Only what a hand-off needs: a card leaving and a card arriving trade one
    /// player per clip, and there are four clips. Deeper than that and a
    /// screenful of cards sits on a dozen decoder sessions it is not using,
    /// which is what AVFoundation runs out of.
    private static let maxIdle = 4

    /// How long a handed-back player waits for the next card before it is torn
    /// down. Long enough to cover a scroll and a change of mind, short enough
    /// that leaving the screen gives the decoders back.
    private static let idleGrace: TimeInterval = 4

    private var reaper: Timer?

    /// A player for this clip: a parked one if there is one, otherwise a new one
    /// starting at `phase`.
    ///
    /// A reused player keeps the phase it was born with rather than taking the
    /// caller's. The offset only exists so neighbouring cards of one zone do not
    /// play in lockstep, and a pool of players each created for a different card
    /// already gives that.
    func borrow(url: URL, phase: Double, variant: SkyVideo.Variant) -> SkyClipView {
        if var waiting = idle[url], let player = waiting.popLast() {
            idle[url] = waiting.isEmpty ? nil : waiting
            idleCount -= 1
            player.resume()
            return player
        }

        let player = SkyClipView(url: url, phase: phase, variant: variant)
        live.add(player)
        return player
    }

    func giveBack(_ player: SkyClipView) {
        player.park()

        guard idleCount < Self.maxIdle else {
            player.tearDown()
            live.remove(player)
            return
        }

        idle[player.url, default: []].append(player)
        idleCount += 1
        scheduleReap()
    }

    /// Stops every full-screen sky while something covers it.
    ///
    /// The profile list scrolls a stack of card clips over a page whose own
    /// 1080p sky is still decoding behind the sheet, for a wash nobody can see.
    /// This hands that decoder back for as long as the list is up.
    func setPlaying(_ playing: Bool, variant: SkyVideo.Variant) {
        if playing {
            suspended.remove(variant.prefix)
        } else {
            suspended.insert(variant.prefix)
        }

        for player in live.allObjects where player.variant == variant {
            player.setPlaying(playing)
        }
    }

    func isSuspended(_ variant: SkyVideo.Variant) -> Bool {
        suspended.contains(variant.prefix)
    }

    /// Tears down whatever is still parked. Called on a delay after a give-back,
    /// so a scroll keeps its players and a screen that has been left does not.
    private func scheduleReap() {
        reaper?.invalidate()
        reaper = Timer.scheduledTimer(withTimeInterval: Self.idleGrace, repeats: false) { _ in
            Task { @MainActor in SkyPlayerPool.shared.reap() }
        }
    }

    private func reap() {
        reaper = nil
        for player in idle.values.flatMap({ $0 }) {
            player.tearDown()
            live.remove(player)
        }
        idle.removeAll()
        idleCount = 0
    }
}
