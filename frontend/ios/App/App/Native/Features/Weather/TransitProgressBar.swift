import SwiftUI

/// The arc of one transit: when it opened, when it peaks, when it closes, and
/// where today sits on that span.
///
/// The track is the whole window. The colour under it is an influence curve —
/// a bell peaking where the aspect perfects, tinted blue through yellow to red
/// by how heavy the transiting body is — and it is revealed only as far as
/// now, so the filled part reads as elapsed. Ported from the web app's
/// `TransitProgressBar` so both apps draw the same shape.
///
/// The card draws it bare, one row per transit the way the forecast draws a
/// day. `showsDates` adds the start, peak and end labels, which is what the
/// detail sheet wants and a compact row has no space for.
struct TransitProgressBar: View {

    let timing: AspectTiming
    let transitObject: String
    var showsDates = false
    /// Injected rather than read from the clock so previews are stable.
    var now: Date = Date()

    @Environment(\.transitPalette) private var palette

    private let track: CGFloat = 6
    private let dot: CGFloat = 10
    private let notch: CGFloat = 11

    var body: some View {
        if let span = Span(timing: timing, now: now) {
            if showsDates {
                VStack(alignment: .leading, spacing: 3) {
                    peakLabel(span)
                    bar(span)
                    edgeLabels(span)
                }
            } else {
                bar(span)
            }
        }
    }

    // MARK: - Pieces

    private func bar(_ span: Span) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let elapsed = max(width * span.nowFraction, track)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.track)
                    .frame(height: track)

                // The gradient spans the whole window and is masked back to
                // now, so the colours stay put as the day moves along it.
                Capsule()
                    .fill(
                        LinearGradient(
                            stops: TransitIntensity.stops(peak: span.peakFraction, object: transitObject),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width, height: track)
                    .mask(alignment: .leading) {
                        Capsule()
                            .frame(width: elapsed, height: track)
                    }

                ForEach(Array(span.passFractions.enumerated()), id: \.offset) { _, fraction in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(palette.secondary)
                        .frame(width: 2, height: notch)
                        .offset(x: clamp(width * fraction - 1, in: width - 2))
                }

                // Solid, no ring: the gradient already carries the colour,
                // and a rimmed dot reads as a control.
                Circle()
                    .fill(palette.primary)
                    .frame(width: dot, height: dot)
                    .offset(x: clamp(width * span.nowFraction - dot / 2, in: width - dot))
            }
            .frame(height: geometry.size.height, alignment: .center)
        }
        .frame(height: notch)
    }

    @ViewBuilder
    private func peakLabel(_ span: Span) -> some View {
        if let peak = span.peak {
            GeometryReader { geometry in
                Text(Self.day(peak))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.secondary)
                    .fixedSize()
                    // `.position` centres on the point, so the label sits over
                    // its notch without measuring the text.
                    .position(
                        x: min(max(geometry.size.width * span.peakFraction, 22), geometry.size.width - 22),
                        y: geometry.size.height / 2
                    )
            }
            .frame(height: 14)
        }
    }

    private func edgeLabels(_ span: Span) -> some View {
        HStack(spacing: 8) {
            Text(Self.day(span.start))
            Spacer(minLength: 0)
            Text(Self.day(span.end))
        }
        .font(.system(size: 11, design: .rounded))
        .foregroundStyle(palette.tertiary)
    }

    /// Keeps a marker inside the track at both ends.
    private func clamp(_ value: CGFloat, in limit: CGFloat) -> CGFloat {
        min(max(value, 0), max(limit, 0))
    }

    static func day(_ date: Date) -> String {
        formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()
}

// MARK: - Geometry

private extension TransitProgressBar {

    /// The window resolved to fractions of the track, or `nil` when the report
    /// came back without timing.
    struct Span {
        let start: Date
        let end: Date
        let peak: Date?
        let nowFraction: CGFloat
        let peakFraction: CGFloat
        let passFractions: [CGFloat]

        init?(timing: AspectTiming, now: Date) {
            guard let start = timing.start, let end = timing.end else { return nil }
            let total = end.timeIntervalSince(start)
            guard total > 0 else { return nil }

            func fraction(_ date: Date) -> CGFloat {
                CGFloat(min(max(date.timeIntervalSince(start) / total, 0), 1))
            }

            self.start = start
            self.end = end
            self.peak = timing.peak
            self.nowFraction = fraction(now)
            self.peakFraction = timing.peak.map(fraction) ?? 0.5
            self.passFractions = timing.passes.map(fraction)
        }
    }
}

// MARK: - Colour

/// The influence curve's palette: blue at rest, yellow building, red at the
/// peak of a heavy transit. The scale and the weights are the web app's.
enum TransitIntensity {

    /// How much of the scale a transiting body can reach. The Moon barely
    /// registers; the outer planets saturate it.
    static func weight(for object: String) -> Double {
        min(weights[object] ?? 1.0, 1.0)
    }

    static func peakColor(for object: String) -> Color {
        color(at: weight(for: object))
    }

    /// Gradient stops sampling the bell curve every 5% of the window.
    static func stops(peak: CGFloat, object: String) -> [Gradient.Stop] {
        let ceiling = weight(for: object)
        return stride(from: 0.0, through: 1.0, by: 0.05).map { point in
            Gradient.Stop(
                color: color(at: influence(at: point, peak: Double(peak)) * ceiling),
                location: point
            )
        }
    }

    /// Bell curve centred on the exact moment, falling off either side.
    private static func influence(at point: Double, peak: Double) -> Double {
        let distance = point - peak
        return exp(-8 * distance * distance)
    }

    private static func color(at intensity: Double) -> Color {
        let value = min(max(intensity, 0), 1)

        for index in 0..<(scale.count - 1) {
            let lower = scale[index]
            let upper = scale[index + 1]
            guard value >= lower.stop, value <= upper.stop else { continue }

            let ratio = (value - lower.stop) / (upper.stop - lower.stop)
            return Color(
                red: lower.red + (upper.red - lower.red) * ratio,
                green: lower.green + (upper.green - lower.green) * ratio,
                blue: lower.blue + (upper.blue - lower.blue) * ratio
            )
        }

        let last = scale[scale.count - 1]
        return Color(red: last.red, green: last.green, blue: last.blue)
    }

    private static let weights: [String: Double] = [
        "Sun": 1.0, "Moon": 0.5, "Mercury": 1.0, "Venus": 1.0, "Mars": 1.0,
        "Jupiter": 1.3, "Saturn": 1.3, "Uranus": 1.5, "Neptune": 1.5, "Pluto": 1.5,
    ]

    /// #5AC8FA → #FFD60A → #FF375F, in unit components.
    private static let scale: [(stop: Double, red: Double, green: Double, blue: Double)] = [
        (0.0, 90 / 255, 200 / 255, 250 / 255),
        (0.5, 255 / 255, 214 / 255, 10 / 255),
        (1.0, 255 / 255, 55 / 255, 95 / 255),
    ]
}
