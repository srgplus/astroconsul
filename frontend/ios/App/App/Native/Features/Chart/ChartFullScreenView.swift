import SwiftUI

/// The same wheel `ChartWheelCard` draws, across the whole screen.
///
/// Why both. On the card the wheel is about 270 points wide, because a card is
/// the screen minus a margin minus its own padding, and the glyphs on it are
/// thirteen points — enough to say *there is a chart here*, not enough to read
/// one off. Full screen the same wheel is a third wider before anything is
/// zoomed, and the two bars around it hold the controls the card kept under it.
///
/// A third wider is still a phone, so the wheel is pinchable to 3× on top of
/// that, which is where a stellium in one sign becomes four separate glyphs.
/// Pinch and not a fixed enlargement, and pinch rather than tap-to-zoom: the
/// wheel already spends the single tap on picking out a planet or a line, and
/// a double tap over it would put a quarter-second of hesitation on every one
/// of those taps while the system waited to see if a second was coming.
///
/// The zoom moves the wheel's own size rather than scaling the drawn result.
/// The wheel is one `Canvas`, so `scaleEffect` alone would stretch a bitmap
/// and 3× would be a blur of soft hairlines; the effect carries only the live
/// pinch, and the moment the fingers lift the size is committed and the whole
/// thing is redrawn sharp at its new radius.
struct ChartFullScreenView: View {

    let positions: TransitPositions
    var aspects: [ActiveAspect] = []
    /// The moment the reading was cast for, carried through to the detail
    /// sheet the caption opens — the same value the card hands it.
    var now: Date = Date()
    /// Drawn frosted behind the wheel, so the screen stands on the sky it was
    /// opened from instead of on a slab of grey.
    var zone: TiiZone = .active

    /// The card's state, shared rather than copied: what is switched or picked
    /// out here is still switched or picked out on the card underneath.
    @Binding var mode: ChartMode
    @Binding var showsSpecialPoints: Bool
    @Binding var selection: ChartWheelSelection?

    @Environment(\.dismiss) private var dismiss

    @State private var detail: ActiveAspect?

    /// The zoom the last pinch settled on, and the pinch in progress. The
    /// wheel is drawn at `zoom` and scaled by the pinch on top of it.
    @State private var zoom: CGFloat = 1
    @State private var pinch: CGFloat = 1
    /// Where the wheel has been dragged to, and how far this drag has come.
    @State private var offset: CGSize = .zero
    @State private var drag: CGSize = .zero
    /// Whether a pinch is running, which is the one thing the pan has to know
    /// about. `DragGesture` cannot be asked for two fingers the way UIKit's
    /// pan can, so during a pinch it follows one of the two and would slide
    /// the wheel out from under the zoom.
    @State private var isPinching = false

    /// Past 3× the ring is wider than three screens and panning it costs more
    /// than the detail is worth.
    private static let maxZoom: CGFloat = 3

    private var chart: ChartWheelData? {
        ChartWheelData(
            positions: positions,
            aspects: aspects,
            mode: mode,
            showsSpecialPoints: showsSpecialPoints
        )
    }

    var body: some View {
        ZStack {
            // In the view and not in `.presentationBackground`: a cover with
            // no background of its own shows the window's white, and every
            // glyph and hairline on this screen is white.
            WeatherGlassBackdrop(zone: zone)

            VStack(spacing: 0) {
                topBar

                if let chart {
                    wheel(chart)

                    bottomBar(chart)
                } else {
                    Spacer()
                }
            }
        }
        .tint(.white)
        // The screen is a night sky whatever the device is set to, so the ink
        // on it is drawn for one — the same override the profile list and the
        // search screen carry over their own frosted sky.
        .environment(\.colorScheme, .dark)
        .sheet(item: $detail) { aspect in
            TransitDetailSheet(
                aspect: aspect,
                isRetrograde: positions.transiting[aspect.transitObject]?.retrograde == true,
                positions: positions,
                now: now
            )
        }
    }

    // MARK: - Bars

    /// Title, the ring switch, and the way out. The switch rides up here
    /// rather than down with the other one because that is where the card
    /// keeps it, and the two surfaces are meant to read as one chart.
    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.dotted.circle")
                .font(.system(size: 12, weight: .semibold))

            Text(L("chart.title").uppercased())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(0.5)

            Spacer(minLength: 8)

            ChartModePicker(mode: $mode)

