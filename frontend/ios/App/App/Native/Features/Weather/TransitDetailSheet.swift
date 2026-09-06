import SwiftUI

/// What the compact row leaves out: the transit's name, the window it runs
/// over, and where both bodies sit. The written interpretation belongs here
/// too and is not wired up yet.
///
/// Unlike the card, this is not drawn on the sky. Weather's own detail sheets
/// drop the weather behind them for a plain surface, and so does this one, so
/// the reading stays legible whatever colour the page underneath happens to
/// be — which means its ink follows the system appearance instead of being
/// white throughout.
struct TransitDetailSheet: View {

    let aspect: ActiveAspect
    var isRetrograde = false
    var positions: TransitPositions = .init()
    var now: Date = Date()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    window
                    where_
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .environment(\.transitPalette, .onSurface)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            TransitGlyphs(aspect: aspect, size: 30, width: nil)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(aspect.title)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)

                if isRetrograde {
                    Text("\u{211E}")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize()
                        .accessibilityLabel("retrograde")
                }
            }

            HStack(spacing: 8) {
                StrengthLabel(strength: aspect.strength)

                Text(String(format: "%.2f° orb", aspect.orb))
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Theme.textStrong)
                    .monospacedDigit()

                if let status = aspect.timing?.status, !status.isEmpty {
                    Text("· \(status)")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    // MARK: - Window

    @ViewBuilder
    private var window: some View {
        if let timing = aspect.timing, timing.start != nil, timing.end != nil {
            SheetCard {
                SheetCardHeader(icon: "calendar", title: "Window", trailing: duration(timing))
                    .padding(.bottom, 14)

                TransitProgressBar(
                    timing: timing,
                    transitObject: aspect.transitObject,
                    showsDates: true,
                    now: now
                )

                if timing.passes.count > 1 {
                    Text("Exact \(timing.passes.count) times: \(timing.passes.map(TransitProgressBar.day).joined(separator: ", "))")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }
            }
        }
    }

    /// "18 days" / "9 h" — the span in whichever unit reads plainly.
    private func duration(_ timing: AspectTiming) -> String? {
        guard let hours = timing.durationHours, hours > 0 else { return nil }
        if hours < 48 { return "\(Int(hours.rounded())) h" }
        return "\(Int((hours / 24).rounded())) days"
    }

    // MARK: - Positions

    @ViewBuilder
    private var where_: some View {
        let transiting = positions.transiting[aspect.transitObject]
        let natal = positions.natal[aspect.natalObject]

        if transiting != nil || natal != nil {
            SheetCard {
                SheetCardHeader(icon: "location.circle", title: "Positions")
                    .padding(.bottom, 4)

                if let transiting {
                    positionRow(object: aspect.transitObject, position: transiting, label: "transiting")
                        .padding(.top, 10)
                }

                if let natal {
                    positionRow(object: aspect.natalObject, position: natal, label: "natal")
                        .padding(.top, 10)
                }
            }
        }
    }

    private func positionRow(object: String, position: ChartPosition, label: String) -> some View {
        HStack(spacing: 8) {
            Text(AstroGlyph.object(object))
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .frame(width: 22, alignment: .leading)

            Text(object)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Spacer(minLength: 6)

            if let degree = position.formattedDegree {
                Text(degree)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Theme.textStrong)
                    .monospacedDigit()
                    .fixedSize()
            }

            // Sign name, no glyph: U+2648-2653 resolve through the emoji font,
            // which the simulator draws as tofu and a device draws in colour.
            // Neither is what this row wants.
            if let sign = position.sign {
                Text(sign)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Theme.textStrong)
                    .lineLimit(1)
                    .fixedSize()
            }

            // A house symbol, not the web's △: that triangle is the glyph for
            // a trine, so on a row about aspects it reads as one.
            if let house = position.houseNumber {
                HStack(spacing: 3) {
                    Image(systemName: "house")
                        .font(.system(size: 11))

                    Text("\(house)")
                        .font(.system(size: 13, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(Theme.textDim)
                .fixedSize()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("house \(house)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(object)")
    }
}

// MARK: - Surface

/// `WeatherCard` in the sheet's palette. The weather one is tuned to float on
/// a saturated sky and reads as a smudge on a plain background.
struct SheetCard<Content: View>: View {

    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
                .allowsHitTesting(false)
        )
    }
}

struct SheetCardHeader: View {

    let icon: String
    let title: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))

            Text(title.uppercased())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(0.5)

            Spacer(minLength: 8)

            if let trailing {
                Text(trailing)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
        }
        .foregroundStyle(Theme.textDim)
    }
}
