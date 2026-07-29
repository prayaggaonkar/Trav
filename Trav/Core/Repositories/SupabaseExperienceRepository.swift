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

        NotificationCenter.default.post(name: Notification.Name("ExperiencePublishedNotification"), object: nil)
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

    func fetchPopups(
        latitude: Double? = nil,
        longitude: Double? = nil,
        city: String? = nil
    ) async throws -> [Popup] {
        let client = try client

        struct DBPopup: Decodable {
            let id: UUID
            let event_name: String
            let address: String?
            let city: String?
            let latitude: Double?
            let longitude: Double?
            let category: String?
            let description: String?
            let start_time: String?
            let end_time: String?
            let external_url: String?
            let image_url: String?
            let source: String?
            let distance_miles: Double?
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

        let userLat = latitude ?? 37.8715
        let userLng = longitude ?? -122.2730
        let targetCity = city ?? "Berkeley, CA"

        var rows: [DBPopup] = []

        // 1. Invoke Supabase Edge Function API `fetch-location-popups` for live dynamic events
        do {
            struct FunctionBody: Encodable {
                let latitude: Double
                let longitude: Double
                let city: String
                let radius_miles: Double
            }
            struct FunctionResponse: Decodable {
                let popups: [DBPopup]
            }

            let res: FunctionResponse = try await client.functions.invoke(
                "fetch-location-popups",
                options: FunctionInvokeOptions(
                    body: FunctionBody(
                        latitude: userLat,
                        longitude: userLng,
                        city: targetCity,
                        radius_miles: 50.0
                    )
                )
            )
            rows = res.popups
        } catch {
            // 2. Fallback to RPC function fetch_popups_near
            do {
                struct RPCParams: Encodable {
                    let user_lat: Double
                    let user_lng: Double
                    let radius_miles: Double
                    let limit_count: Int
                }
                rows = try await client
                    .rpc(
                        "fetch_popups_near",
                        params: RPCParams(
                            user_lat: userLat,
                            user_lng: userLng,
                            radius_miles: 50.0,
                            limit_count: 50
                        )
                    )
                    .execute()
                    .value
            } catch {
                // 3. Fallback to direct table query
                do {
                    rows = try await client
                        .from("popups")
                        .select("id, event_name, address, city, latitude, longitude, category, description, start_time, end_time, external_url, image_url, source")
                        .order("start_time", ascending: true)
                        .limit(50)
                        .execute()
                        .value
                } catch {
                    rows = []
                }
            }
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date.distantPast
        let parsed = rows
            .map { row in
                let catEnum = row.category.flatMap { PopupCategory(rawValue: $0.lowercased()) } ?? .general
                let extURL = Popup.cleanURL(row.external_url, name: row.event_name)
                let imgURL = row.image_url.flatMap { URL(string: $0) } ?? Popup.uniqueCoverURL(for: row.event_name, category: catEnum)

                return Popup(
                    id: row.id,
                    name: row.event_name,
                    address: row.address ?? row.city ?? "Berkeley, CA",
                    city: row.city ?? targetCity,
                    latitude: row.latitude,
                    longitude: row.longitude,
                    category: catEnum,
                    description: row.description,
                    startTime: parseDate(row.start_time),
                    endTime: parseDate(row.end_time),
                    externalURL: extURL,
                    imageURL: imgURL,
                    source: row.source,
                    distanceMiles: row.distance_miles
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

        let deduplicated = Self.deduplicatePopups(parsed)

        if deduplicated.isEmpty {
            let fallbacks = Self.deduplicatePopups(Self.generateFallbackPopups(latitude: userLat, longitude: userLng, city: targetCity))
            
            // Auto-sync fallbacks directly into Supabase database in background task
            Task {
                struct DBOupsert: Encodable {
                    let event_name: String
                    let address: String
                    let city: String
                    let latitude: Double?
                    let longitude: Double?
                    let category: String
                    let description: String?
                    let start_time: String?
                    let external_url: String?
                    let image_url: String?
                    let source: String
                }

                let isoFormatter = ISO8601DateFormatter()
                let rowsToInsert = fallbacks.map { p in
                    DBOupsert(
                        event_name: p.name,
                        address: p.address,
                        city: p.city ?? targetCity,
                        latitude: p.latitude,
                        longitude: p.longitude,
                        category: p.category.rawValue,
                        description: p.description,
                        start_time: p.startTime.map { isoFormatter.string(from: $0) },
                        external_url: p.externalURL?.absoluteString,
                        image_url: p.imageURL?.absoluteString,
                        source: p.source ?? "auto_sync"
                    )
                }
                
                try? await client
                    .from("popups")
                    .upsert(rowsToInsert, onConflict: "event_name,start_time")
                    .execute()
            }
            
            return fallbacks
        }

        return deduplicated
    }

    private static func deduplicatePopups(_ list: [Popup]) -> [Popup] {
        var result: [Popup] = []
        let calendar = Calendar.current

        for popup in list {
            let normName = popup.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            let isDuplicate = result.contains { existing in
                let existingNormName = existing.name
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()

                guard existingNormName == normName else { return false }

                // Same title! Check if they are on the same calendar day or missing dates
                switch (existing.startTime, popup.startTime) {
                case let (d1?, d2?):
                    return calendar.isDate(d1, inSameDayAs: d2)
                default:
                    // If either date is missing, treat as duplicate title
                    return true
                }
            }

            if !isDuplicate {
                result.append(popup)
            }
        }
        return result
    }

    private static func generateFallbackPopups(latitude: Double, longitude: Double, city: String) -> [Popup] {
        let cityShort = city.components(separatedBy: ",").first ?? "Local"
        let now = Date()
        let todayEvening = Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: now)
        let tomorrowAfternoon = Calendar.current.date(byAdding: .day, value: 1, to: now).flatMap {
            Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: $0)
        }
        let day2Evening = Calendar.current.date(byAdding: .day, value: 2, to: now).flatMap {
            Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: $0)
        }
        let day3Morning = Calendar.current.date(byAdding: .day, value: 3, to: now).flatMap {
            Calendar.current.date(bySettingHour: 10, minute: 30, second: 0, of: $0)
        }

        let citySlug = cityShort.lowercased().replacingOccurrences(of: " ", with: "-")

        return [
            Popup(
                name: "\(cityShort) Pickleball Open & Social",
                address: "Community Courts, \(city)",
                city: city,
                latitude: latitude + 0.005,
                longitude: longitude - 0.003,
                category: .sports,
                description: "Doubles tournament open to all skill levels! Grab a paddle, bring friends, and enjoy post-game refreshments.",
                startTime: tomorrowAfternoon,
                externalURL: URL(string: "https://eventbrite.com/e/\(citySlug)-pickleball-open-social-tickets-89217401923"),
                imageURL: URL(string: "https://images.unsplash.com/photo-1626248801379-51a0748a5f96?w=800&q=80"),
                source: "community",
                distanceMiles: 1.2
            ),
            Popup(
                name: "\(cityShort) Sunset Live Acoustic Sessions",
                address: "Amphitheater Plaza, \(city)",
                city: city,
                latitude: latitude - 0.004,
                longitude: longitude + 0.006,
                category: .music,
                description: "Outdoor acoustic concert featuring regional indie bands, food trucks, and sunset views.",
                startTime: todayEvening,
                externalURL: URL(string: "https://ticketmaster.com/event/Z7r9jZ1AeG0aK8?city=\(citySlug)"),
                imageURL: URL(string: "https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=800&q=80"),
                source: "ticketmaster",
                distanceMiles: 0.8
            ),
            Popup(
                name: "\(cityShort) Night Market & Street Food Festival",
                address: "Main St Promenade, \(city)",
                city: city,
                latitude: latitude + 0.002,
                longitude: longitude + 0.002,
                category: .food,
                description: "Over 20 local food trucks, craft boba, live DJ sets, and night market vendors.",
                startTime: day2Evening,
                externalURL: URL(string: "https://eventbrite.com/e/\(citySlug)-night-market-street-food-fest-tickets-7841920349"),
                imageURL: URL(string: "https://images.unsplash.com/photo-1533900298318-6b8da08a523e?w=800&q=80"),
                source: "eventbrite",
                distanceMiles: 2.1
            ),
            Popup(
                name: "\(cityShort) Tabletop Board Games & Trivia Night",
                address: "Corner Taproom, \(city)",
                city: city,
                latitude: latitude - 0.008,
                longitude: longitude - 0.004,
                category: .meetups,
                description: "Bring friends or play solo! Hundreds of board games, team trivia with prizes, and local brews on tap.",
                startTime: day2Evening,
                externalURL: URL(string: "https://meetup.com/\(citySlug)-tabletop-gaming/events/298410294/"),
                imageURL: URL(string: "https://images.unsplash.com/photo-1529699211952-734e80c4d42b?w=800&q=80"),
                source: "meetup",
                distanceMiles: 1.5
            ),
            Popup(
                name: "\(cityShort) Morning Run Club & Coffee Social",
                address: "Town Square Fountain, \(city)",
                city: city,
                latitude: latitude + 0.010,
                longitude: longitude - 0.007,
                category: .sports,
                description: "Easy 3-mile casual jog followed by complimentary pour-over coffee and pastries with the crew.",
                startTime: day3Morning,
                externalURL: URL(string: "https://strava.com/clubs/\(citySlug)-run-club/events/98412039"),
                imageURL: URL(string: "https://images.unsplash.com/photo-1476480862126-209bfaa8edc8?w=800&q=80"),
                source: "community",
                distanceMiles: 3.0
            ),
            Popup(
                name: "\(cityShort) Underground Comedy Showcase",
                address: "The Black Cat Lounge, \(city)",
                city: city,
                latitude: latitude - 0.005,
                longitude: longitude + 0.004,
                category: .comedy,
                description: "Hilarious showcase featuring touring headliners and local comedy talent.",
                startTime: day2Evening,
                externalURL: URL(string: "https://eventbrite.com/e/\(citySlug)-underground-comedy-tickets-6712940182"),
                imageURL: URL(string: "https://images.unsplash.com/photo-1585699324551-f6c309eedeca?w=800&q=80"),
                source: "eventbrite",
                distanceMiles: 1.8
            )
        ]
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

    func fetchLeaderboardEntries(cityID: UUID?, cityName: String?) async throws -> [LeaderboardEntry] {
        let client = try client

        // Fetch published experiences from Supabase database
        struct ExperienceRow: Decodable {
            let id: UUID
            let user_id: UUID
            let city_id: UUID?
            let city: String?
        }

        let rows: [ExperienceRow] = (try? await client
            .from("experiences")
            .select("id, user_id, city_id, city")
            .eq("is_published", value: true)
            .execute()
            .value) ?? []

        let searchCity: String? = {
            guard let cityName, !cityName.isEmpty, cityName != LocationOption.allLocations.name else { return nil }
            return cityName.lowercased().components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
        }()
        let isFilteredByCity = (cityID != nil || searchCity != nil)

        // Filter rows by city if a specific city was chosen
        let filteredRows: [ExperienceRow]
        if let cityID {
            filteredRows = rows.filter { $0.city_id == cityID }
        } else if let searchCity {
            filteredRows = rows.filter { row in
                guard let c = row.city?.lowercased() else { return false }
                return c.contains(searchCity) || searchCity.contains(c)
            }
        } else {
            filteredRows = rows
        }

        // Count experiences created in that city per user
        var userCounts: [UUID: Int] = [:]
        for row in filteredRows {
            userCounts[row.user_id, default: 0] += 1
        }

        // Fetch registered user profiles from Supabase profiles table
        struct DetailedDBProfile: Decodable {
            let id: UUID
            let username: String
            let display_name: String?
            let avatar_url: String?
            let is_verified: Bool?
            let onboarding_location: String?
        }

        let profiles: [DetailedDBProfile] = (try? await client
            .from("profiles")
            .select("id, username, display_name, avatar_url, is_verified, onboarding_location")
            .execute()
            .value) ?? []

        var realEntries: [LeaderboardEntry] = []
        for profile in profiles {
            let count = userCounts[profile.id] ?? 0

            if isFilteredByCity {
                let userLoc = profile.onboarding_location?.lowercased() ?? ""
                let matchesLocation = searchCity.map { userLoc.contains($0) } ?? false
                guard count > 0 || matchesLocation else { continue }
            }

            realEntries.append(LeaderboardEntry(
                id: profile.id,
                username: profile.username,
                displayName: profile.display_name ?? profile.username,
                avatarURL: profile.avatar_url.flatMap { URL(string: $0) },
                experienceCount: count,
                cityName: cityName ?? profile.onboarding_location,
                cityID: cityID,
                isFriend: false
            ))
        }

        // Sort descending by number of experiences created in this location
        realEntries.sort { lhs, rhs in
            if lhs.experienceCount != rhs.experienceCount {
                return lhs.experienceCount > rhs.experienceCount
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        return realEntries
    }

    func fetchHeatStreakEntries(cityID: UUID?, cityName: String?) async throws -> [HeatStreakEntry] {
        let client = try client

        struct ExperienceRow: Decodable {
            let id: UUID
            let user_id: UUID
            let city_id: UUID?
            let city: String?
            let created_at: String?
        }

        let rows: [ExperienceRow] = (try? await client
            .from("experiences")
            .select("id, user_id, city_id, city, created_at")
            .eq("is_published", value: true)
            .execute()
            .value) ?? []

        let searchCity: String? = {
            guard let cityName, !cityName.isEmpty, cityName != LocationOption.allLocations.name else { return nil }
            return cityName.lowercased().components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
        }()

        let filteredRows: [ExperienceRow]
        if let cityID {
            filteredRows = rows.filter { $0.city_id == cityID }
        } else if let searchCity {
            filteredRows = rows.filter { row in
                guard let c = row.city?.lowercased() else { return false }
                return c.contains(searchCity) || searchCity.contains(c)
            }
        } else {
            filteredRows = rows
        }

        var userDatesMap: [UUID: [Date]] = [:]
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()

        for row in filteredRows {
            guard let dateStr = row.created_at,
                  let date = isoFormatter.date(from: dateStr) ?? fallbackFormatter.date(from: dateStr) else { continue }
            userDatesMap[row.user_id, default: []].append(date)
        }

        struct DetailedDBProfile: Decodable {
            let id: UUID
            let username: String
            let display_name: String?
            let avatar_url: String?
            let is_verified: Bool?
        }

        let profiles: [DetailedDBProfile] = (try? await client
            .from("profiles")
            .select("id, username, display_name, avatar_url, is_verified")
            .execute()
            .value) ?? []

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)

        var rawEntries: [HeatStreakEntry] = []

        for profile in profiles {
            let dates = userDatesMap[profile.id] ?? []
            guard !dates.isEmpty else { continue }

            // 1. Calculate consecutive days streak anchored to today or yesterday
            let postDays = Set(dates.map { calendar.startOfDay(for: $0) })

            let anchorDay: Date?
            if postDays.contains(todayStart) {
                anchorDay = todayStart
            } else if let yesterdayStart, postDays.contains(yesterdayStart) {
                anchorDay = yesterdayStart
            } else {
                anchorDay = nil
            }

            var consecutiveDays = 0
            var streakStartDate: Date? = nil
            var streakEndDate: Date? = nil

            if let anchorDay {
                streakEndDate = anchorDay
                var checkDay = anchorDay
                while postDays.contains(checkDay) {
                    consecutiveDays += 1
                    streakStartDate = checkDay
                    guard let prevDay = calendar.date(byAdding: .day, value: -1, to: checkDay) else { break }
                    checkDay = prevDay
                }
            }

            guard consecutiveDays > 0 else { continue }

            // 2. Count experiences posted during this consecutive streak span
            let postsInStreak: Int
            if let start = streakStartDate, let end = streakEndDate {
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: end) ?? end
                postsInStreak = dates.filter { $0 >= start && $0 < endOfDay }.count
            } else {
                postsInStreak = dates.count
            }

            rawEntries.append(HeatStreakEntry(
                id: profile.id,
                username: profile.username,
                displayName: profile.display_name ?? profile.username,
                avatarURL: profile.avatar_url.flatMap { URL(string: $0) },
                count30Days: postsInStreak,
                consecutiveDays: consecutiveDays,
                isLocationVerified: true,
                rank: 1
            ))
        }

        // Sort descending by consecutive days streak and posts in streak
        rawEntries.sort { lhs, rhs in
            if lhs.consecutiveDays != rhs.consecutiveDays {
                return lhs.consecutiveDays > rhs.consecutiveDays
            }
            if lhs.count30Days != rhs.count30Days {
                return lhs.count30Days > rhs.count30Days
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        // Re-assign ranks 1..N
        var rankedEntries: [HeatStreakEntry] = []
        for (index, item) in rawEntries.enumerated() {
            rankedEntries.append(HeatStreakEntry(
                id: item.id,
                username: item.username,
                displayName: item.displayName,
                avatarURL: item.avatarURL,
                count30Days: item.count30Days,
                consecutiveDays: item.consecutiveDays,
                isLocationVerified: item.isLocationVerified,
                rank: index + 1
            ))
        }

        return rankedEntries
    }

    func fetchImpactLeaderboard(cityID: UUID?, cityName: String?) async throws -> [ImpactEntry] {
        let client = try client

        struct ExperienceRow: Decodable {
            let id: UUID
            let user_id: UUID
            let city_id: UUID?
            let city: String?
            let save_count: Int?
            let completion_count: Int?
        }

        let rows: [ExperienceRow] = (try? await client
            .from("experiences")
            .select("id, user_id, city_id, city, save_count, completion_count")
            .eq("is_published", value: true)
            .execute()
            .value) ?? []

        let searchCity: String? = {
            guard let cityName, !cityName.isEmpty, cityName != LocationOption.allLocations.name else { return nil }
            return cityName.lowercased().components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
        }()

        let filteredRows: [ExperienceRow]
        if let cityID {
            filteredRows = rows.filter { $0.city_id == cityID }
        } else if let searchCity {
            filteredRows = rows.filter { row in
                guard let c = row.city?.lowercased() else { return false }
                return c.contains(searchCity) || searchCity.contains(c)
            }
        } else {
            filteredRows = rows
        }

        // Map experience ID -> creator user ID
        var expToCreatorMap: [UUID: UUID] = [:]
        for row in filteredRows {
            expToCreatorMap[row.id] = row.user_id
        }

        struct ExpRefRow: Decodable {
            let experience_id: UUID
        }

        // 1. Tally saves per experience from experience_saves and saved_experiences tables
        var savesPerExp: [UUID: Int] = [:]
        if let expSaves: [ExpRefRow] = try? await client.from("experience_saves").select("experience_id").execute().value {
            for item in expSaves {
                if expToCreatorMap[item.experience_id] != nil {
                    savesPerExp[item.experience_id, default: 0] += 1
                }
            }
        }
        if let legacySaves: [ExpRefRow] = try? await client.from("saved_experiences").select("experience_id").execute().value {
            for item in legacySaves {
                if expToCreatorMap[item.experience_id] != nil {
                    savesPerExp[item.experience_id, default: 0] += 1
                }
            }
        }

        // 2. Tally watchlists per experience from watchlists and experience_completions tables
        var watchlistsPerExp: [UUID: Int] = [:]
        if let watchlists: [ExpRefRow] = try? await client.from("watchlists").select("experience_id").execute().value {
            for item in watchlists {
                if expToCreatorMap[item.experience_id] != nil {
                    watchlistsPerExp[item.experience_id, default: 0] += 1
                }
            }
        }
        if let completions: [ExpRefRow] = try? await client.from("experience_completions").select("experience_id").execute().value {
            for item in completions {
                if expToCreatorMap[item.experience_id] != nil {
                    watchlistsPerExp[item.experience_id, default: 0] += 1
                }
            }
        }

        // Calculate total impact per creator (sum of watchlists + saves across every experience created by the user)
        var userImpactMap: [UUID: Int] = [:]
        for row in filteredRows {
            let saves = max(row.save_count ?? 0, savesPerExp[row.id] ?? 0)
            let watchlists = max(row.completion_count ?? 0, watchlistsPerExp[row.id] ?? 0)
            userImpactMap[row.user_id, default: 0] += (saves + watchlists)
        }

        struct DetailedDBProfile: Decodable {
            let id: UUID
            let username: String
            let display_name: String?
            let avatar_url: String?
        }

        let profiles: [DetailedDBProfile] = (try? await client
            .from("profiles")
            .select("id, username, display_name, avatar_url")
            .execute()
            .value) ?? []

        var rawEntries: [ImpactEntry] = []
        for profile in profiles {
            let impactCount = userImpactMap[profile.id] ?? 0

            rawEntries.append(ImpactEntry(
                id: profile.id,
                username: profile.username,
                displayName: profile.display_name ?? profile.username,
                avatarURL: profile.avatar_url.flatMap { URL(string: $0) },
                totalImpactCount: impactCount,
                rank: 1
            ))
        }

        // Sort descending by total impact count across all experiences created by each user
        rawEntries.sort { lhs, rhs in
            if lhs.totalImpactCount != rhs.totalImpactCount {
                return lhs.totalImpactCount > rhs.totalImpactCount
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        var rankedEntries: [ImpactEntry] = []
        for (index, item) in rawEntries.enumerated() {
            rankedEntries.append(ImpactEntry(
                id: item.id,
                username: item.username,
                displayName: item.displayName,
                avatarURL: item.avatarURL,
                totalImpactCount: item.totalImpactCount,
                rank: index + 1
            ))
        }

        return rankedEntries
    }

    func fetchMainLeaderboard() async throws -> [MainLeaderboardEntry] {
        let client = try client

        // 1. Attempt to call Supabase RPC function get_main_leaderboard
        if let rpcEntries: [MainLeaderboardEntry] = try? await client
            .rpc("get_main_leaderboard")
            .execute()
            .value,
           !rpcEntries.isEmpty {
            return rpcEntries
        }

        // 2. Fallback calculation in Swift if RPC function is not yet created on Supabase
        let impactEntries = (try? await fetchImpactLeaderboard(cityID: nil, cityName: nil)) ?? []
        let expEntries = (try? await fetchLeaderboardEntries(cityID: nil, cityName: nil)) ?? []
        let streakEntries = (try? await fetchHeatStreakEntries(cityID: nil, cityName: nil)) ?? []

        let impactMap = Dictionary(uniqueKeysWithValues: impactEntries.map { ($0.id, $0.totalImpactCount) })
        let expMap = Dictionary(uniqueKeysWithValues: expEntries.map { ($0.id, $0.experienceCount) })
        let streakDaysMap = Dictionary(uniqueKeysWithValues: streakEntries.map { ($0.id, $0.consecutiveDays) })
        let streakPostsMap = Dictionary(uniqueKeysWithValues: streakEntries.map { ($0.id, $0.count30Days) })

        struct DetailedDBProfile: Decodable {
            let id: UUID
            let username: String
            let display_name: String?
            let avatar_url: String?
        }

        let profiles: [DetailedDBProfile] = (try? await client
            .from("profiles")
            .select("id, username, display_name, avatar_url")
            .execute()
            .value) ?? []

        var rawEntries: [MainLeaderboardEntry] = []
        for profile in profiles {
            let impact = impactMap[profile.id] ?? 0
            let expCount = expMap[profile.id] ?? 0
            let streakDays = streakDaysMap[profile.id] ?? 0
            let streakPosts = streakPostsMap[profile.id] ?? 0

            let entry = MainLeaderboardEntry(
                id: profile.id,
                username: profile.username,
                displayName: profile.display_name ?? profile.username,
                avatarURL: profile.avatar_url.flatMap { URL(string: $0) },
                impactCount: impact,
                experienceCount: expCount,
                streakDays: streakDays,
                streakPosts: streakPosts,
                rank: 1
            )
            rawEntries.append(entry)
        }

        rawEntries.sort { lhs, rhs in
            if lhs.totalScore != rhs.totalScore {
                return lhs.totalScore > rhs.totalScore
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        var rankedEntries: [MainLeaderboardEntry] = []
        for (index, item) in rawEntries.enumerated() {
            rankedEntries.append(MainLeaderboardEntry(
                id: item.id,
                username: item.username,
                displayName: item.displayName,
                avatarURL: item.avatarURL,
                impactCount: item.impactCount,
                experienceCount: item.experienceCount,
                streakDays: item.streakDays,
                streakPosts: item.streakPosts,
                totalScore: item.totalScore,
                rank: index + 1
            ))
        }

        return rankedEntries
    }

    func observeExperiencesInsert() -> AsyncStream<Void> {
        AsyncStream { continuation in
            guard let client = try? client else {
                continuation.finish()
                return
            }
            let channel = client.channel("public:experiences")
            let changeStream = channel.postgresChange(
                InsertAction.self,
                schema: "public",
                table: "experiences"
            )
            let task = Task {
                await channel.subscribe()
                for await _ in changeStream {
                    continuation.yield(())
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task {
                    await channel.unsubscribe()
                }
            }
        }
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
