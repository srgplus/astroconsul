import SwiftUI

/// A generic view cannot hold static storage, so the card's constants live here.
private enum CardGlass {
    /// Enough dark for white text to hold over a bright sky, little enough
    /// that the panel still reads as glass rather than a grey box.
    static let tint: Double = 0.3
    static let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
}

/// Frosted panel that floats on the sky, the way Weather's summary and
/// forecast blocks do.
///
/// Glass rather than a flat white wash: a wash is only transparency, so the
/// sky video kept moving through the text. Glass blurs what is behind it, and
/// the tint here is heavier than the bottom bar's because these panels carry
/// paragraphs, not a pair of glyphs.
struct WeatherCard<Content: View>: View {

    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .weatherGlass(in: CardGlass.shape, tint: CardGlass.tint)
        .overlay(
            CardGlass.shape
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                // Decoration only: a hit-testing overlay swallows taps meant
                // for the controls underneath it.
                .allowsHitTesting(false)
        )
    }
}

/// Small caps header inside a card — Weather's "10-DAY FORECAST" line.
struct WeatherCardHeader: View {

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
        .foregroundStyle(.white.opacity(0.7))
    }
}

struct WeatherCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
            .frame(height: 1)
    }
}