            closeButton
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    /// Weather's close button: a glyph on a circle, floating over the content
    /// rather than sitting in a titled navigation bar. On glass here, because
    /// what is behind it is a sky and not a plain surface.
    private var closeButton: some View {
        Image(systemName: "xmark")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 32, height: 32)
            .weatherGlass(in: Circle())
            .contentShape(Circle())
            .onTapGesture { dismiss() }
            .accessibilityLabel(L("common.close"))
            .accessibilityAddTraits(.isButton)
    }

    /// What the last tap named, and the switch for the inner rows. The panel
    /// is the card's own, so the two rows sit where a reader last saw them.
    private func bottomBar(_ chart: ChartWheelData) -> some View {
        WeatherCard {
            ChartCaption(
                chart: chart,
                selection: selection,
                // The one gesture on this screen that nothing else announces.
                hint: L("chart.tapHintZoom"),
                onAspect: { detail = $0 }
            )

            WeatherCardDivider()

            ChartSpecialPointsRow(isOn: $showsSpecialPoints)
                .padding(.top, 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    // MARK: - Wheel

    private func wheel(_ chart: ChartWheelData) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let base = min(size.width, size.height)
            let scale = displayZoom
            let shift = clamped(
                CGSize(width: offset.width + drag.width, height: offset.height + drag.height),
                content: base * scale,
                in: size
            )

            ChartWheelView(chart: chart, selection: $selection)
                .frame(width: base * zoom, height: base * zoom)
                .scaleEffect(scale / zoom)
                .offset(shift)
                .frame(width: size.width, height: size.height)
                .clipped()
                .contentShape(Rectangle())
                // Simultaneous, and alongside the wheel's own tap: a pinch and
                // a pan cannot both be the finger's intent as a tap, so the
                // three sort themselves out by how far the finger travels.
                .simultaneousGesture(
                    MagnifyGesture(minimumScaleDelta: 0.01)
                        .onChanged { value in
                            isPinching = true
                            // Whatever the pan picked up on the way into the
                            // pinch is thrown away rather than carried.
                            drag = .zero
                            pinch = value.magnification
                        }
                        .onEnded { _ in
                            commitPinch(base: base, in: size)
                            isPinching = false
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            guard !isPinching else { return }
                            drag = value.translation
                        }
                        .onEnded { _ in
                            guard !isPinching else {
                                drag = .zero
                                return
                            }
                            commitDrag(base: base, scale: scale, in: size)
                        }
                )
                .overlay(alignment: .bottomTrailing) {
                    if scale > 1.01 {
                        resetButton
                            .padding(.trailing, 16)
                            .padding(.bottom, 4)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: scale > 1.01)
        }
        .animation(.easeInOut(duration: 0.25), value: mode)
        .animation(.easeInOut(duration: 0.25), value: showsSpecialPoints)
    }

    /// Back to the whole wheel, and how far in it currently is. One control
    /// for both, because the number is only worth showing while there is
    /// something to undo.
    private var resetButton: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 11, weight: .semibold))

            Text(String(format: "%.1f×", displayZoom))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .weatherGlass(in: Capsule())
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.28)) {
                zoom = 1
                pinch = 1
                offset = .zero
                drag = .zero
                isPinching = false
            }
        }
        .accessibilityLabel(L("chart.fit"))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Zoom

    /// What the wheel is actually drawn at: the committed zoom times the pinch
    /// in progress, held inside the range. Clamping here rather than when the
    /// fingers lift is what keeps a pinch past either end from snapping when
    /// it is released.
    private var displayZoom: CGFloat {
        min(max(zoom * pinch, 1), Self.maxZoom)
    }

    /// Fold the finished pinch into the size the wheel is drawn at. The wheel
    /// keeps its centre and its diameter across the swap — `displayZoom` is
    /// the same number before and after — so nothing moves on screen; only the
    /// resolution it is drawn at changes.
    private func commitPinch(base: CGFloat, in size: CGSize) {
        let settled = displayZoom
        offset = clamped(offset, content: base * settled, in: size)
        zoom = settled
        pinch = 1
    }

    private func commitDrag(base: CGFloat, scale: CGFloat, in size: CGSize) {
        offset = clamped(
            CGSize(width: offset.width + drag.width, height: offset.height + drag.height),
            content: base * scale,
            in: size
        )
        drag = .zero
    }

    /// A pan that cannot lose the wheel: it stops when an edge of the drawing
    /// reaches the matching edge of the screen, and an axis with room to spare
    /// stays centred rather than sliding.
    private func clamped(_ shift: CGSize, content: CGFloat, in size: CGSize) -> CGSize {
        let x = max((content - size.width) / 2, 0)
        let y = max((content - size.height) / 2, 0)
        return CGSize(
            width: min(max(shift.width, -x), x),
            height: min(max(shift.height, -y), y)
        )
    }
}

#if DEBUG
#Preview {
    struct Harness: View {
        @State private var mode: ChartMode = .transit
        @State private var showsSpecialPoints = false
        @State private var selection: ChartWheelSelection?

        var body: some View {
            ChartFullScreenView(
                positions: WeatherPreviewData.positions,
                aspects: WeatherPreviewData.aspects,
                zone: .active,
                mode: $mode,
                showsSpecialPoints: $showsSpecialPoints,
                selection: $selection
            )
        }
    }

    return Harness()
}
#endif
