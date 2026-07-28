import Foundation
import Supabase

struct SupabaseExperienceRepository: ExperienceRepository {
    static let pageSize = 20

    private var client: SupabaseClient {
        get throws {
            guard let client = SupabaseManager.client else {
                throw RepositoryError.backendUnavailable
            }
            return client
        }
    }

    // MARK: - Wire types

    /// Full experience row with the creator profile embedded (single round trip).
    struct DBExperienceRow: Decodable {
        let id: UUID
        let user_id: UUID
        let title: String
        let description: String
        let city: String
        let city_id: UUID?
        let stops: [String]
        let image: StringOrArray?
        let rating: RadarRating?
        let save_count: Int
        let like_count: Int
        let completion_count: Int
        let comment_count: Int
        let created_at: Date?
        let creator: DBProfileSummary?

        enum CodingKeys: String, CodingKey {
            case id, user_id, title, description, city, city_id, stops, image, rating
            case save_count, like_count, completion_count, comment_count
            case created_at, creator
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            user_id = try c.decode(UUID.self, forKey: .user_id)
            title = try c.decode(String.self, forKey: .title)
            description = (try c.decodeIfPresent(String.self, forKey: .description)) ?? ""
            city = (try c.decodeIfPresent(String.self, forKey: .city)) ?? ""
            city_id = try c.decodeIfPresent(UUID.self, forKey: .city_id)
            stops = (try c.decodeIfPresent([String].self, forKey: .stops)) ?? []
            image = try c.decodeIfPresent(StringOrArray.self, forKey: .image)
            save_count = (try c.decodeIfPresent(Int.self, forKey: .save_count)) ?? 0
            like_count = (try c.decodeIfPresent(Int.self, forKey: .like_count)) ?? 0
            completion_count = (try c.decodeIfPresent(Int.self, forKey: .completion_count)) ?? 0
            comment_count = (try c.decodeIfPresent(Int.self, forKey: .comment_count)) ?? 0
            created_at = try c.decodeIfPresent(Date.self, forKey: .created_at)
            creator = try c.decodeIfPresent(DBProfileSummary.self, forKey: .creator)

            // Rating is stored as a flat scores dict. Decode leniently so one
            // malformed row does not fail an entire feed fetch.
            if let scores = try? c.decode([String: Double].self, forKey: .rating), !scores.isEmpty {
                rating = RadarRating(scores: scores)
            } else if let decoded = try? c.decode(RadarRating.self, forKey: .rating),
                      !decoded.scores.isEmpty {
                rating = decoded
            } else {
                rating = nil
            }
        }
    }

    struct DBProfileSummary: Decodable {
        let id: UUID
        let username: String
        let display_name: String
        let avatar_url: String?
        let is_verified: Bool?

        var summary: ProfileSummary {
            ProfileSummary(
                id: id,
                username: username,
                displayName: display_name,
                avatarURL: avatar_url.flatMap { URL(string: $0) },
                isVerified: is_verified ?? false
            )
        }
    }

    struct DBPlace: Decodable {
        let id: String
        let client_uuid: UUID?
        let name: String
        let basic_category: String?
        let latitude: Double
        let longitude: Double
        let city: String?
        let image_urls: [String]?
        let stops: [String]?
    }

    /// JSON payload stored inside `experiences.stops` / `places.stops` entries.
    struct DBStop: Codable {
        let id: UUID
        let name: String
        let emoji: String?
        let description: String
        let latitude: Double
        let longitude: Double
        let place_id: String?
        let orderIndex: Int
        let creator_notes: String?
        let duration_minutes: Int?

        init(from stop: Stop) {
            id = stop.id
            name = stop.name
            emoji = stop.emoji
            description = stop.description
            latitude = stop.latitude
            longitude = stop.longitude
            place_id = stop.placeID
            orderIndex = stop.orderIndex
            creator_notes = stop.creatorNotes
            duration_minutes = stop.durationMinutes
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
            name = try c.decode(String.self, forKey: .name)
            emoji = try c.decodeIfPresent(String.self, forKey: .emoji)
            description = (try c.decodeIfPresent(String.self, forKey: .description)) ?? ""
            latitude = (try c.decodeIfPresent(Double.self, forKey: .latitude)) ?? 0
            longitude = (try c.decodeIfPresent(Double.self, forKey: .longitude)) ?? 0
            place_id = try c.decodeIfPresent(String.self, forKey: .place_id)
            orderIndex = (try c.decodeIfPresent(Int.self, forKey: .orderIndex)) ?? 0
            creator_notes = try c.decodeIfPresent(String.self, forKey: .creator_notes)
            duration_minutes = try c.decodeIfPresent(Int.self, forKey: .duration_minutes)
        }
    }

