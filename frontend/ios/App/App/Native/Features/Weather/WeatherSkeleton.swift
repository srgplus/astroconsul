import SwiftUI

/// The shape of a card before its data lands.
///
/// An empty page under the hero reads as a screen that failed to draw, and
/// cards appearing one by one shove everything below them down the moment the
/// reader starts reading. A skeleton holds both the space and the rhythm of
/// the card it stands in for, so the arrival is a fill rather than a jump.
struct WeatherSkeleton: View {

    enum Kind {
        /// Three lines of prose, then the day's transits.
        case summary
        /// A header and ten day rows.
        case forecast
        /// A header, a band label and its transit rows.
        case transits
    }

    let kind: Kind

    /// One pulse for the whole card rather than per bar: bars fading out of
    /// step with each other read as a glitch, not as waiting.
    @State private var dim = false

    var body: some View {
        WeatherCard {
            switch kind {
            case .summary: summary
            case .forecast: forecast
            case .transits: transits
            }
        }
        .opacity(dim ? 0.6 : 1)
        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: dim)
        .onAppear { dim = true }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }

    // MARK: - Shapes

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            line(height: 15)
            line(height: 15).padding(.top, 9)
            bar(width: 152, height: 15).padding(.top, 9)

            WeatherCardDivider().padding(.top, 14)

            ForEach([CGFloat(158), 128, 142], id: \.self) { width in
                HStack(spacing: 10) {
                    bar(width: width, height: 13)
                    Spacer(minLength: 8)
                    bar(width: 54, height: 13)
                    bar(width: 30, height: 13)
                }
                .padding(.vertical, 10)
            }
        }
    }

    private var forecast: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ForEach(0..<10, id: \.self) { _ in
                WeatherCardDivider()

                HStack(spacing: 10) {
                    bar(width: 44, height: 15)
                    bar(width: 20, height: 20, radius: 6)
                    track
                    bar(width: 34, height: 17)
                }
                .padding(.vertical, 10)
            }
        }
    }

    private var transits: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            WeatherCardDivider()

            bar(width: 118, height: 11)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ForEach(0..<4, id: \.self) { _ in
                WeatherCardDivider()

                HStack(spacing: 10) {
                    bar(width: 48, height: 13)
                    track
                    bar(width: 36, height: 12)
                    bar(width: 56, height: 12)
                }
                .padding(.vertical, 12)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            bar(width: 14, height: 12, radius: 3)
            bar(width: 108, height: 12)
            Spacer(minLength: 8)
            bar(width: 46, height: 12)
        }
        .padding(.bottom, 12)
    }

    /// What a progress track leaves behind. It keeps the track's own weight
    /// rather than the bars', so the row reads as the row it becomes.
    private var track: some View {
        Capsule()
            .fill(Color.white.opacity(0.26))
            .frame(height: 5)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Pieces

    /// A full-width line of prose.
    private func line(height: CGFloat) -> some View {
        bar(height: height).frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Fixed widths rather than fractions of the card: a fraction needs the
    /// card's width measured back into the layout, and the extra pass buys
    /// nothing for bars nobody reads.
    private func bar(
        width: CGFloat? = nil,
        height: CGFloat,
        radius: CGFloat = 4
    ) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white.opacity(0.34))
            .frame(width: width, height: height)
    }
}
