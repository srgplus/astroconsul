import SwiftUI

struct ProfileRowView: View {

    let profile: ProfileSummary
    let isPrimary: Bool

    private var tii: Double? { profile.latestTransit?.tii }
    private var feelsLike: String? { profile.latestTransit?.feelsLike }

    var body: some View {
        HStack(spacing: Theme.Spacing.base) {
            avatar

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(profile.profileName)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    if isPrimary {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textDim)
                            .accessibilityLabel("Primary profile")
                    }
                }

                Text("@\(profile.username)")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)

                if let location = profile.locationName, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Theme.textDim.opacity(0.8))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Theme.Spacing.tight)

            if let tii {
                tiiBadge(tii)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: - Pieces

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Theme.surfaceSoft)
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))

            Text(initial)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textStrong)
        }
        .frame(width: 44, height: 44)
    }

    private var initial: String {
        let source = profile.profileName.isEmpty ? profile.username : profile.profileName
        return String(source.prefix(1)).uppercased()
    }

    private func tiiBadge(_ value: Double) -> some View {
        let color = Theme.zoneColor(tii: value)

        return VStack(spacing: 2) {
            HStack(spacing: 4) {
                if let emoji = FeelsLike.emoji(for: feelsLike) {
                    Text(emoji).font(.system(size: 11))
                }
                Text("\(Int(value.rounded()))")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }

            if let feelsLike, !feelsLike.isEmpty {
                Text(feelsLike)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(color.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tension index \(Int(value.rounded()))\(feelsLike.map { ", \($0)" } ?? "")")
    }
}