    /// Column list used by every experience read.
    ///
    /// Creator is loaded in a follow-up `profiles` query (`hydrateCreators`)
    /// because PostgREST cannot disambiguate `experiences ↔ profiles` when
    /// likes/saves M2M relationships exist and `experiences_user_id_fkey` is
    /// missing on a drifted live DB (PGRST201).
    static let experienceSelect = """
    id, user_id, title, description, city, city_id, stops, image, rating, \
    save_count, like_count, completion_count, comment_count, created_at
    """
    // MARK: - Publish

    func publishExperience(_ draft: ExperienceDraft) async throws {
        let client = try client
        let experienceID = UUID()

        let cityID = try await ensureCityExists(draft.city, client: client)

        var imageURLStrings: [String] = []
        for (index, data) in draft.imagesData.enumerated() {
            // User-scoped path so storage RLS can authorize the write.
            let path = "\(draft.creatorID.uuidString.lowercased())/\(experienceID.uuidString.lowercased())/photo_\(index).jpg"
            _ = try await client.storage
                .from("experiences")
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
            let publicURL = try client.storage.from("experiences").getPublicURL(path: path)
            imageURLStrings.append(publicURL.absoluteString)
        }

        let encoder = JSONEncoder()
        let stopPayloads: [String] = try draft.stops
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { stop in
                let data = try encoder.encode(DBStop(from: stop))
                return String(decoding: data, as: UTF8.self)
            }

        struct Insert: Encodable {
            let id: UUID
            let user_id: UUID
            let title: String
            let description: String
            let city: String
            let city_id: UUID
            let stops: [String]
            let image: [String]?
            let rating: [String: Double]?
            let is_published: Bool
        }

        try await client
            .from("experiences")
            .insert(Insert(
                id: experienceID,
                user_id: draft.creatorID,
                title: draft.title,
                description: draft.description,
                city: draft.city.name,
                city_id: cityID,
                stops: stopPayloads,
                image: imageURLStrings.isEmpty ? nil : imageURLStrings,
                rating: draft.rating?.scores,
                is_published: true
            ))
            .execute()

        // Persist normalized stop rows (coordinates / place IDs) for detail maps.
        struct StopInsert: Encodable {
            let experience_id: UUID
            let order_index: Int
            let name: String
            let description: String
            let creator_notes: String
            let latitude: Double?
            let longitude: Double?
            let place_id: String?
            let recommended_time: String?
            let duration_minutes: Int
            let emoji: String?
        }

        let stopRows = draft.stops
            .sorted { $0.orderIndex < $1.orderIndex }
            .enumerated()
            .map { index, stop in
                StopInsert(
                    experience_id: experienceID,
                    order_index: index,
                    name: stop.name,
                    description: stop.description,
                    creator_notes: stop.creatorNotes ?? "",
                    latitude: stop.latitude,
                    longitude: stop.longitude,
                    place_id: stop.placeID,
                    recommended_time: stop.recommendedTime,
                    duration_minutes: stop.durationMinutes,
                    emoji: stop.emoji
                )
            }

        if !stopRows.isEmpty {
            try await client.from("stops").insert(stopRows).execute()
        }
    }

    // MARK: - City FK Helper

