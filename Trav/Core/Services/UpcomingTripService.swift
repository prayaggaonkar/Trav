import Foundation
import CoreLocation
import Observation
import Supabase

@MainActor
@Observable
final class UpcomingTripService {
    static let shared = UpcomingTripService()

    private(set) var trips: [UpcomingTrip] = []
    private(set) var isLoading: Bool = false

    private init() {
        self.trips = []
    }

    /// Fetches upcoming trips from Supabase
    func fetchTrips(using environment: AppEnvironment? = nil) async {
        isLoading = true
        defer { isLoading = false }

        guard let client = SupabaseManager.client else { return }

        do {
            struct DBTrip: Codable {
                let id: UUID
                let user_id: UUID
                let destination_name: String
                let destination_city: String?
                let latitude: Double
                let longitude: Double
                let start_date: Date
                let end_date: Date?
                let note: String?
                let created_at: Date
            }

            struct DBRec: Codable {
                let id: UUID
                let trip_id: UUID
                let user_id: UUID
                let spot_name: String
                let spot_category: String?
                let latitude: Double
                let longitude: Double
                let image_url: String?
                let upvote_count: Int
                let created_at: Date
            }

            struct DBProfile: Codable {
                let id: UUID
                let username: String
                let display_name: String
                let avatar_url: String?
            }

            let dbProfiles: [DBProfile] = (try? await client
                .from("profiles")
                .select()
                .execute()
                .value) ?? []

            let profilesDict = Dictionary(uniqueKeysWithValues: dbProfiles.map {
                ($0.id, ProfileSummary(
                    id: $0.id,
                    username: $0.username,
                    displayName: $0.display_name,
                    avatarURL: $0.avatar_url != nil ? URL(string: $0.avatar_url!) : nil,
                    isVerified: false
                ))
            })

            let dbTrips: [DBTrip] = try await client
                .from("upcoming_trips")
                .select()
                .order("start_date", ascending: true)
                .execute()
                .value

            let dbRecs: [DBRec] = try await client
                .from("trip_recommendations")
                .select()
                .execute()
                .value

            let now = Date()
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)

            var fetched: [UpcomingTrip] = []
            var expiredTripIDs: [UUID] = []

            for dt in dbTrips {
                let effectiveEnd = dt.end_date ?? dt.start_date
                let endDay = calendar.startOfDay(for: effectiveEnd)

                if endDay < today {
                    expiredTripIDs.append(dt.id)
                    continue
                }

                let author = profilesDict[dt.user_id] ?? ProfileSummary(id: dt.user_id, username: "member", displayName: "Member", avatarURL: nil, isVerified: false)

                let recsForTrip = dbRecs.filter { $0.trip_id == dt.id }.map { dr in
                    let recUser = profilesDict[dr.user_id] ?? ProfileSummary(id: dr.user_id, username: "member", displayName: "Member", avatarURL: nil, isVerified: false)
                    return TripRecommendation(
                        id: dr.id,
                        tripID: dr.trip_id,
                        user: recUser,
                        spotName: dr.spot_name,
                        spotCategory: dr.spot_category,
                        latitude: dr.latitude,
                        longitude: dr.longitude,
                        imageURL: dr.image_url != nil ? URL(string: dr.image_url!) : nil,
                        upvoteCount: dr.upvote_count,
                        createdAt: dr.created_at
                    )
                }

                let isDayTrip = dt.end_date == nil || calendar.isDate(dt.start_date, inSameDayAs: dt.end_date ?? dt.start_date)

                let trip = UpcomingTrip(
                    id: dt.id,
                    user: author,
                    destinationName: dt.destination_name,
                    destinationCity: dt.destination_city,
                    latitude: dt.latitude,
                    longitude: dt.longitude,
                    startDate: dt.start_date,
                    endDate: dt.end_date,
                    note: dt.note,
                    tripType: isDayTrip ? .dayTrip : .upcomingTrip,
                    createdAt: dt.created_at,
                    recommendations: recsForTrip
                )
                fetched.append(trip)
            }

            self.trips = fetched

            // Clean up expired trips from Supabase database
            if !expiredTripIDs.isEmpty {
                Task {
                    for expiredID in expiredTripIDs {
                        let idStr = expiredID.uuidString.lowercased()
                        _ = try? await client.from("trip_recommendations").delete().eq("trip_id", value: idStr).execute()
                        _ = try? await client.from("upcoming_trips").delete().eq("id", value: idStr).execute()
                    }
                }
            }
        } catch {
            print("Error fetching upcoming trips from Supabase: \(error)")
        }
    }

    /// Creates a new upcoming trip or day trip in Supabase
    func createTrip(
        destinationName: String,
        latitude: Double,
        longitude: Double,
        startDate: Date,
        endDate: Date?,
        note: String?,
        tripType: TripType,
        currentUser: Profile?
    ) async -> UpcomingTrip? {
        guard let currentUser = currentUser else { return nil }

        let newTripID = UUID()
        let authorSummary = ProfileSummary(
            id: currentUser.id,
            username: currentUser.username,
            displayName: currentUser.displayName,
            avatarURL: currentUser.avatarURL,
            isVerified: currentUser.isVerified
        )

        let newTrip = UpcomingTrip(
            id: newTripID,
            user: authorSummary,
            destinationName: destinationName,
            destinationCity: destinationName.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: latitude,
            longitude: longitude,
            startDate: startDate,
            endDate: endDate,
            note: note,
            tripType: tripType,
            createdAt: Date(),
            recommendations: []
        )

        trips.insert(newTrip, at: 0)

        if let client = SupabaseManager.client {
            struct InsertTrip: Encodable {
                let id: UUID
                let user_id: UUID
                let destination_name: String
                let destination_city: String?
                let latitude: Double
                let longitude: Double
                let start_date: String
                let end_date: String?
                let note: String?
            }

            let formatter = ISO8601DateFormatter()
            let insertData = InsertTrip(
                id: newTripID,
                user_id: currentUser.id,
                destination_name: destinationName,
                destination_city: newTrip.destinationCity,
                latitude: latitude,
                longitude: longitude,
                start_date: formatter.string(from: startDate),
                end_date: endDate != nil ? formatter.string(from: endDate!) : nil,
                note: note
            )

            do {
                try await client.from("upcoming_trips").insert(insertData).execute()
            } catch {
                print("Error inserting trip into Supabase: \(error)")
            }
        }

        return newTrip
    }

    /// Adds a place recommendation to an upcoming trip
    func addRecommendation(
        tripID: UUID,
        spotName: String,
        spotCategory: String?,
        latitude: Double,
        longitude: Double,
        imageURL: URL?,
        currentUser: Profile?
    ) async {
        guard let currentUser = currentUser else { return }

        let newRecID = UUID()
        let recommender = ProfileSummary(
            id: currentUser.id,
            username: currentUser.username,
            displayName: currentUser.displayName,
            avatarURL: currentUser.avatarURL,
            isVerified: currentUser.isVerified
        )

        let rec = TripRecommendation(
            id: newRecID,
            tripID: tripID,
            user: recommender,
            spotName: spotName,
            spotCategory: spotCategory,
            latitude: latitude,
            longitude: longitude,
            imageURL: imageURL,
            upvoteCount: 0,
            createdAt: Date()
        )

        if let index = trips.firstIndex(where: { $0.id == tripID }) {
            trips[index].recommendations.insert(rec, at: 0)
        }

        if let client = SupabaseManager.client {
            struct InsertRec: Encodable {
                let id: UUID
                let trip_id: UUID
                let user_id: UUID
                let spot_name: String
                let spot_category: String?
                let latitude: Double
                let longitude: Double
                let image_url: String?
                let upvote_count: Int
            }

            let insertData = InsertRec(
                id: newRecID,
                trip_id: tripID,
                user_id: currentUser.id,
                spot_name: spotName,
                spot_category: spotCategory,
                latitude: latitude,
                longitude: longitude,
                image_url: imageURL?.absoluteString,
                upvote_count: 0
            )

            do {
                try await client.from("trip_recommendations").insert(insertData).execute()
            } catch {
                print("Error inserting recommendation into Supabase: \(error)")
            }
        }

        // Send In-App Notification to Trip Creator
        if let targetTrip = trips.first(where: { $0.id == tripID }) {
            let notification = AppNotification(
                id: UUID(),
                userID: targetTrip.user.id,
                actor: recommender,
                type: .tripRecommendation,
                referenceID: tripID,
                isRead: false,
                createdAt: Date(),
                experienceTitle: targetTrip.destinationCity ?? targetTrip.destinationName
            )

            if let client = SupabaseManager.client, targetTrip.user.id != recommender.id {
                struct InsertNotif: Encodable {
                    let id: UUID
                    let user_id: UUID
                    let actor_id: UUID
                    let type: String
                    let reference_id: UUID?
                    let experience_title: String?
                }
                let notifData = InsertNotif(
                    id: notification.id,
                    user_id: targetTrip.user.id,
                    actor_id: recommender.id,
                    type: "trip_recommendation",
                    reference_id: tripID,
                    experience_title: targetTrip.destinationCity ?? targetTrip.destinationName
                )
                _ = try? await client.from("app_notifications").insert(notifData).execute()
            }
        }
    }

    /// Upvotes a spot recommendation
    @MainActor
    func toggleUpvote(tripID: UUID, recommendationID: UUID) {
        if let tripIndex = trips.firstIndex(where: { $0.id == tripID }),
           let recIndex = trips[tripIndex].recommendations.firstIndex(where: { $0.id == recommendationID }) {
            trips[tripIndex].recommendations[recIndex].upvoteCount += 1
            let updatedCount = trips[tripIndex].recommendations[recIndex].upvoteCount

            if let client = SupabaseManager.client {
                Task {
                    struct UpvotePatch: Encodable {
                        let upvote_count: Int
                    }
                    _ = try? await client
                        .from("trip_recommendations")
                        .update(UpvotePatch(upvote_count: updatedCount))
                        .eq("id", value: recommendationID.uuidString.lowercased())
                        .execute()
                }
            }
        }
    }
}
