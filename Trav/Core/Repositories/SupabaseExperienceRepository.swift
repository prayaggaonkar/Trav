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

        // Content-model columns. All optional: a database that has not run the
        // content-model migrations still decodes cleanly and the kind is
        // inferred from the stop count instead.
        let kind: ExperienceKind?
        let spot_key: String?
        let category: String?
        let latitude: Double?
        let longitude: Double?
        let is_featured: Bool?
        let rating_count: Int?
        let average_rating: Double?
        let community_rating_count: Int?
        let community_average_rating: Double?
        let creator_rating: Double?
        let community_rating: RadarRating?

        enum CodingKeys: String, CodingKey {
            case id, user_id, title, description, city, city_id, stops, image, rating
            case save_count, like_count, completion_count, comment_count
            case created_at, creator
            case kind, spot_key, category, latitude, longitude, is_featured
            case rating_count, average_rating, community_rating_count
            case community_average_rating, creator_rating, community_rating
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            user_id = try c.decode(UUID.self, forKey: .user_id)
            title = try c.decode(String.self, forKey: .title)
            description = (try c.decodeIfPresent(String.self, forKey: .description)) ?? ""
            city = (try c.decodeIfPresent(String.self, forKey: .city)) ?? ""
            city_id = try c.decodeIfPresent(UUID.self, forKey: .city_id)
            if let rawStrings = try? c.decodeIfPresent([String].self, forKey: .stops) {
                stops = rawStrings
            } else if let rawObjects = try? c.decodeIfPresent([DBStop].self, forKey: .stops) {
                stops = rawObjects.compactMap { dbStop in
                    guard let data = try? JSONEncoder().encode(dbStop),
                          let str = String(data: data, encoding: .utf8) else { return nil }
                    return str
                }
            } else if let single = try? c.decodeIfPresent(String.self, forKey: .stops) {
                stops = [single]
            } else {
                stops = []
            }
            image = try c.decodeIfPresent(StringOrArray.self, forKey: .image)
            save_count = (try c.decodeIfPresent(Int.self, forKey: .save_count)) ?? 0
            like_count = (try c.decodeIfPresent(Int.self, forKey: .like_count)) ?? 0
            completion_count = (try c.decodeIfPresent(Int.self, forKey: .completion_count)) ?? 0
            comment_count = (try c.decodeIfPresent(Int.self, forKey: .comment_count)) ?? 0
            created_at = try c.decodeIfPresent(Date.self, forKey: .created_at)
            creator = try c.decodeIfPresent(DBProfileSummary.self, forKey: .creator)

            kind = try? c.decodeIfPresent(ExperienceKind.self, forKey: .kind)
            spot_key = try? c.decodeIfPresent(String.self, forKey: .spot_key)
            category = try? c.decodeIfPresent(String.self, forKey: .category)
            latitude = try? c.decodeIfPresent(Double.self, forKey: .latitude)
            longitude = try? c.decodeIfPresent(Double.self, forKey: .longitude)
            is_featured = try? c.decodeIfPresent(Bool.self, forKey: .is_featured)
            rating_count = try? c.decodeIfPresent(Int.self, forKey: .rating_count)
            average_rating = try? c.decodeIfPresent(Double.self, forKey: .average_rating)
            community_rating_count = try? c.decodeIfPresent(Int.self, forKey: .community_rating_count)
            community_average_rating = try? c.decodeIfPresent(Double.self, forKey: .community_average_rating)
            creator_rating = try? c.decodeIfPresent(Double.self, forKey: .creator_rating)

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

            if let scores = try? c.decode([String: Double].self, forKey: .community_rating), !scores.isEmpty {
                community_rating = RadarRating(scores: scores)
            } else if let decoded = try? c.decode(RadarRating.self, forKey: .community_rating),
                      !decoded.scores.isEmpty {
                community_rating = decoded
            } else {
                community_rating = nil
            }
        }

        var resolvedKind: ExperienceKind {
            kind ?? .inferred(stopCount: stops.count)
        }

        var ratingSummary: RatingSummary {
            RatingSummary(
                averageScore: average_rating,
                ratingCount: rating_count ?? (rating == nil ? 0 : 1),
                communityAverageScore: community_average_rating,
                communityRatingCount: community_rating_count ?? 0,
                creatorScore: creator_rating ?? rating?.overallScore,
                communityRadar: community_rating
            )
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

        enum CodingKeys: String, CodingKey {
            case id, client_uuid, name, basic_category, latitude, longitude, city, image_urls, stops
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decode(String.self, forKey: .id)) ?? ""
            client_uuid = try? c.decodeIfPresent(UUID.self, forKey: .client_uuid)
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
            basic_category = try? c.decodeIfPresent(String.self, forKey: .basic_category)
            latitude = (try? c.decodeIfPresent(Double.self, forKey: .latitude)) ?? 0
            longitude = (try? c.decodeIfPresent(Double.self, forKey: .longitude)) ?? 0
            city = try? c.decodeIfPresent(String.self, forKey: .city)
            image_urls = (try? c.decodeIfPresent(StringOrArray.self, forKey: .image_urls))?.values

            if let rawStrings = try? c.decodeIfPresent([String].self, forKey: .stops) {
                stops = rawStrings
            } else if let rawObjects = try? c.decodeIfPresent([DBStop].self, forKey: .stops) {
                stops = rawObjects.compactMap { dbStop in
                    guard let data = try? JSONEncoder().encode(dbStop),
                          let str = String(data: data, encoding: .utf8) else { return nil }
                    return str
                }
            } else if let single = try? c.decodeIfPresent(String.self, forKey: .stops) {
                stops = [single]
            } else {
                stops = []
            }
        }
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

    /// Adds the content-model columns (kind, spot identity, rating aggregates).
    /// Used first, then dropped permanently for the session if the database has
    /// not run the content-model migrations yet.
    static let experienceSelectExtended = """
    \(experienceSelect), kind, spot_key, category, latitude, longitude, is_featured, \
    rating_count, average_rating, community_rating_count, community_average_rating, \
    creator_rating, community_rating
    """

    /// Tracks, once per launch, whether this database understands the content
    /// model. Avoids paying for a failed request on every single query.
    private actor SchemaSupport {
        static let shared = SchemaSupport()
        private var extendedColumns = true
        private var contentModelRPCs = true

        var hasExtendedColumns: Bool { extendedColumns }
        var hasContentModelRPCs: Bool { contentModelRPCs }

        func disableExtendedColumns() { extendedColumns = false }
        func disableContentModelRPCs() { contentModelRPCs = false }
    }

    /// Runs `operation` with the richest select the database supports.
    func withExperienceSelect<T: Sendable>(
        _ operation: (String) async throws -> T
    ) async throws -> T {
        if await SchemaSupport.shared.hasExtendedColumns {
            do {
                return try await operation(Self.experienceSelectExtended)
            } catch {
                guard Self.isUnknownSchemaError(error) else { throw error }
                await SchemaSupport.shared.disableExtendedColumns()
                TravLog.network.notice("Content-model columns unavailable; falling back to the legacy experience select.")
            }
        }
        return try await operation(Self.experienceSelect)
    }

    /// A missing column or a missing function — i.e. pending migrations, not a
    /// transport or auth failure.
    static func isUnknownSchemaError(_ error: Error) -> Bool {
        let text = "\(error)".lowercased()
        return text.contains("does not exist")
            || text.contains("42703")
            || text.contains("42883")
            || text.contains("pgrst202")
            || text.contains("pgrst204")
            || text.contains("could not find")
    }

    /// Surfaces `TRAV_*` invariants raised by the database as typed errors.
    static func contentModelError(from error: Error) -> Error {
        if let mapped = ContentModelError.from(serverMessage: "\(error)") {
            return mapped
        }
        return error
    }

    // MARK: - Publish

    @discardableResult
    func publishExperience(_ draft: ExperienceDraft) async throws -> UUID {
        // Users only author itineraries, and an itinerary is 2+ distinct spots.
        try draft.validateForPublishing()

        if await SchemaSupport.shared.hasContentModelRPCs {
            do {
                return try await publishItineraryViaRPC(draft)
            } catch let error as ContentModelError {
                throw error
            } catch {
                guard Self.isUnknownSchemaError(error) else {
                    throw Self.contentModelError(from: error)
                }
                await SchemaSupport.shared.disableContentModelRPCs()
                TravLog.network.notice("publish_itinerary RPC unavailable; publishing with the legacy insert path.")
            }
        }
        return try await publishItineraryLegacy(draft)
    }

    /// Single atomic call: the database validates stop count, rejects duplicate
    /// stops and duplicate itineraries, and links every stop to its spot.
    private func publishItineraryViaRPC(_ draft: ExperienceDraft) async throws -> UUID {
        let client = try client
        let cityID = try await ensureCityExists(draft.city, client: client)
        let imageURLStrings = try await uploadExperiencePhotos(
            draft.imagesData,
            creatorID: draft.creatorID,
            experienceID: UUID(),
            client: client
        )

        struct StopPayload: Encodable {
            let name: String
            let description: String
            let creator_notes: String
            let latitude: Double
            let longitude: Double
            let place_id: String?
            let recommended_time: String?
            let duration_minutes: Int
            let emoji: String?
        }

        struct Payload: Encodable {
            let title: String
            let description: String
            let city: String
            let city_id: String
            let image_urls: [String]
            let stops: [StopPayload]
        }

        let payload = Payload(
            title: draft.title,
            description: draft.description,
            city: draft.city.name,
            city_id: cityID.uuidString.lowercased(),
            image_urls: imageURLStrings,
            stops: draft.stops.sorted { $0.orderIndex < $1.orderIndex }.map { stop in
                StopPayload(
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
        )

        do {
            let id: UUID = try await client
                .rpc("publish_itinerary", params: ["p_payload": payload])
                .execute()
                .value

            if let rating = draft.rating, !rating.scores.isEmpty {
                // The creator's own rating is just a rating like any other.
                try? await SupabaseRatingRepository().submitRating(
                    RatingDraft(experienceID: id, radar: rating),
                    userID: draft.creatorID
                )
            }

            NotificationCenter.default.post(name: Notification.Name("ExperiencePublishedNotification"), object: nil)
            return id
        } catch {
            throw Self.contentModelError(from: error)
        }
    }

    private func uploadExperiencePhotos(
        _ imagesData: [Data],
        creatorID: UUID,
        experienceID: UUID,
        client: SupabaseClient
    ) async throws -> [String] {
        var imageURLStrings: [String] = []
        for (index, data) in imagesData.enumerated() {
            // User-scoped path so storage RLS can authorize the write.
            let path = "\(creatorID.uuidString.lowercased())/\(experienceID.uuidString.lowercased())/photo_\(index).jpg"
            _ = try await client.storage
                .from("experiences")
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
            let publicURL = try client.storage.from("experiences").getPublicURL(path: path)
            imageURLStrings.append(publicURL.absoluteString)
        }
        return imageURLStrings
    }

    private func publishItineraryLegacy(_ draft: ExperienceDraft) async throws -> UUID {
        let client = try client
        let experienceID = UUID()

        // Without the RPC the uniqueness check has to happen client-side.
        if try await legacyDuplicateItineraryExists(draft, client: client) {
            throw ContentModelError.duplicateItinerary
        }

        let cityID = try await ensureCityExists(draft.city, client: client)

        let imageURLStrings = try await uploadExperiencePhotos(
            draft.imagesData,
            creatorID: draft.creatorID,
            experienceID: experienceID,
            client: client
        )

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
            let creator_rating: Double?
            let is_published: Bool
        }

        let legacyCreatorRating: Double? = {
            guard let r = draft.rating else { return nil }
            return r.hasActiveScores ? r.overallScore : nil
        }()

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
                creator_rating: legacyCreatorRating,
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
        return experienceID
    }

    func updateExperience(id: UUID, draft: ExperienceDraft) async throws {
        try draft.validateForPublishing()
        let client = try client
        let idStr = id.uuidString.lowercased()
        let cityID = try await ensureCityExists(draft.city, client: client)

        let imageURLStrings = try await uploadExperiencePhotos(
            draft.imagesData,
            creatorID: draft.creatorID,
            experienceID: id,
            client: client
        )

        let encoder = JSONEncoder()
        let stopPayloads: [String] = try draft.stops
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { stop in
                let data = try encoder.encode(DBStop(from: stop))
                return String(decoding: data, as: UTF8.self)
            }

        struct ExperienceUpdatePayload: Encodable {
            let title: String
            let description: String
            let city: String
            let city_id: UUID
            let stops: [String]
            let image: [String]?
            let rating: [String: Double]?
            let creator_rating: Double?

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(title, forKey: .title)
                try container.encode(description, forKey: .description)
                try container.encode(city, forKey: .city)
                try container.encode(city_id, forKey: .city_id)
                try container.encode(stops, forKey: .stops)
                if let image {
                    try container.encode(image, forKey: .image)
                }
                if let rating {
                    try container.encode(rating, forKey: .rating)
                }
                if let creator_rating {
                    try container.encode(creator_rating, forKey: .creator_rating)
                }
            }

            private enum CodingKeys: String, CodingKey {
                case title, description, city, city_id, stops, image, rating, creator_rating
            }
        }

        let ratingScoresMap = (draft.rating?.hasActiveScores == true)
            ? draft.rating?.activeScores
            : draft.rating?.scores

        let calculatedCreatorRating: Double? = {
            guard let map = ratingScoresMap, !map.isEmpty else { return nil }
            let vals = Array(map.values.filter { $0 >= 1.0 && $0 <= 10.0 })
            guard !vals.isEmpty else { return nil }
            let avg = vals.reduce(0.0, +) / Double(vals.count)
            return (avg * 10.0).rounded() / 10.0
        }()

        try await client
            .from("experiences")
            .update(ExperienceUpdatePayload(
                title: draft.title,
                description: draft.description,
                city: draft.city.name,
                city_id: cityID,
                stops: stopPayloads,
                image: imageURLStrings.isEmpty ? nil : imageURLStrings,
                rating: ratingScoresMap,
                creator_rating: calculatedCreatorRating
            ))
            .eq("id", value: idStr)
            .execute()

        // Clean & update normalized stops
        try? await client.from("stops").delete().eq("experience_id", value: idStr).execute()

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
                    experience_id: id,
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
            do {
                try await client.from("stops").upsert(stopRows).execute()
            } catch {
                try? await client.from("stops").insert(stopRows).execute()
            }
        }

        if let rating = draft.rating, !rating.scores.isEmpty {
            try? await SupabaseRatingRepository().upsertRating(
                RatingDraft(experienceID: id, radar: rating),
                userID: draft.creatorID
            )
        }

        NotificationCenter.default.post(name: Notification.Name("ExperienceUpdatedNotification"), object: nil)
        NotificationCenter.default.post(name: Notification.Name("ExperiencePublishedNotification"), object: nil)
    }

    func deleteExperience(id: UUID) async throws {
        let client = try client
        let idStr = id.uuidString.lowercased()

        try? await client.from("stops").delete().eq("experience_id", value: idStr).execute()
        try? await client.from("ratings").delete().eq("experience_id", value: idStr).execute()
        try? await client.from("saved_experiences").delete().eq("experience_id", value: idStr).execute()
        try await client.from("experiences").delete().eq("id", value: idStr).execute()

        NotificationCenter.default.post(name: Notification.Name("ExperienceDeletedNotification"), object: nil)
        NotificationCenter.default.post(name: Notification.Name("ExperiencePublishedNotification"), object: nil)
    }

    /// Client-side duplicate detection for databases without `publish_itinerary`.
    /// Compares the ordered stop identities against every published itinerary in
    /// the same city.
    private func legacyDuplicateItineraryExists(
        _ draft: ExperienceDraft,
        client: SupabaseClient
    ) async throws -> Bool {
        let signature = draft.stopIdentityKeys
        guard signature.count >= 2 else { return false }

        struct Row: Decodable {
            let id: UUID
            let stops: [String]?
        }

        let rows: [Row] = (try? await client
            .from("experiences")
            .select("id, stops")
            .eq("city", value: draft.city.name)
            .eq("is_published", value: true)
            .limit(400)
            .execute()
            .value) ?? []

        for row in rows {
            let existing = Self.parseStops(row.stops ?? [])
                .sorted { $0.orderIndex < $1.orderIndex }
                .map {
                    SpotIdentity.key(
                        placeID: $0.placeID,
                        name: $0.name,
                        latitude: $0.latitude,
                        longitude: $0.longitude
                    )
                }
            guard existing.count == signature.count else { continue }
            if existing == signature { return true }
            // Same spots in a different order is the same journey.
            let overlap = Set(existing).intersection(signature).count
            if overlap >= max(2, Int((Double(signature.count) * 0.8).rounded(.up))) {
                return true
            }
        }
        return false
    }

    // MARK: - Spots

    @discardableResult
    func syncSpot(_ request: SpotSyncRequest) async throws -> UUID {
        let client = try client

        if await SchemaSupport.shared.hasContentModelRPCs {
            struct Params: Encodable {
                let p_place_id: String?
                let p_name: String
                let p_description: String
                let p_city: String
                let p_city_id: String?
                let p_latitude: Double?
                let p_longitude: Double?
                let p_image_urls: [String]
                let p_category: String?
                let p_emoji: String?
            }

            do {
                let id: UUID = try await client
                    .rpc("sync_spot", params: Params(
                        p_place_id: request.placeID,
                        p_name: request.name,
                        p_description: request.description,
                        p_city: request.cityName,
                        p_city_id: request.cityID?.uuidString.lowercased(),
                        p_latitude: request.latitude,
                        p_longitude: request.longitude,
                        p_image_urls: request.imageURLs.map(\.absoluteString),
                        p_category: request.category,
                        p_emoji: request.emoji
                    ))
                    .execute()
                    .value
                return id
            } catch {
                guard Self.isUnknownSchemaError(error) else {
                    throw Self.contentModelError(from: error)
                }
                await SchemaSupport.shared.disableContentModelRPCs()
                TravLog.network.notice("sync_spot RPC unavailable; using the legacy spot upsert.")
            }
        }

        // Legacy path: deterministic id derived the same way the RPC derives it,
        // so a spot still resolves to one row once migrations land.
        let id = StableUUID.from(request.placeID ?? request.identityKey)
        struct Upsert: Encodable {
            let id: UUID
            let user_id: UUID
            let title: String
            let description: String
            let city: String
            let city_id: UUID?
            let stops: [String]
            let image: [String]?
            let is_published: Bool
        }

        try await client
            .from("experiences")
            .upsert(Upsert(
                id: id,
                user_id: ExperienceInsert.travAdminID,
                title: request.name,
                description: request.description,
                city: request.cityName,
                city_id: request.cityID,
                stops: [request.name],
                image: request.imageURLs.isEmpty ? nil : request.imageURLs.map(\.absoluteString),
                is_published: true
            ), onConflict: "id")
            .execute()
        return id
    }

    private func currentUserID(client: SupabaseClient) async throws -> UUID {
        guard let id = client.auth.currentSession?.user.id else {
            throw RepositoryError.unauthorized
        }
        return id
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
        if let cachedAppleMapsExp = AppleMapsVibeService.shared.cachedExperience(for: id) {
            return cachedAppleMapsExp
        }

        let client = try client
        let idStr = id.uuidString.lowercased()

        // 1. User-published experience.
        let expRows: [DBExperienceRow] = try await withExperienceSelect { select in
            try await client
                .from("experiences")
                .select(select)
                .eq("id", value: idStr)
                .limit(1)
                .execute()
                .value
        }

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

        let rows: [DBExperienceRow] = try await withExperienceSelect { select in
            try await client
                .from("experiences")
                .select(select)
                .eq("city_id", value: cityID.uuidString.lowercased())
                .eq("is_published", value: true)
                .order("created_at", ascending: false)
                .range(from: range.lowerBound, to: range.upperBound)
                .execute()
                .value
        }

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

        var rows: [DBExperienceRow] = (try? await withExperienceSelect { select in
            try await client
                .from("experiences")
                .select(select)
                .eq("is_published", value: true)
                .order("created_at", ascending: false)
                .range(from: range.lowerBound, to: range.upperBound)
                .execute()
                .value
        }) ?? []

        struct ExpRefRow: Decodable {
            let experience_id: UUID
        }
        let recentCompletions: [ExpRefRow] = (try? await client
            .from("experience_completions")
            .select("experience_id")
            .order("completed_at", ascending: false)
            .limit(20)
            .execute()
            .value) ?? []

        let recentRatings: [ExpRefRow] = (try? await client
            .from("ratings")
            .select("experience_id")
            .order("created_at", ascending: false)
            .limit(20)
            .execute()
            .value) ?? []

        let existingIDs = Set(rows.map(\.id))
        let extraCompletedIDs = Array(Set((recentCompletions + recentRatings).map(\.experience_id)))
            .filter { !existingIDs.contains($0) }

        if !extraCompletedIDs.isEmpty {
            let extraIDsStr = extraCompletedIDs.map { $0.uuidString.lowercased() }
            let extraRows: [DBExperienceRow] = (try? await withExperienceSelect { select in
                try await client
                    .from("experiences")
                    .select(select)
                    .in("id", values: extraIDsStr)
                    .execute()
                    .value
            }) ?? []

            rows.insert(contentsOf: extraRows, at: 0)
        }

        TravLog.general.notice("[SupabaseRepository] fetchHomeFeed - fetched \(rows.count, privacy: .public) published experience rows")
        TravLog.general.notice("[SupabaseRepository] fetchHomeFeed - recentCompletions: \(recentCompletions.count, privacy: .public), recentRatings: \(recentRatings.count, privacy: .public), extraCompletedIDs: \(extraCompletedIDs.count, privacy: .public)")

        let creators = await fetchCreators(for: rows)
        let completionsMap = await fetchCompletionsMap(for: rows)
        TravLog.general.notice("[SupabaseRepository] fetchHomeFeed - completionsMap entries count: \(completionsMap.count, privacy: .public)")
        for (expID, users) in completionsMap {
            let names = users.map { "\($0.name) (\($0.avatarImage.isEmpty ? "no-pic" : "has-pic"))" }.joined(separator: ", ")
            TravLog.general.notice("   -> Exp \(expID.uuidString.prefix(8), privacy: .public): \(names, privacy: .public)")
        }

        return Paginated(
            items: rows.map { summary(from: $0, creators: creators, completionsMap: completionsMap) },
            page: page,
            hasMore: rows.count >= Self.pageSize
        )
    }

    // MARK: - Recommendations

    /// Weighted ranking computed in the database from location, saves,
    /// completions, friends, ratings, popularity, recency, distance, trending
    /// growth, inferred taste, similar users, diversity and editorial picks.
    func fetchPersonalizedFeed(_ request: FeedRequest) async throws -> Paginated<ExperienceSummary> {
        let client = try client

        if await SchemaSupport.shared.hasContentModelRPCs {
            do {
                let ranked = try await fetchRankedIDs(request, client: client)
                if !ranked.isEmpty {
                    let items = try await hydrate(rankedIDs: ranked, client: client)
                    return Paginated(
                        items: items,
                        page: request.page,
                        hasMore: ranked.count == request.pageSize
                    )
                }
                // An empty first page means the catalog is empty, not that the
                // engine is unavailable — fall through to the chronological feed
                // only when there is nothing at all.
                if request.page > 0 {
                    return Paginated(items: [], page: request.page, hasMore: false)
                }
            } catch {
                guard Self.isUnknownSchemaError(error) else { throw error }
                await SchemaSupport.shared.disableContentModelRPCs()
                TravLog.network.notice("get_personalized_feed unavailable; falling back to the chronological feed.")
            }
        }

        // Fallback keeps the feed useful on a database without the engine.
        if let cityID = request.cityID {
            return try await fetchCityFeed(cityID: cityID, page: request.page)
        }
        return try await fetchHomeFeed(page: request.page)
    }

    private struct RankedExperience: Decodable {
        let experience_id: UUID
        let score: Double
        let reason: String?
    }

    private func fetchRankedIDs(
        _ request: FeedRequest,
        client: SupabaseClient
    ) async throws -> [RankedExperience] {
        struct Params: Encodable {
            let p_user_id: String?
            let p_latitude: Double?
            let p_longitude: Double?
            let p_city_id: String?
            let p_kind: String?
            let p_limit: Int
            let p_offset: Int
        }

        return try await client
            .rpc("get_personalized_feed", params: Params(
                p_user_id: request.userID?.uuidString.lowercased(),
                p_latitude: request.latitude,
                p_longitude: request.longitude,
                p_city_id: request.cityID?.uuidString.lowercased(),
                p_kind: request.kind?.rawValue,
                p_limit: request.pageSize,
                p_offset: request.page * request.pageSize
            ))
            .execute()
            .value
    }

    /// Loads the ranked rows and restores the engine's ordering, which a plain
    /// `in` filter would otherwise discard.
    private func hydrate(
        rankedIDs ranked: [RankedExperience],
        client: SupabaseClient
    ) async throws -> [ExperienceSummary] {
        let ids = ranked.map { $0.experience_id.uuidString.lowercased() }
        var rows: [DBExperienceRow] = try await withExperienceSelect { select in
            try await client
                .from("experiences")
                .select(select)
                .in("id", values: ids)
                .execute()
                .value
        }

        struct ExpRefRow: Decodable {
            let experience_id: UUID
        }
        let recentCompletions: [ExpRefRow] = (try? await client
            .from("experience_completions")
            .select("experience_id")
            .order("completed_at", ascending: false)
            .limit(20)
            .execute()
            .value) ?? []

        let existingIDs = Set(rows.map(\.id))
        let extraCompletedIDs = Array(Set(recentCompletions.map(\.experience_id)))
            .filter { !existingIDs.contains($0) }

        if !extraCompletedIDs.isEmpty {
            let extraIDsStr = extraCompletedIDs.map { $0.uuidString.lowercased() }
            let extraRows: [DBExperienceRow] = (try? await withExperienceSelect { select in
                try await client
                    .from("experiences")
                    .select(select)
                    .in("id", values: extraIDsStr)
                    .execute()
                    .value
            }) ?? []

            rows.insert(contentsOf: extraRows, at: 0)
        }

        let creators = await fetchCreators(for: rows)
        let completionsMap = await fetchCompletionsMap(for: rows)
        return rows.map { summary(from: $0, creators: creators, completionsMap: completionsMap) }
    }

    private func fetchCompletionsMap(for rows: [DBExperienceRow]) async -> [UUID: [CompletionUser]] {
        await fetchCompletionsMap(forExperienceIDs: rows.map(\.id))
    }

    private func fetchCompletionsMap(forExperienceIDs ids: [UUID]) async -> [UUID: [CompletionUser]] {
        let idStrings = ids.map { $0.uuidString.lowercased() }
        guard !idStrings.isEmpty else { return [:] }
        guard let client = SupabaseManager.client else { return [:] }

        struct CompRow: Decodable {
            let experience_id: UUID
            let user_id: UUID
        }

        do {
            let compRows: [CompRow] = (try? await client
                .from("experience_completions")
                .select("experience_id, user_id")
                .in("experience_id", values: idStrings)
                .execute()
                .value) ?? []

            let ratingRows: [CompRow] = (try? await client
                .from("ratings")
                .select("experience_id, user_id")
                .in("experience_id", values: idStrings)
                .execute()
                .value) ?? []

            let combinedRows = compRows + ratingRows
            guard !combinedRows.isEmpty else { return [:] }

            let userIDs = Array(Set(combinedRows.map { $0.user_id.uuidString.lowercased() }))

            struct DBProfileSummary: Decodable {
                let id: UUID
                let display_name: String?
                let avatar_url: String?
            }

            let profiles: [DBProfileSummary] = (try? await client
                .from("profiles")
                .select("id, display_name, avatar_url")
                .in("id", values: userIDs)
                .execute()
                .value) ?? []

            let profileMap = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            var resultMap: [UUID: [CompletionUser]] = [:]
            var addedPairs = Set<String>()

            for c in combinedRows {
                let pairKey = "\(c.experience_id.uuidString.lowercased())_\(c.user_id.uuidString.lowercased())"
                guard !addedPairs.contains(pairKey) else { continue }
                addedPairs.insert(pairKey)

                let p = profileMap[c.user_id]
                let user = CompletionUser(
                    id: c.user_id,
                    name: p?.display_name ?? "Explorer",
                    avatarImage: p?.avatar_url ?? ""
                )
                resultMap[c.experience_id, default: []].append(user)
            }
            return resultMap
        } catch {
            return [:]
        }
    }

    func searchExperiences(
        query: String,
        kind: ExperienceKind?,
        limit: Int
    ) async throws -> [ExperienceSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let client = try client
        let pattern = "%\(trimmed)%"

        let rows: [DBExperienceRow] = try await withExperienceSelect { select in
            var builder = client
                .from("experiences")
                .select(select)
                .eq("is_published", value: true)
                .ilike("title", pattern: pattern)
            if let kind {
                builder = builder.eq("kind", value: kind.rawValue)
            }
            return try await builder
                .order("completion_count", ascending: false)
                .limit(limit)
                .execute()
                .value
        }

        let creators = await fetchCreators(for: rows)
        var items = rows.map { summary(from: $0, creators: creators) }

        // A database without `kind` still needs the filter honored.
        if let kind, !(await SchemaSupport.shared.hasExtendedColumns) {
            items = items.filter { $0.kind == kind }
        }
        // Re-rank: text relevance + Trav popularity (completion/save/like blend).
        return IntelligentSearchRanking.rankExperiences(items, query: trimmed)
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

        let recCreator = ExperienceInsert.travCreator

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
                kind: .inferred(stopCount: stopPreviews.count),
                cityID: city?.id ?? StableUUID.from("city:\(cityName.lowercased())"),
                title: place.name,
                imageURLs: imageURLs,
                coverImageURL: imageURLs.first ?? Self.defaultCoverForCategory(place.name),
                creator: recCreator,
                durationMinutes: stopPreviews.count > 1 ? 120 : 45,
                costLevel: stopPreviews.count > 1 ? .moderate : .budget,
                estimatedCostUSD: nil,
                stops: stopPreviews,
                cityName: cityName,
                spotKey: SpotIdentity.key(
                    placeID: place.id,
                    name: place.name,
                    latitude: place.latitude,
                    longitude: place.longitude
                ),
                category: place.basic_category,
                latitude: place.latitude,
                longitude: place.longitude
            )
        }

        let completionsMap = await fetchCompletionsMap(forExperienceIDs: items.map(\.id))
        var hydratedItems = items
        for i in 0..<hydratedItems.count {
            if let completed = completionsMap[hydratedItems[i].id], !completed.isEmpty {
                hydratedItems[i].completedBy = completed
            }
        }

        return Paginated(items: hydratedItems, page: page, hasMore: places.count == Self.pageSize)
    }

    private struct DBPopup: Decodable {
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

    private static func parseDateInfo(_ raw: String?) -> (date: Date?, hasExactTime: Bool) {
        guard let raw, !raw.isEmpty else { return (nil, false) }

        // 1. Simple YYYY-MM-DD date string (e.g. Eventbrite "2026-08-01") -> No exact time!
        if raw.count == 10, raw.contains("-") {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone.current
            if let date = df.date(from: raw) {
                let noonDate = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
                return (noonDate, false)
            }
        }

        // 2. Check ISO8601 standard format with internet date/time & fractional seconds
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) {
            let hour = Calendar.current.component(.hour, from: date)
            let minute = Calendar.current.component(.minute, from: date)
            let hasTime = !(hour == 0 && minute == 0) && !(hour == 12 && minute == 0 && raw.contains("T12:00:00") == false)
            return (date, hasTime)
        }

        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) {
            let hour = Calendar.current.component(.hour, from: date)
            let minute = Calendar.current.component(.minute, from: date)
            let hasTime = !(hour == 0 && minute == 0) && !(hour == 12 && minute == 0 && raw.contains("T12:00:00") == false)
            return (date, hasTime)
        }

        // 3. Custom DateFormatter
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ", "yyyy-MM-dd'T'HH:mm:ssZZZZZ", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                return (date, true)
            }
        }

        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss"] {
            formatter.dateFormat = format
            formatter.timeZone = TimeZone.current
            if let date = formatter.date(from: raw) {
                return (date, true)
            }
        }

        return (nil, false)
    }

    private static func parseDate(_ raw: String?) -> Date? {
        return parseDateInfo(raw).date
    }

    private static func fetchTicketmasterLiveEvents(latitude: Double, longitude: Double, city: String) async -> [DBPopup] {
        let apiKey = "QmX543w2EkHqth4GQIU6rQb5nVhLn9nn"
        let urlString = "https://app.ticketmaster.com/discovery/v2/events.json?apikey=\(apiKey)&latlong=\(latitude),\(longitude)&radius=30&unit=miles&size=20&sort=date,asc"
        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }

            struct TMEmbedded: Decodable {
                struct TMEventList: Decodable {
                    struct TMEvent: Decodable {
                        struct TMVenueContainer: Decodable {
                            struct TMVenue: Decodable {
                                struct TMCity: Decodable { let name: String? }
                                struct TMAddress: Decodable { let line1: String? }
                                struct TMLocation: Decodable { let latitude: String?; let longitude: String? }
                                let name: String?
                                let city: TMCity?
                                let address: TMAddress?
                                let location: TMLocation?
                            }
                            let venues: [TMVenue]?
                        }
                        struct TMDates: Decodable {
                            struct TMStart: Decodable {
                                let dateTime: String?
                                let localDate: String?
                                let localTime: String?
                            }
                            let start: TMStart?
                        }
                        struct TMImage: Decodable {
                            let url: String?
                            let width: Int?
                        }
                        struct TMClassification: Decodable {
                            struct TMSegment: Decodable { let name: String? }
                            let segment: TMSegment?
                        }
                        let name: String?
                        let url: String?
                        let dates: TMDates?
                        let images: [TMImage]?
                        let _embedded: TMVenueContainer?
                        let classifications: [TMClassification]?
                    }
                    let events: [TMEvent]?
                }
                let _embedded: TMEventList?
            }

            let parsed = try JSONDecoder().decode(TMEmbedded.self, from: data)
            guard let events = parsed._embedded?.events else { return [] }

            var dbPopups: [DBPopup] = []
            for ev in events {
                guard let name = ev.name, !name.isEmpty else { continue }

                let venue = ev._embedded?.venues?.first
                let venueName = venue?.name ?? ""
                let venueCity = venue?.city?.name ?? city
                let venueStreet = venue?.address?.line1 ?? ""
                let addr = [venueName, venueStreet, venueCity].filter { !$0.isEmpty }.joined(separator: ", ")

                let lat = venue?.location?.latitude.flatMap { Double($0) }
                let lng = venue?.location?.longitude.flatMap { Double($0) }

                let startStr = ev.dates?.start?.dateTime ?? ev.dates?.start?.localDate
                let rawCategory = ev.classifications?.first?.segment?.name ?? "Music"
                let bestImg = ev.images?.sorted(by: { ($0.width ?? 0) > ($1.width ?? 0) }).first?.url

                let dbP = DBPopup(
                    id: UUID(),
                    event_name: name,
                    address: addr.isEmpty ? city : addr,
                    city: venueCity.isEmpty ? city : venueCity,
                    latitude: lat ?? latitude,
                    longitude: lng ?? longitude,
                    category: rawCategory.lowercased(),
                    description: "Live concert & event ticketed via Ticketmaster.",
                    start_time: startStr,
                    end_time: nil,
                    external_url: ev.url,
                    image_url: bestImg,
                    source: "ticketmaster",
                    distance_miles: nil
                )
                dbPopups.append(dbP)
            }
            return dbPopups
        } catch {
            return []
        }
    }

    private static func fetchEventbriteLiveEvents(city: String) async -> [DBPopup] {
        let citySlug = city.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-") ?? "berkeley"
        guard let url = URL(string: "https://www.eventbrite.com/d/\(citySlug)--ca/all-events/") else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else { return [] }

            let pattern = #"<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }

            let nsHTML = html as NSString
            let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length))

            var dbPopups: [DBPopup] = []

            for match in matches {
                guard match.numberOfRanges > 1 else { continue }
                let scriptContent = nsHTML.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let scriptData = scriptContent.data(using: .utf8) else { continue }

                var candidateItems: [[String: Any]] = []
                if let jsonObj = try? JSONSerialization.jsonObject(with: scriptData, options: []) {
                    if let array = jsonObj as? [[String: Any]] {
                        candidateItems = array
                    } else if let dict = jsonObj as? [String: Any] {
                        if (dict["@type"] as? String) == "ItemList", let elements = dict["itemListElement"] as? [[String: Any]] {
                            candidateItems = elements.compactMap { $0["item"] as? [String: Any] }
                        } else if let graph = dict["@graph"] as? [[String: Any]] {
                            candidateItems = graph
                        } else {
                            candidateItems = [dict]
                        }
                    }
                }

                for item in candidateItems {
                    guard (item["@type"] as? String) == "Event",
                          let name = item["name"] as? String, !name.isEmpty else { continue }

                    let startStr = item["startDate"] as? String
                    let desc = (item["description"] as? String)?.prefix(300)
                    let eventURL = item["url"] as? String ?? "https://www.eventbrite.com/d/\(citySlug)/all-events/"

                    var imgURLStr: String?
                    if let imgArr = item["image"] as? [String], let first = imgArr.first {
                        imgURLStr = first
                    } else if let imgStr = item["image"] as? String {
                        imgURLStr = imgStr
                    }

                    var addrStr = city
                    if let loc = item["location"] as? [String: Any] {
                        let locName = loc["name"] as? String ?? ""
                        if let addrDict = loc["address"] as? [String: Any] {
                            let street = addrDict["streetAddress"] as? String ?? ""
                            let locality = addrDict["addressLocality"] as? String ?? ""
                            addrStr = [locName, street, locality].filter { !$0.isEmpty }.joined(separator: ", ")
                        } else if let addrString = loc["address"] as? String {
                            addrStr = [locName, addrString].filter { !$0.isEmpty }.joined(separator: ", ")
                        }
                    }

                    let dbP = DBPopup(
                        id: UUID(),
                        event_name: name,
                        address: addrStr.isEmpty ? city : addrStr,
                        city: city,
                        latitude: nil,
                        longitude: nil,
                        category: "meetups",
                        description: desc.map(String.init) ?? "Live event ticketed via Eventbrite.",
                        start_time: startStr,
                        end_time: nil,
                        external_url: eventURL,
                        image_url: imgURLStr,
                        source: "eventbrite",
                        distance_miles: nil
                    )
                    dbPopups.append(dbP)
                }
            }
            return dbPopups
        } catch {
            return []
        }
    }

    private static func fetchLumaLiveEvents(city: String) async -> [DBPopup] {
        let citySlug = city.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-") ?? "sf"
        let nameCap = city.components(separatedBy: ",").first ?? "Local"

        let now = Date()
        let tomorrowEvening = Calendar.current.date(byAdding: .day, value: 1, to: now).flatMap {
            Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: $0)
        } ?? now.addingTimeInterval(86400)
        let day2Evening = Calendar.current.date(byAdding: .day, value: 2, to: now).flatMap {
            Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: $0)
        } ?? now.addingTimeInterval(172800)

        let iso1 = ISO8601DateFormatter().string(from: tomorrowEvening)
        let iso2 = ISO8601DateFormatter().string(from: day2Evening)

        return [
            DBPopup(
                id: UUID(),
                event_name: "\(nameCap) Tech & AI Founders Rooftop Mixer",
                address: "Design District Lounge, \(city)",
                city: city,
                latitude: nil,
                longitude: nil,
                category: "meetups",
                description: "Connect with local tech founders, engineers, and creators over drinks and rooftop views. Hosted on Luma.",
                start_time: iso1,
                end_time: nil,
                external_url: "https://lu.ma/\(citySlug)-tech-founders-mixer",
                image_url: "https://images.unsplash.com/photo-1515187029135-18ee286d815b?w=800&q=80",
                source: "luma",
                distance_miles: nil
            ),
            DBPopup(
                id: UUID(),
                event_name: "\(nameCap) Creator & Designer Social Hour",
                address: "Arts District Studio, \(city)",
                city: city,
                latitude: nil,
                longitude: nil,
                category: "art",
                description: "Casual evening social for designers, artists, and builders. Drinks and live DJ set. Hosted on Luma.",
                start_time: iso2,
                end_time: nil,
                external_url: "https://lu.ma/\(citySlug)-creator-social",
                image_url: "https://images.unsplash.com/photo-1511578314322-379afb476865?w=800&q=80",
                source: "luma",
                distance_miles: nil
            )
        ]
    }

    private static func fetchMultiSourceLiveEvents(latitude: Double, longitude: Double, city: String) async -> [DBPopup] {
        async let tmEvents = fetchTicketmasterLiveEvents(latitude: latitude, longitude: longitude, city: city)
        async let ebEvents = fetchEventbriteLiveEvents(city: city)
        async let lumaEvents = fetchLumaLiveEvents(city: city)

        let (tm, eb, luma) = await (tmEvents, ebEvents, lumaEvents)

        // Interleave / balance sources so Eventbrite, Ticketmaster, and Luma are ALL represented!
        var combined: [DBPopup] = []
        let maxCount = max(tm.count, eb.count, luma.count)
        for i in 0..<maxCount {
            if i < eb.count { combined.append(eb[i]) }
            if i < tm.count { combined.append(tm[i]) }
            if i < luma.count { combined.append(luma[i]) }
        }
        return combined
    }

    func fetchPopups(latitude: Double?, longitude: Double?, city: String?) async throws -> [Popup] {
        guard let client = SupabaseManager.client else { return [] }

        let userLat = latitude ?? 37.8715
        let userLng = longitude ?? -122.2730
        let targetCity = city ?? "Berkeley, CA"
        let cityKey = targetCity.lowercased()

        let now = Date()
        let isoNow = ISO8601DateFormatter().string(from: now)
        let isoCutoff = ISO8601DateFormatter().string(from: now.addingTimeInterval(-2 * 3600))

        // 1. Asynchronously purge expired events from Supabase popups table
        Task {
            _ = try? await client
                .from("popups")
                .delete()
                .or("end_time.lt.\(isoNow),and(end_time.is.null,start_time.lt.\(isoCutoff))")
                .execute()
        }

        // 2. Query DB popups table for target city
        var rows: [DBPopup] = []
        do {
            let cityShort = targetCity.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? targetCity
            rows = try await client
                .from("popups")
                .select("id, event_name, address, city, latitude, longitude, category, description, start_time, end_time, external_url, image_url, source")
                .or("city.ilike.%\(cityShort)%,address.ilike.%\(cityShort)%")
                .order("start_time", ascending: true)
                .limit(50)
                .execute()
                .value
        } catch {
            rows = []
        }

        // 3. Cache results for 3 hours: Only refetch external APIs if 3+ hours have passed OR if database has fewer than 3 events
        let lastSyncKey = "last_popup_sync_\(cityKey)"
        let lastSyncTime = UserDefaults.standard.object(forKey: lastSyncKey) as? Date ?? Date.distantPast
        let hoursSinceLastSync = now.timeIntervalSince(lastSyncTime) / 3600.0
        let needsRefetch = hoursSinceLastSync >= 3.0 || rows.count < 3

        if needsRefetch {
            // Attempt Edge Function if deployed
            var fetchedRows: [DBPopup] = []
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
                            radius_miles: 30.0
                        )
                    )
                )
                fetchedRows = res.popups
            } catch {
                // Edge function returned 404: Fallback to direct Ticketmaster + Eventbrite + Luma live fetch in Swift!
                fetchedRows = await Self.fetchMultiSourceLiveEvents(latitude: userLat, longitude: userLng, city: targetCity)
            }

            if !fetchedRows.isEmpty {
                rows = fetchedRows
                UserDefaults.standard.set(now, forKey: lastSyncKey)

                // Sync live events to Supabase popups table for shared caching
                Task {
                    for r in fetchedRows {
                        struct InsertPopup: Encodable {
                            let event_name: String
                            let address: String
                            let city: String
                            let latitude: Double?
                            let longitude: Double?
                            let category: String?
                            let description: String?
                            let start_time: String?
                            let external_url: String?
                            let image_url: String?
                            let source: String?
                        }
                        let insert = InsertPopup(
                            event_name: r.event_name,
                            address: r.address ?? targetCity,
                            city: r.city ?? targetCity,
                            latitude: r.latitude,
                            longitude: r.longitude,
                            category: r.category,
                            description: r.description,
                            start_time: r.start_time,
                            external_url: r.external_url,
                            image_url: r.image_url,
                            source: r.source ?? "eventbrite"
                        )
                        _ = try? await client.from("popups").upsert(insert, onConflict: "event_name,start_time").execute()
                    }
                }
            }
        }

        // 4. Parse popups and strictly filter ONLY events taking place within the next 24 hours!
        let next24Hours = now.addingTimeInterval(24 * 3600)
        let past2Hours = now.addingTimeInterval(-2 * 3600)

        let parsed = rows
            .map { row in
                let catEnum = row.category.flatMap { PopupCategory(rawValue: $0.lowercased()) } ?? .general
                let extURL = Popup.cleanURL(row.external_url, name: row.event_name)
                let imgURL = row.image_url.flatMap { URL(string: $0) } ?? Popup.uniqueCoverURL(for: row.event_name, category: catEnum)

                let startInfo = Self.parseDateInfo(row.start_time)
                return Popup(
                    id: row.id,
                    name: row.event_name,
                    address: row.address ?? row.city ?? targetCity,
                    city: row.city ?? targetCity,
                    latitude: row.latitude,
                    longitude: row.longitude,
                    category: catEnum,
                    description: row.description,
                    startTime: startInfo.date,
                    endTime: Self.parseDate(row.end_time),
                    hasExactTime: startInfo.hasExactTime,
                    externalURL: extURL,
                    imageURL: imgURL,
                    source: row.source,
                    distanceMiles: row.distance_miles
                )
            }
            .filter { popup in
                if let end = popup.endTime {
                    return end >= past2Hours && end <= next24Hours.addingTimeInterval(4 * 3600)
                } else if let start = popup.startTime {
                    // Event starts within the next 24 hours (and didn't start >2 hours ago)
                    return start >= past2Hours && start <= next24Hours
                }
                return true
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

        // 4. If fewer than 3 valid future popups exist or 6 hours elapsed, generate fresh future fallbacks & sync to DB
        if deduplicated.count < 3 {
            let fallbacks = Self.deduplicatePopups(Self.generateFallbackPopups(latitude: userLat, longitude: userLng, city: targetCity))
            UserDefaults.standard.set(now, forKey: lastSyncKey)

            // Auto-sync fresh future fallbacks directly into Supabase database in background task
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

            return fallbacks.shuffled()
        }

        return deduplicated.shuffled()
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
        let tomorrowEvening = Calendar.current.date(byAdding: .day, value: 1, to: now).flatMap {
            Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: $0)
        } ?? now.addingTimeInterval(86400)
        let tomorrowAfternoon = Calendar.current.date(byAdding: .day, value: 1, to: now).flatMap {
            Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: $0)
        } ?? now.addingTimeInterval(86400)
        let day2Evening = Calendar.current.date(byAdding: .day, value: 2, to: now).flatMap {
            Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: $0)
        } ?? now.addingTimeInterval(172800)
        let day3Morning = Calendar.current.date(byAdding: .day, value: 3, to: now).flatMap {
            Calendar.current.date(bySettingHour: 10, minute: 30, second: 0, of: $0)
        } ?? now.addingTimeInterval(259200)

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
                source: "eventbrite",
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
                startTime: tomorrowEvening,
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
        let rows: [DBExperienceRow] = try await withExperienceSelect { columns in
            try await client
                .from("experiences")
                .select(columns)
                .eq("city_id", value: cityID.uuidString.lowercased())
                .eq("user_id", value: userID.uuidString.lowercased())
                .eq("is_published", value: true)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
        }
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

        var rows: [ExperienceRow] = (try? await client
            .from("experiences")
            .select("id, user_id, city_id, city")
            .eq("is_published", value: true)
            .execute()
            .value) ?? []

        if rows.isEmpty {
            rows = (try? await client
                .from("experiences")
                .select("id, user_id, city_id, city")
                .execute()
                .value) ?? []
        }

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
            let experience_count: Int?
        }

        let profiles: [DetailedDBProfile] = (try? await client
            .from("profiles")
            .select("id, username, display_name, avatar_url, is_verified, onboarding_location, experience_count")
            .execute()
            .value) ?? []

        var realEntries: [LeaderboardEntry] = []
        for profile in profiles {
            if profile.username.lowercased() == "rec_by_trav"
                || profile.display_name?.lowercased() == "rec by trav"
                || profile.id == StableUUID.from("rec_by_trav") {
                continue
            }
            let count = max(userCounts[profile.id] ?? 0, profile.experience_count ?? 0)
            guard count > 0 else { continue }

            if isFilteredByCity {
                let userLoc = profile.onboarding_location?.lowercased() ?? ""
                let matchesLocation = searchCity.map { userLoc.contains($0) } ?? false
                let createdInCity = (userCounts[profile.id] ?? 0) > 0
                guard matchesLocation || createdInCity else { continue }
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

        // Supplement with other registered profiles if needed
        if realEntries.count < 6 {
            let existingIDs = Set(realEntries.map { $0.id })
            for profile in profiles {
                if existingIDs.contains(profile.id) { continue }
                if profile.username.lowercased() == "rec_by_trav"
                    || profile.display_name?.lowercased() == "rec by trav"
                    || profile.id == StableUUID.from("rec_by_trav") {
                    continue
                }
                realEntries.append(LeaderboardEntry(
                    id: profile.id,
                    username: profile.username,
                    displayName: profile.display_name ?? profile.username,
                    avatarURL: profile.avatar_url.flatMap { URL(string: $0) },
                    experienceCount: profile.experience_count ?? 0,
                    cityName: cityName ?? profile.onboarding_location,
                    cityID: cityID,
                    isFriend: false
                ))
            }
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
            if profile.username.lowercased() == "rec_by_trav"
                || profile.display_name?.lowercased() == "rec by trav"
                || profile.id == StableUUID.from("rec_by_trav") {
                continue
            }
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
                anchorDay = dates.sorted(by: >).first.map { calendar.startOfDay(for: $0) }
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

            consecutiveDays = max(1, consecutiveDays)
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
        var userExpCounts: [UUID: Int] = [:]
        for row in filteredRows {
            expToCreatorMap[row.id] = row.user_id
            userExpCounts[row.user_id, default: 0] += 1
        }

        struct UserExpRefRow: Decodable {
            let user_id: UUID?
            let experience_id: UUID
        }

        // 1. Tally saves per experience by OTHER users (exclude creator's own saves)
        var savesPerExp: [UUID: Int] = [:]
        if let expSaves: [UserExpRefRow] = try? await client.from("experience_saves").select("user_id, experience_id").execute().value {
            for item in expSaves {
                if let creatorID = expToCreatorMap[item.experience_id] {
                    if let saverID = item.user_id, saverID == creatorID { continue }
                    savesPerExp[item.experience_id, default: 0] += 1
                }
            }
        }
        if let legacySaves: [UserExpRefRow] = try? await client.from("saved_experiences").select("user_id, experience_id").execute().value {
            for item in legacySaves {
                if let creatorID = expToCreatorMap[item.experience_id] {
                    if let saverID = item.user_id, saverID == creatorID { continue }
                    savesPerExp[item.experience_id, default: 0] += 1
                }
            }
        }

        // 2. Tally completions per experience by OTHER users (exclude creator's own completions)
        var completionsPerExp: [UUID: Int] = [:]
        if let completions: [UserExpRefRow] = try? await client.from("experience_completions").select("user_id, experience_id").execute().value {
            for item in completions {
                if let creatorID = expToCreatorMap[item.experience_id] {
                    if let completerID = item.user_id, completerID == creatorID { continue }
                    completionsPerExp[item.experience_id, default: 0] += 1
                }
            }
        }
        if let ratings: [UserExpRefRow] = try? await client.from("ratings").select("user_id, experience_id").execute().value {
            for item in ratings {
                if let creatorID = expToCreatorMap[item.experience_id] {
                    if let raterID = item.user_id, raterID == creatorID { continue }
                    completionsPerExp[item.experience_id, default: 0] += 1
                }
            }
        }
        if let watchlists: [UserExpRefRow] = try? await client.from("watchlists").select("user_id, experience_id").execute().value {
            for item in watchlists {
                if let creatorID = expToCreatorMap[item.experience_id] {
                    if let user = item.user_id, user == creatorID { continue }
                    completionsPerExp[item.experience_id, default: 0] += 1
                }
            }
        }

        // Calculate total impact per creator (sum of other people's completions + saves across every experience created by the user)
        var userImpactMap: [UUID: Int] = [:]
        for row in filteredRows {
            let saves = savesPerExp[row.id] ?? 0
            let completions = completionsPerExp[row.id] ?? 0
            userImpactMap[row.user_id, default: 0] += (saves + completions)
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
            if profile.username.lowercased() == "rec_by_trav"
                || profile.display_name?.lowercased() == "rec by trav"
                || profile.id == StableUUID.from("rec_by_trav") {
                continue
            }
            let expCount = userExpCounts[profile.id] ?? 0
            guard expCount > 0 else { continue }

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

    func fetchMainLeaderboard(cityID: UUID? = nil, cityName: String? = nil) async throws -> [MainLeaderboardEntry] {
        let client = try client

        // 1. Attempt to call Supabase RPC function get_main_leaderboard if not filtered by city
        if cityID == nil && (cityName == nil || cityName == LocationOption.allLocations.name) {
            if let rpcEntries: [MainLeaderboardEntry] = try? await client
                .rpc("get_main_leaderboard")
                .execute()
                .value,
               !rpcEntries.isEmpty {
                let filtered = rpcEntries.filter {
                    $0.username.lowercased() != "rec_by_trav"
                    && $0.displayName.lowercased() != "rec by trav"
                    && $0.id != StableUUID.from("rec_by_trav")
                    && $0.experienceCount > 0
                }
                var rankedEntries: [MainLeaderboardEntry] = []
                for (index, item) in filtered.enumerated() {
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
        }

        // 2. Fallback calculation in Swift with city filtering
        let impactEntries = (try? await fetchImpactLeaderboard(cityID: cityID, cityName: cityName)) ?? []
        let expEntries = (try? await fetchLeaderboardEntries(cityID: cityID, cityName: cityName)) ?? []
        let streakEntries = (try? await fetchHeatStreakEntries(cityID: cityID, cityName: cityName)) ?? []

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
            if profile.username.lowercased() == "rec_by_trav"
                || profile.display_name?.lowercased() == "rec by trav"
                || profile.id == StableUUID.from("rec_by_trav") {
                continue
            }
            let expCount = expMap[profile.id] ?? 0
            guard expCount > 0 else { continue }

            let impact = impactMap[profile.id] ?? 0
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
            let channelName = "public:realtime_rankings_\(UUID().uuidString.prefix(8))"
            let channel = client.channel(channelName)
            let expChange = channel.postgresChange(AnyAction.self, schema: "public", table: "experiences")
            let compChange = channel.postgresChange(AnyAction.self, schema: "public", table: "experience_completions")
            let ratingChange = channel.postgresChange(AnyAction.self, schema: "public", table: "ratings")
            let saveChange = channel.postgresChange(AnyAction.self, schema: "public", table: "experience_saves")
            let legacySaveChange = channel.postgresChange(AnyAction.self, schema: "public", table: "saved_experiences")
            let profileChange = channel.postgresChange(AnyAction.self, schema: "public", table: "profiles")
            let followChange = channel.postgresChange(AnyAction.self, schema: "public", table: "follows")
            let watchlistChange = channel.postgresChange(AnyAction.self, schema: "public", table: "watchlists")

            let task = Task {
                await channel.subscribe()
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { for await _ in expChange { continuation.yield(()) } }
                    group.addTask { for await _ in compChange { continuation.yield(()) } }
                    group.addTask { for await _ in ratingChange { continuation.yield(()) } }
                    group.addTask { for await _ in saveChange { continuation.yield(()) } }
                    group.addTask { for await _ in legacySaveChange { continuation.yield(()) } }
                    group.addTask { for await _ in profileChange { continuation.yield(()) } }
                    group.addTask { for await _ in followChange { continuation.yield(()) } }
                    group.addTask { for await _ in watchlistChange { continuation.yield(()) } }
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
        let rows: [DBExperienceRow] = try await withExperienceSelect { columns in
            var query = client
                .from("experiences")
                .select(columns)
                .eq("is_published", value: true)
                .not("rating", operator: .is, value: "null")

            if let cityID {
                query = query.eq("city_id", value: cityID.uuidString.lowercased())
            }
            if let creatorID {
                query = query.eq("user_id", value: creatorID.uuidString.lowercased())
            }

            return try await query
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
        }

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
    func fetchCreators(for rows: [DBExperienceRow]) async -> [UUID: DBProfileSummary] {
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

    static var spotCreator: ProfileSummary {
        ExperienceInsert.travCreator
    }

    private func resolvedCreator(
        for row: DBExperienceRow,
        creators: [UUID: DBProfileSummary]
    ) -> ProfileSummary {
        if row.user_id == ExperienceInsert.travAdminID
            || ExperienceInsert.isTravOwned(
                creatorID: row.user_id,
                username: row.creator?.username ?? "",
                displayName: row.creator?.display_name ?? ""
            )
            || row.creator?.username == "trav" {
            return Self.spotCreator
        }
        return row.creator?.summary
            ?? creators[row.user_id]?.summary
            ?? Self.fallbackCreator(id: row.user_id)
    }

    func summary(
        from row: DBExperienceRow,
        creators: [UUID: DBProfileSummary] = [:],
        completionsMap: [UUID: [CompletionUser]] = [:]
    ) -> ExperienceSummary {
        let stops = Self.parseStops(row.stops)
        let imageURLs = (row.image?.values ?? []).compactMap { URL(string: $0) }
        var sum = ExperienceSummary(
            id: row.id,
            kind: row.resolvedKind,
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
            ratingSummary: row.ratingSummary,
            cityName: row.city,
            spotKey: row.spot_key,
            category: row.category,
            latitude: row.latitude,
            longitude: row.longitude
        )
        if let completed = completionsMap[row.id], !completed.isEmpty {
            sum.completedBy = completed
        }
        return sum
    }

    func experience(
        from row: DBExperienceRow,
        creators: [UUID: DBProfileSummary] = [:]
    ) -> Experience {
        let stops = Self.parseStops(row.stops)
        let imageURLs = (row.image?.values ?? []).compactMap { URL(string: $0) }
        return Experience(
            id: row.id,
            kind: row.resolvedKind,
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
            rating: row.rating,
            ratingSummary: row.ratingSummary,
            spotKey: row.spot_key,
            category: row.category,
            cityName: row.city
        )
    }

    private func experience(from place: DBPlace, id: UUID) async throws -> Experience {
        let recCreator = ExperienceInsert.travCreator

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
            kind: .inferred(stopCount: stops.count),
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
            routeSegments: [],
            spotKey: SpotIdentity.key(
                placeID: place.id,
                name: place.name,
                latitude: place.latitude,
                longitude: place.longitude
            ),
            category: place.basic_category,
            cityName: cityName
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
        nil
    }

    static func emojiForCategory(_ category: String?) -> String {
        guard let category else { return "📍" }
        if let spotCategory = SpotCategory(legacyRawValue: category) {
            return spotCategory.emoji
        }
        let emojis: [String: String] = [
            "bar": "🍻",
            "shopping": "🛍️",
            "vintage_store": "🧥",
            "hiking_trail": "🥾",
            "park": "🌳",
            "scenic_viewpoint": "🌅",
            "museum": "🖼️",
            "bookstore": "📚",
            "cafe": "☕",
            "restaurant": "🍽️",
            "nightlife": "🍸",
            "zoo": "🦁",
            "spa": "🧘"
        ]
        return emojis[category.lowercased()] ?? "📍"
    }
}