    private func ensureCityExists(_ city: City, client: SupabaseClient) async throws -> UUID {
        // 1. Try matching against cached catalog by ID
        if let existing = try? await CityCatalog.shared.city(id: city.id) {
            return existing.id
        }

        // 2. Try matching against cached catalog by Name
        if let existing = try? await CityCatalog.shared.city(named: city.name) {
            return existing.id
        }

        let cleanName = city.name.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? city.name
        if let existing = try? await CityCatalog.shared.city(named: cleanName) {
            return existing.id
        }

        let slug = city.slug.isEmpty ? cleanName.lowercased().replacingOccurrences(of: " ", with: "-") : city.slug

        // 3. Query Supabase `cities` table directly by slug or name
        struct CityIdRow: Decodable { let id: UUID }
        if let existingRows: [CityIdRow] = try? await client
            .from("cities")
            .select("id")
            .or("slug.eq.\(slug),name.ilike.\(cleanName)")
            .limit(1)
            .execute()
            .value,
           let existing = existingRows.first {
            await CityCatalog.shared.invalidate()
            return existing.id
        }

        // 4. If city does not exist in DB yet, insert it into `cities` table to satisfy FK
        struct CityInsert: Encodable {
            let id: UUID
            let name: String
            let slug: String
            let country_code: String
            let latitude: Double
            let longitude: Double
            let hero_image_url: String?
            let timezone: String
            let experience_count: Int
            let creator_count: Int
            let is_active: Bool
        }

        let newID = city.id
        let insertData = CityInsert(
            id: newID,
            name: cleanName,
            slug: slug,
            country_code: city.countryCode.isEmpty ? "US" : city.countryCode,
            latitude: city.latitude,
            longitude: city.longitude,
            hero_image_url: city.heroImageURL?.absoluteString,
            timezone: city.timezone.isEmpty ? "America/Los_Angeles" : city.timezone,
            experience_count: 1,
            creator_count: 1,
            is_active: true
        )

        do {
            try await client
                .from("cities")
                .insert(insertData)
                .execute()
            await CityCatalog.shared.invalidate()
            return newID
        } catch {
            // In case of conflict or duplicate slug, query ID one last time
            if let fallbackRows: [CityIdRow] = try? await client
                .from("cities")
                .select("id")
                .eq("slug", value: slug)
                .limit(1)
                .execute()
                .value,
               let fallback = fallbackRows.first {
                return fallback.id
            }
            throw error
        }
    }

    // MARK: - Detail

    func fetchExperience(id: UUID) async throws -> Experience {
        let client = try client
        let idStr = id.uuidString.lowercased()

        // 1. User-published experience.
        let expRows: [DBExperienceRow] = try await client
            .from("experiences")
            .select(Self.experienceSelect)
            .eq("id", value: idStr)
            .limit(1)
            .execute()
            .value

        if let row = expRows.first {
            let creators = await fetchCreators(for: [row])
            var detail = experience(from: row, creators: creators)
            if let normalized = try? await fetchNormalizedStops(experienceID: row.id), !normalized.isEmpty {
                detail.stops = normalized
            }
            return detail
        }

        // 2. Curated place (pipeline content), looked up by its stable client UUID.
        let placeRows: [DBPlace] = try await client
            .from("places")
            .select()
            .eq("client_uuid", value: idStr)
            .limit(1)
            .execute()
            .value

        guard let place = placeRows.first else {
            throw RepositoryError.notFound
        }
        return try await experience(from: place, id: id)
    }

    // MARK: - Feeds

    func fetchCityFeed(cityID: UUID, page: Int) async throws -> Paginated<ExperienceSummary> {
        let client = try client
        let range = Self.pageRange(page)

        let rows: [DBExperienceRow] = try await client
            .from("experiences")
            .select(Self.experienceSelect)
            .eq("city_id", value: cityID.uuidString.lowercased())
            .eq("is_published", value: true)
            .order("created_at", ascending: false)
            .range(from: range.lowerBound, to: range.upperBound)
            .execute()
            .value

        let creators = await fetchCreators(for: rows)
        return Paginated(
            items: rows.map { summary(from: $0, creators: creators) },
            page: page,
            hasMore: rows.count == Self.pageSize
        )
    }

    func fetchHomeFeed(page: Int) async throws -> Paginated<ExperienceSummary> {
        let client = try client
        let range = Self.pageRange(page)

        let rows: [DBExperienceRow] = try await client
            .from("experiences")
            .select(Self.experienceSelect)
            .eq("is_published", value: true)
            .order("created_at", ascending: false)
            .range(from: range.lowerBound, to: range.upperBound)
            .execute()
            .value

        let creators = await fetchCreators(for: rows)
        return Paginated(
            items: rows.map { summary(from: $0, creators: creators) },
            page: page,
            hasMore: rows.count == Self.pageSize
        )
    }

