import SwiftUI

/// Every aspect currently inside orb, laid out the way the forecast lays out
/// its days: one line each, glyphs where the weather icon goes, the transit's
/// arc where the temperature bar goes.
///
/// The name of the transit is deliberately absent — three glyphs say it, and
/// the row stays scannable. Tapping one opens the detail sheet. The rows are
/// banded by how fast the transiting body moves, and the header's switch
/// narrows the list to what is actually close.
struct ActiveTransitsCard: View {

    let aspects: [ActiveAspect]
    /// Transiting bodies that are retrograde right now, marked on their rows.
    var retrograde: Set<String> = []
    var positions: TransitPositions = .init()
    var now: Date = Date()

    @ObservedObject private var strings = L10n.shared

    /// On by default, the way the web widget opens: exact and strong only.
    @State private var mostImpact = true
    @State private var selected: ActiveAspect?

    private var visible: [ActiveAspect] {
        mostImpact ? aspects.filter(\.isImpactful) : aspects
    }

    /// The visible aspects in bands, empty bands dropped. Order inside a band
    /// is the order they arrive in, which the view model already sorted by
    /// transiting body and then by orb.
    private var groups: [(group: TransitGroup, aspects: [ActiveAspect])] {
        let bands = Dictionary(grouping: visible) { TransitGroup(transitObject: $0.transitObject) }
        return TransitGroup.allCases.compactMap { group in
            guard let aspects = bands[group], !aspects.isEmpty else { return nil }
            return (group, aspects)
        }
    }

    var body: some View {
        if !aspects.isEmpty {
            WeatherCard {
                header

                if visible.isEmpty {
                    WeatherCardDivider()

                    Text(L("transits.nothingStrong"))
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                }

                ForEach(groups, id: \.group) { band in
                    WeatherCardDivider()

                    Text(band.group.title.uppercased())
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    ForEach(band.aspects) { aspect in
                        WeatherCardDivider()

                        row(aspect)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                            .onTapGesture { selected = aspect }
                    }
                }
            }
            .sheet(item: $selected) { aspect in
                TransitDetailSheet(
                    aspect: aspect,
                    isRetrograde: retrograde.contains(aspect.transitObject),
                    positions: positions,
                    now: now
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 12, weight: .semibold))

            Text(L("transits.title").uppercased())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(0.5)

            Spacer(minLength: 8)

            Text(L("transits.mostImpact"))
                .font(.system(size: 13, design: .rounded))

            SmallSwitch(isOn: $mostImpact)
                .accessibilityLabel(L("transits.mostImpact"))
        }
        .foregroundStyle(.white.opacity(0.7))
        .contentShape(Rectangle())
        .onTapGesture { toggleImpact() }
        .padding(.bottom, 2)
    }

    private func toggleImpact() {
        withAnimation(.easeInOut(duration: 0.2)) { mostImpact.toggle() }
    }

    private func row(_ aspect: ActiveAspect) -> some View {
        HStack(spacing: 10) {
            TransitGlyphs(aspect: aspect)

            if let timing = aspect.timing {
                TransitProgressBar(timing: timing, transitObject: aspect.transitObject, now: now)
            } else {
                // No window came back for this one; hold the column so the
                // orbs and badges stay in line down the card.
                Color.clear.frame(height: 11)
            }

            Text(String(format: "%.2f°", aspect.orb))
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
                .fixedSize()

            StrengthLabel(strength: aspect.strength, width: 66)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            L(
                "transits.orbA11y",
                aspect.title,
                Astro.strength(aspect.strength),
                String(format: "%.2f", aspect.orb)
            )
        )
        .accessibilityAddTraits(.isButton)
    }
}

/// ☉ △ ♆ — transiting body, aspect, natal body. A fixed width keeps the bars
/// lined up down the card however wide the glyphs render.
struct TransitGlyphs: View {

    let aspect: ActiveAspect
    var size: CGFloat = 15
    // Wide enough for the angles, which are written "AC"/"MC" rather than
    // drawn, next to a square or an opposition.
    var width: CGFloat? = 58

    @Environment(\.transitPalette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            Text(AstroGlyph.object(aspect.transitObject))
                .foregroundStyle(palette.primary)

            Text(AstroGlyph.aspect(aspect.aspect))
                .foregroundStyle(palette.secondary)

            Text(AstroGlyph.object(aspect.natalObject))
                .foregroundStyle(palette.primary)
        }
        .font(.system(size: size))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(width: width, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// EXACT / STRONG / MODERATE / WIDE. The web sets these in the aspect's own
/// colour on a tinted pill; over a saturated sky that reads as clutter, so
/// here it is plain white text. The column has a fixed width in the card so
/// the labels line up under each other however long the word is.
struct StrengthLabel: View {

    let strength: String
    var width: CGFloat?

    @Environment(\.transitPalette) private var palette

    var body: some View {
        Text(Astro.strength(strength))
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(palette.primary)
            .lineLimit(1)
            .fixedSize()
            .frame(width: width, alignment: .trailing)
    }
}

/// A switch drawn from shapes rather than SwiftUI's `Toggle`.
///
/// Two reasons. A UIKit switch never sees a tap inside the weather pager's
/// scroll view — the same gesture conflict that keeps a plain-styled `Button`
/// from firing there — and at 51x31 it towers over a 13pt header line with no
/// supported way to shrink it.
struct SmallSwitch: View {

    @Binding var isOn: Bool

    private let width: CGFloat = 40
    private let height: CGFloat = 24

    var body: some View {
        Capsule()
            .fill(isOn ? Theme.ok : Color.white.opacity(0.22))
            .frame(width: width, height: height)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .padding(2)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
            }
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { isOn.toggle() }
            }
            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            .accessibilityValue(isOn ? "on" : "off")
    }
}
