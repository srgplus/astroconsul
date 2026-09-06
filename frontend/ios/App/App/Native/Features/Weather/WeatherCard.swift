import SwiftUI

/// Translucent panel that floats on the sky gradient, the way Weather's
/// summary and forecast blocks do. Fixed white tints rather than a material:
/// the sky underneath is saturated in both light and dark, so the card has to
/// keep the same contrast either way.
struct WeatherCard<Content: View>: View {

    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
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