    func fetchPlacesFeed(page: Int) async throws -> Paginated<ExperienceSummary> {
        let client = try client
        let range = Self.pageRange(page)

        let places: [DBPlace]
        do {
            places = try await client
                .from("places")
                .select("id, client_uuid, name, basic_category, latitude, longitude, city, image_urls, stops")
                .order("created_at", ascending: false)
                .range(from: range.lowerBound, to: range.upperBound)
                .execute()
                .value
        } catch {
            // Older place rows / missing created_at — still return catalog content.
            TravLog.network.error("fetchPlacesFeed ordered query failed, retrying: \(error.localizedDescription, privacy: .public)")
            places = try await client
                .from("places")
                .select("id, client_uuid, name, basic_category, latitude, longitude, city, image_urls, stops")
                .range(from: range.lowerBound, to: range.upperBound)
                .execute()
                .value
        }

        let recCreator = ProfileSummary(
            id: StableUUID.from("rec_by_trav"),
            username: "rec_by_trav",
            displayName: "Rec by Trav",
            avatarURL: nil,
            isVerified: true
        )

        let catalog = try? await CityCatalog.shared.all()

        let items: [ExperienceSummary] = places.map { place in
            let stops = Self.parseStops(place.stops ?? [])
            let stopPreviews = stops.isEmpty
                ? [StopPreview(id: StableUUID.from("place:\(place.id)"), name: place.name, emoji: Self.emojiForCategory(place.basic_category))]
                : stops.map { StopPreview(id: $0.id, name: $0.name, emoji: $0.emoji, latitude: $0.latitude, longitude: $0.longitude) }

            let cityName = place.city ?? "Berkeley"
            let city = catalog?.first { $0.name.caseInsensitiveCompare(cityName) == .orderedSame }
            let imageURLs = (place.image_urls ?? []).compactMap { URL(string: $0) }

            return ExperienceSummary(
                id: place.client_uuid ?? StableUUID.from(place.id),
                cityID: city?.id ?? StableUUID.from("city:\(cityName.lowercased())"),
                title: place.name,
                imageURLs: imageURLs,
                coverImageURL: imageURLs.first ?? Self.defaultCoverForCategory(place.name),
                creator: recCreator,
                durationMinutes: stopPreviews.count > 1 ? 120 : 45,
                costLevel: stopPreviews.count > 1 ? .moderate : .budget,
                estimatedCostUSD: nil,
                stops: stopPreviews,
                cityName: cityName
            )
        }

        return Paginated(items: items, page: page, hasMore: places.count == Self.pageSize)
    }

