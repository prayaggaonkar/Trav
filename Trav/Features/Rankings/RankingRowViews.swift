import SwiftUI

struct RankedExperienceRow: View {
    let rank: Int
    let experience: ExperienceSummary
    let axis: RankingAxis
    let onTap: () -> Void
    var onCreatorTap: (() -> Void)? = nil

    private var scoreText: String {
        guard let score = RankingScore.value(from: experience, axis: axis) else { return "—" }
        return String(format: "%.1f", score)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: TravSpacing.md) {
                Text("\(rank)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(rank <= 3 ? TravColors.accent : TravColors.muted)
                    .frame(width: 28, alignment: .center)

                RemoteImage(
                    url: experience.coverImageURL,
                    height: 56,
                    cornerRadius: TravRadius.sm
                )
                .frame(width: 56, height: 56)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: TravRadius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(experience.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(TravColors.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: TravSpacing.xs) {
                        Button {
                            onCreatorTap?()
                        } label: {
                            Text(experience.creator.displayName)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(TravColors.muted)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)

                        Text("·")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(TravColors.muted.opacity(0.6))

                        Text(cityLabel)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(TravColors.muted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: TravSpacing.xs)

                rankingScorePill(scoreText)
            }
            .padding(.vertical, TravSpacing.sm)
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .contentShape(Rectangle())
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.98))
    }

    private var cityLabel: String {
        if let name = experience.cityName, !name.isEmpty, name.lowercased() != "unknown" {
            return name
        }
        if let city = MockData.cities.first(where: { $0.id == experience.cityID }) {
            return city.name
        }
        return experience.displayCityName
    }
}

struct RankedCreatorRow: View {
    let rank: Int
    let creator: RankedCreator
    let onTap: () -> Void

    private var scoreText: String {
        guard creator.ratedExperienceCount > 0 else { return "—" }
        return String(format: "%.1f", creator.averageScore)
    }

    private var experienceLabel: String {
        let rated = creator.ratedExperienceCount
        if rated == 0 {
            return "No ratings yet"
        }
        return rated == 1 ? "1 rated experience" : "\(rated) rated experiences"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: TravSpacing.md) {
                Text("\(rank)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(rank <= 3 ? TravColors.accent : TravColors.muted)
                    .frame(width: 28, alignment: .center)

                AvatarView(url: creator.profile.avatarURL, size: 48)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(creator.profile.displayName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(TravColors.primary)
                            .lineLimit(1)
                        if creator.profile.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(TravColors.muted)
                        }
                    }
                    Text("@\(creator.profile.username) · \(experienceLabel)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(TravColors.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: TravSpacing.xs)

                rankingScorePill(scoreText)
            }
            .padding(.vertical, TravSpacing.sm)
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .contentShape(Rectangle())
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.98))
    }
}

private func rankingScorePill(_ text: String) -> some View {
    HStack(spacing: 3) {
        Image(systemName: "star.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.0))
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(TravColors.primary)
            .monospacedDigit()
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(TravColors.surfaceElevated)
    .clipShape(Capsule())
}
