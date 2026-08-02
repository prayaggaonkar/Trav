import Foundation

struct SpotEngagementStats: Sendable, Hashable {
    var saveCount: Int
    var likeCount: Int
    var completionCount: Int

    static let zero = SpotEngagementStats(saveCount: 0, likeCount: 0, completionCount: 0)
}

/// Batch-loads Trav engagement counters for MapKit place titles.
enum SpotEngagementLookup {
    /// Returns a map keyed by lowercased place title → aggregated stats.
    static func stats(forPlaceNames names: [String]) async -> [String: SpotEngagementStats] {
        let cleaned = Array(
            Set(
                names
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).prefix(25)

        guard !cleaned.isEmpty, let client = SupabaseManager.client else {
            return [:]
        }

        struct ExpRow: Decodable {
            let title: String
            let save_count: Int?
            let like_count: Int?
            let completion_count: Int?
        }

        var result: [String: SpotEngagementStats] = [:]

        // Parallel-ish batches of OR filters would be ideal; ilike-per-name is
        // fine for ≤25 titles and keeps matching fuzzy enough for MapKit names.
        await withTaskGroup(of: (String, SpotEngagementStats)?.self) { group in
            for name in cleaned {
                group.addTask {
                    let pattern = "%\(name)%"
                    let rows: [ExpRow] = (try? await client
                        .from("experiences")
                        .select("title, save_count, like_count, completion_count")
                        .ilike("title", pattern: pattern)
                        .eq("is_published", value: true)
                        .limit(8)
                        .execute()
                        .value) ?? []

                    guard !rows.isEmpty else { return nil }

                    let nameLower = name.lowercased()
                    // Prefer exact/near-exact title matches when aggregating.
                    let preferred = rows.filter {
                        $0.title.lowercased() == nameLower
                            || $0.title.lowercased().hasPrefix(nameLower)
                            || nameLower.hasPrefix($0.title.lowercased())
                    }
                    let use = preferred.isEmpty ? rows : preferred

                    var stats = SpotEngagementStats.zero
                    for row in use {
                        stats.saveCount += row.save_count ?? 0
                        stats.likeCount += row.like_count ?? 0
                        stats.completionCount += row.completion_count ?? 0
                    }
                    return (nameLower, stats)
                }
            }

            for await item in group {
                if let item {
                    if let existing = result[item.0] {
                        result[item.0] = SpotEngagementStats(
                            saveCount: existing.saveCount + item.1.saveCount,
                            likeCount: existing.likeCount + item.1.likeCount,
                            completionCount: existing.completionCount + item.1.completionCount
                        )
                    } else {
                        result[item.0] = item.1
                    }
                }
            }
        }

        return result
    }
}