    func fetchPopups() async throws -> [Popup] {
        let client = try client

        // Timestamps are ingested by the pipeline in inconsistent formats, so
        // decode as strings and parse leniently.
        struct DBPopup: Decodable {
            let id: UUID
            let event_name: String
            let address: String?
            let start_time: String?
            let end_time: String?
        }

        func parseDate(_ raw: String?) -> Date? {
            guard let raw else { return nil }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: raw) { return date }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: raw) { return date }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ", "yyyy-MM-dd'T'HH:mm:ssZZZZZ", "yyyy-MM-dd'T'HH:mm:ss"] {
                formatter.dateFormat = format
                if let date = formatter.date(from: raw) { return date }
            }
            return nil
        }

        let rows: [DBPopup]
        do {
            rows = try await client
                .from("popups")
                .select("id, event_name, address, start_time, end_time")
                .order("start_time", ascending: true)
                .limit(50)
                .execute()
                .value
        } catch {
            rows = try await client
                .from("popups")
                .select("id, event_name, address, start_time, end_time")
                .limit(50)
                .execute()
                .value
        }

        // Keep recent + upcoming events so preexisting popups still appear.
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date.distantPast
        return rows
            .map {
                Popup(
                    id: $0.id,
                    name: $0.event_name,
                    address: $0.address ?? "Berkeley, CA",
                    startTime: parseDate($0.start_time),
                    endTime: parseDate($0.end_time)
                )
            }
            .filter { popup in
                guard let start = popup.startTime else { return true }
                return start >= cutoff
            }
            .sorted { lhs, rhs in
                switch (lhs.startTime, rhs.startTime) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.name < rhs.name
                }
            }
    }

    func fetchUserExperiences(cityID: UUID, userID: UUID) async throws -> [ExperienceSummary] {
        let client = try client
        let rows: [DBExperienceRow] = try await client
            .from("experiences")
            .select(Self.experienceSelect)
            .eq("city_id", value: cityID.uuidString.lowercased())
            .eq("user_id", value: userID.uuidString.lowercased())
            .eq("is_published", value: true)
            .order("created_at", ascending: false)
            .limit(50)
            .execute()
            .value
        let creators = await fetchCreators(for: rows)
        return rows.map { summary(from: $0, creators: creators) }
    }

    // MARK: - Rankings

    func fetchRankedExperiences(
        cityID: UUID?,
        creatorID: UUID?,
        axis: RankingAxis,
        page: Int
    ) async throws -> Paginated<ExperienceSummary> {
        let summaries = try await fetchRatedExperienceSummaries(cityID: cityID, creatorID: creatorID)
        let sorted = RankingScore.sortedExperiences(summaries, axis: axis)
        return RankingScore.paginate(sorted, page: page)
    }

    func fetchRankedCreators(
        cityID: UUID?,
        axis: RankingAxis,
        page: Int
    ) async throws -> Paginated<RankedCreator> {
        let summaries = try await fetchRatedExperienceSummaries(cityID: cityID, creatorID: nil)
        let ranked = RankingScore.rankedCreators(from: summaries, axis: axis)
        return RankingScore.paginate(ranked, page: page)
    }

    /// Loads rated experiences for leaderboards. Filtered server-side; capped
    /// so leaderboards stay fast as the table grows.
    private func fetchRatedExperienceSummaries(
        cityID: UUID?,
        creatorID: UUID?
    ) async throws -> [ExperienceSummary] {
        let client = try client
        var query = client
            .from("experiences")
            .select(Self.experienceSelect)
            .eq("is_published", value: true)
            .not("rating", operator: .is, value: "null")

        if let cityID {
            query = query.eq("city_id", value: cityID.uuidString.lowercased())
        }
        if let creatorID {
            query = query.eq("user_id", value: creatorID.uuidString.lowercased())
        }

        let rows: [DBExperienceRow] = try await query
            .order("created_at", ascending: false)
            .limit(200)
            .execute()
            .value

        let creators = await fetchCreators(for: rows)
        return rows.map { summary(from: $0, creators: creators) }
    }

    // MARK: - Mapping

    static func pageRange(_ page: Int) -> ClosedRange<Int> {
        let from = page * pageSize
        return from...(from + pageSize - 1)
    }

    /// Loads creator profiles in one round trip. Failures fall back to placeholders
    /// so a profiles RLS/decode issue never blanks the whole feed.
    private func fetchCreators(for rows: [DBExperienceRow]) async -> [UUID: DBProfileSummary] {
        let ids = Array(Set(rows.map(\.user_id)))
        guard !ids.isEmpty else { return [:] }
        do {
            let client = try client
            let profiles: [DBProfileSummary] = try await client
                .from("profiles")
                .select("id, username, display_name, avatar_url, is_verified")
                .in("id", values: ids.map { $0.uuidString.lowercased() })
                .execute()
                .value
            return Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        } catch {
            TravLog.network.error("fetchCreators failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    private func resolvedCreator(
        for row: DBExperienceRow,
        creators: [UUID: DBProfileSummary]
    ) -> ProfileSummary {
        row.creator?.summary
            ?? creators[row.user_id]?.summary
            ?? Self.fallbackCreator(id: row.user_id)
    }

    func summary(
        from row: DBExperienceRow,
        creators: [UUID: DBProfileSummary] = [:]
    ) -> ExperienceSummary {
        let stops = Self.parseStops(row.stops)
        let imageURLs = (row.image?.values ?? []).compactMap { URL(string: $0) }
        return ExperienceSummary(
            id: row.id,
            cityID: row.city_id ?? StableUUID.from("city:\(row.city.lowercased())"),
            title: row.title,
            imageURLs: imageURLs,
            creator: resolvedCreator(for: row, creators: creators),
            durationMinutes: Self.estimatedDuration(stops: stops),
            costLevel: .moderate,
            estimatedCostUSD: nil,
            saveCount: row.save_count,
            likeCount: row.like_count,
            completionCount: row.completion_count,
            stops: stops.map { StopPreview(id: $0.id, name: $0.name, emoji: $0.emoji, latitude: $0.latitude, longitude: $0.longitude) },
            rating: row.rating,
            cityName: row.city
        )
    }

    func experience(
        from row: DBExperienceRow,
        creators: [UUID: DBProfileSummary] = [:]
    ) -> Experience {
        let stops = Self.parseStops(row.stops)
        let imageURLs = (row.image?.values ?? []).compactMap { URL(string: $0) }
        return Experience(
            id: row.id,
            cityID: row.city_id ?? StableUUID.from("city:\(row.city.lowercased())"),
            creator: resolvedCreator(for: row, creators: creators),
            title: row.title,
            description: row.description,
            imageURLs: imageURLs,
            durationMinutes: Self.estimatedDuration(stops: stops),
            costLevel: .moderate,
            estimatedCostUSD: nil,
            transportMode: .walking,
            totalDistanceMeters: 0,
            saveCount: row.save_count,
            likeCount: row.like_count,
            completionCount: row.completion_count,
            commentCount: row.comment_count,
            isPublished: true,
            publishedAt: row.created_at,
            stops: stops,
            routeSegments: [],
            rating: row.rating
        )
    }

    private func experience(from place: DBPlace, id: UUID) async throws -> Experience {
        let recCreator = ProfileSummary(
            id: StableUUID.from("rec_by_trav"),
            username: "rec_by_trav",
            displayName: "Rec by Trav",
            avatarURL: nil,
            isVerified: true
        )

        var stops = Self.parseStops(place.stops ?? [])
        if stops.isEmpty {
            stops = [Stop(
                id: UUID(),
                orderIndex: 0,
                name: place.name,
                description: "Curated hangout spot.",
                creatorNotes: nil,
                latitude: place.latitude,
                longitude: place.longitude,
                placeID: place.id,
                recommendedTime: nil,
                durationMinutes: 45,
                emoji: Self.emojiForCategory(place.basic_category),
                media: []
            )]
        }

        let cityName = place.city ?? "Berkeley"
        let city = try? await CityCatalog.shared.city(named: cityName)
        let imageURLs = (place.image_urls ?? []).compactMap { URL(string: $0) }

        return Experience(
            id: id,
            cityID: city?.id ?? StableUUID.from("city:\(cityName.lowercased())"),
            creator: recCreator,
            title: place.name,
            description: "Explore local spots and neighborhood favorites curated by Trav.",
            imageURLs: imageURLs,
            coverImageURL: imageURLs.first ?? Self.defaultCoverForCategory(place.name),
            durationMinutes: Self.estimatedDuration(stops: stops),
            costLevel: .moderate,
            estimatedCostUSD: nil,
            transportMode: .walking,
            totalDistanceMeters: 0,
            saveCount: 0,
            likeCount: 0,
            completionCount: 0,
            commentCount: 0,
            isPublished: true,
            publishedAt: nil,
            stops: stops,
            routeSegments: []
        )
    }

    private func fetchNormalizedStops(experienceID: UUID) async throws -> [Stop] {
        struct Row: Decodable {
            let id: UUID
            let order_index: Int
            let name: String
            let description: String?
            let creator_notes: String?
            let latitude: Double?
            let longitude: Double?
            let place_id: String?
            let recommended_time: String?
            let duration_minutes: Int?
            let emoji: String?
        }

        let rows: [Row] = try await client
            .from("stops")
            .select()
            .eq("experience_id", value: experienceID.uuidString.lowercased())
            .order("order_index", ascending: true)
            .execute()
            .value

        return rows.map { row in
            Stop(
                id: row.id,
                orderIndex: row.order_index,
                name: row.name,
                description: row.description ?? "",
                creatorNotes: row.creator_notes,
                latitude: row.latitude ?? 0,
                longitude: row.longitude ?? 0,
                placeID: row.place_id,
                recommendedTime: row.recommended_time,
                durationMinutes: row.duration_minutes ?? 30,
                emoji: row.emoji,
                media: []
            )
        }
    }

    /// Stops are stored as a text array whose entries are either plain names
    /// (legacy rows) or JSON payloads with coordinates (geocoded rows).
    static func parseStops(_ raw: [String]) -> [Stop] {
        let decoder = JSONDecoder()
        return raw.enumerated().map { index, entry in
            if entry.hasPrefix("{"),
               let data = entry.data(using: .utf8),
               let dbStop = try? decoder.decode(DBStop.self, from: data) {
                return Stop(
                    id: dbStop.id,
                    orderIndex: dbStop.orderIndex,
                    name: dbStop.name,
                    description: dbStop.description,
                    creatorNotes: dbStop.creator_notes,
                    latitude: dbStop.latitude,
                    longitude: dbStop.longitude,
                    placeID: dbStop.place_id,
                    recommendedTime: nil,
                    durationMinutes: dbStop.duration_minutes ?? 30,
                    emoji: dbStop.emoji,
                    media: []
                )
            }
            return Stop(
                id: StableUUID.from("stop:\(index):\(entry)"),
                orderIndex: index,
                name: entry,
                description: "",
                creatorNotes: nil,
                latitude: 0,
                longitude: 0,
                placeID: nil,
                recommendedTime: nil,
                durationMinutes: 30,
                emoji: nil,
                media: []
            )
        }
    }

    static func estimatedDuration(stops: [Stop]) -> Int {
        let total = stops.reduce(0) { $0 + $1.durationMinutes }
        return max(30, total)
    }

    static func fallbackCreator(id: UUID) -> ProfileSummary {
        ProfileSummary(id: id, username: "traveler", displayName: "Traveler", avatarURL: nil, isVerified: false)
    }

    // MARK: - Category helpers (shared with feed mapping)

    static func defaultCoverForCategory(_ text: String) -> URL? {
        let textLower = text.lowercased()
        if textLower.contains("bar") || textLower.contains("pub") || textLower.contains("drink") || textLower.contains("lounge") {
            return URL(string: "https://images.unsplash.com/photo-1514933651103-005eec06c04b?w=800&q=80")
        }
        if textLower.contains("coffee") || textLower.contains("cafe") || textLower.contains("brew") || textLower.contains("espresso") {
            return URL(string: "https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=800&q=80")
        }
        if textLower.contains("shop") || textLower.contains("store") || textLower.contains("market") || textLower.contains("vintage") {
            return URL(string: "https://images.unsplash.com/photo-1483985988355-763728e1935b?w=800&q=80")
        }
        if textLower.contains("hike") || textLower.contains("trail") || textLower.contains("mountain") || textLower.contains("climb") {
            return URL(string: "https://images.unsplash.com/photo-1501555088652-021faa106b9b?w=800&q=80")
        }
        if textLower.contains("park") || textLower.contains("garden") || textLower.contains("lawn") || textLower.contains("field") {
            return URL(string: "https://images.unsplash.com/photo-1502082553048-f009c37129b9?w=800&q=80")
        }
        if textLower.contains("view") || textLower.contains("sunset") || textLower.contains("scenic") || textLower.contains("vista") {
            return URL(string: "https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?w=800&q=80")
        }
        if textLower.contains("museum") || textLower.contains("art") || textLower.contains("gallery") {
            return URL(string: "https://images.unsplash.com/photo-1545987796-200677ee1011?w=800&q=80")
        }
        if textLower.contains("book") || textLower.contains("read") || textLower.contains("library") {
            return URL(string: "https://images.unsplash.com/photo-1521587760476-6c12a4b040da?w=800&q=80")
        }
        return URL(string: "https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=800&q=80")
    }

    static func emojiForCategory(_ category: String?) -> String {
        guard let category else { return "📍" }
        let emojis: [String: String] = [
            "bar": "🍻",
            "shopping": "🛍️",
            "vintage_store": "🧥",
            "hiking_trail": "🥾",
            "park": "🌳",
            "scenic_viewpoint": "🌅",
            "museum": "🖼️",
            "bookstore": "📚"
        ]
        return emojis[category.lowercased()] ?? "📍"
    }
}
