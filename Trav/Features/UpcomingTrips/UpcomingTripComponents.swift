import SwiftUI
import MapKit

// MARK: - Top Input Bar (Facebook-Style Post Trigger)

/// Sleek Facebook-style post creation bar positioned above "Happening Soon".
struct UpcomingTripHeaderInputBar: View {
    var onPostTrip: (TripType) -> Void
    @Environment(AppEnvironment.self) private var environment

    private var userAvatarURL: URL? {
        environment.session.currentUser?.avatarURL
    }

    var body: some View {
        VStack(spacing: 10) {
            // Main Input Pill with Profile Picture
            Button {
                onPostTrip(.upcomingTrip)
            } label: {
                HStack(spacing: 12) {
                    AvatarView(url: userAvatarURL, size: 36)

                    Text("Where are you going next?")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(TravColors.muted)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(TravColors.surfaceElevated)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [TravColors.accent.opacity(0.4), TravColors.border.opacity(0.4)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(TravPressButtonStyle(scale: 0.99))

            Divider().background(TravColors.border.opacity(0.3))

            // Quick action pills (no icons, ultra-clean text layout)
            HStack(spacing: TravSpacing.xs) {
                Button {
                    onPostTrip(.upcomingTrip)
                } label: {
                    Text("Upcoming Trip")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(TravColors.accent.opacity(0.12))
                        .foregroundStyle(TravColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.97))

                Button {
                    onPostTrip(.dayTrip)
                } label: {
                    Text("Day Trip")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.97))
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: TravRadius.xl, style: .continuous)
                .fill(TravColors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: TravRadius.xl, style: .continuous)
                        .stroke(TravColors.accent.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Upcoming Trip Feed Card

/// Facebook-style post card displaying an upcoming trip or day trip in the Feed.
struct UpcomingTripCard: View {
    let trip: UpcomingTrip
    var onRecommend: () -> Void
    var onTap: () -> Void
    @Environment(AppEnvironment.self) private var environment

    private var isOwnTrip: Bool {
        guard let currentUserId = environment.session.currentUser?.id else { return false }
        return trip.user.id == currentUserId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            // Header: User avatar + name + trip type badge
            HStack(spacing: 10) {
                AvatarView(url: trip.user.avatarURL, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(trip.user.displayName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(TravColors.primary)

                        Text("is planning a")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(TravColors.muted)
                    }

                    Text(trip.dateRangeLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(trip.tripType == .dayTrip ? Color.blue : TravColors.accent)
                }

                Spacer()

                Text(trip.tripType.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(trip.tripType == .dayTrip ? Color.blue.opacity(0.15) : TravColors.accent.opacity(0.15))
                    .foregroundStyle(trip.tripType == .dayTrip ? Color.blue : TravColors.accent)
                    .clipShape(Capsule())
            }

            // Destination Title Banner (No icons)
            VStack(alignment: .leading, spacing: 6) {
                Text(trip.destinationName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(TravColors.primary)

                // Category Tag Pills
                if !trip.categoryTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(trip.categoryTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(TravColors.accent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(TravColors.accent.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }

            // Recommendations Preview Row
            if !trip.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RECOMMENDED SPOTS (\(trip.recommendations.count))")
                        .font(TravTypography.overline())
                        .foregroundStyle(TravColors.muted)
                        .tracking(1.5)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(trip.recommendations.prefix(4)) { rec in
                                HStack(spacing: 6) {
                                    AvatarView(url: rec.user.avatarURL, size: 18)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(rec.spotName)
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundStyle(TravColors.primary)
                                            .lineLimit(1)
                                        if let cat = rec.spotCategory {
                                            Text(cat)
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundStyle(TravColors.muted)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(TravColors.surface)
                                .clipShape(RoundedRectangle(cornerRadius: TravRadius.sm))
                                .overlay(
                                    RoundedRectangle(cornerRadius: TravRadius.sm)
                                        .stroke(TravColors.border.opacity(0.4), lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }

            Divider()
                .background(TravColors.border.opacity(0.4))

            // Action Row: Recommend a Spot + Recommendation Count
            HStack {
                if !isOwnTrip {
                    Button(action: onRecommend) {
                        Text("Recommend a Spot")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(TravColors.accent)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(TravPressButtonStyle(scale: 0.96))
                } else {
                    Text("Your Post")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(TravColors.muted)
                }

                Spacer()

                Text("\(trip.recommendationCount) recs")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(TravColors.muted)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: TravRadius.xl, style: .continuous)
                .fill(TravColors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: TravRadius.xl, style: .continuous)
                        .stroke(TravColors.border.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Create Upcoming Trip Sheet (Tag Selector & Clean Controls)

/// Sheet for creating an upcoming trip or day trip with city-only autocomplete and clean date pickers.
struct CreateUpcomingTripSheet: View {
    var initialTripType: TripType = .upcomingTrip
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment

    @State private var selectedTripType: TripType = .upcomingTrip
    @State private var query: String = ""
    @State private var selectedLocation: (name: String, lat: Double, lng: Double)? = nil
    @State private var searchResults: [MKMapItem] = []
    @State private var startDate: Date = Date().addingTimeInterval(86400 * 7)
    @State private var endDate: Date = Date().addingTimeInterval(86400 * 14)
    @State private var hasEndDate: Bool = true
    @State private var selectedTags: Set<String> = []

    init(initialTripType: TripType = .upcomingTrip) {
        self.initialTripType = initialTripType
        _selectedTripType = State(initialValue: initialTripType)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TravSpacing.lg) {
                    // Step 1: Trip Type Selector
                    VStack(alignment: .leading, spacing: TravSpacing.xs) {
                        Text("TRIP TYPE")
                            .font(TravTypography.overline())
                            .foregroundStyle(TravColors.muted)

                        Picker("Trip Type", selection: $selectedTripType) {
                            ForEach(TripType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Step 2: Destination Autocomplete Field (Cities, States, Countries Only)
                    VStack(alignment: .leading, spacing: TravSpacing.xs) {
                        Text("DESTINATION (CITY, STATE, OR COUNTRY)")
                            .font(TravTypography.overline())
                            .foregroundStyle(TravColors.muted)

                        HStack(spacing: 8) {
                            TextField(selectedTripType == .dayTrip ? "Search destination city or region..." : "Search city, state or country...", text: $query)
                                .font(TravTypography.bodyMedium())
                                .foregroundStyle(TravColors.primary)
                                .onChange(of: query) { _, newValue in
                                    performAutocomplete(newValue)
                                }

                            if !query.isEmpty {
                                Button("Clear") {
                                    query = ""
                                    selectedLocation = nil
                                    searchResults = []
                                }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(TravColors.muted)
                            }
                        }
                        .padding(12)
                        .background(TravColors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: TravRadius.md)
                                .stroke(selectedLocation != nil ? TravColors.accent : TravColors.border, lineWidth: 1)
                        )

                        // Autocomplete Search Results
                        if !searchResults.isEmpty && selectedLocation == nil {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(searchResults.prefix(5), id: \.self) { item in
                                    Button {
                                        let name = item.name ?? item.placemark.title ?? query
                                        let fullLabel = item.placemark.title ?? name
                                        let coord = item.placemark.coordinate
                                        self.selectedLocation = (fullLabel, coord.latitude, coord.longitude)
                                        self.query = fullLabel
                                        self.searchResults = []
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name ?? "City / Region")
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundStyle(TravColors.primary)
                                            if let subtitle = item.placemark.title {
                                                Text(subtitle)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(TravColors.muted)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.plain)
                                    Divider().background(TravColors.border.opacity(0.3))
                                }
                            }
                            .background(TravColors.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: TravRadius.md)
                                    .stroke(TravColors.border, lineWidth: 1)
                            )
                        } else if let loc = selectedLocation {
                            Text("Selected: \(loc.name)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.green)
                                .padding(.top, 2)
                        }
                    }

                    // Step 3: Date Selection (Clean Trav Vibe UI)
                    VStack(alignment: .leading, spacing: TravSpacing.xs) {
                        Text(selectedTripType == .dayTrip ? "DAY TRIP DATE" : "TRIP DATES")
                            .font(TravTypography.overline())
                            .foregroundStyle(TravColors.muted)

                        VStack(spacing: 10) {
                            if selectedTripType == .dayTrip {
                                HStack {
                                    Text("Date")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(TravColors.primary)
                                    Spacer()
                                    DatePicker("", selection: $startDate, displayedComponents: .date)
                                        .labelsHidden()
                                        .tint(TravColors.accent)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(TravColors.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                                .overlay(
                                    RoundedRectangle(cornerRadius: TravRadius.md)
                                        .stroke(TravColors.border, lineWidth: 1)
                                )
                            } else {
                                HStack {
                                    Text("Start Date")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(TravColors.primary)
                                    Spacer()
                                    DatePicker("", selection: $startDate, displayedComponents: .date)
                                        .labelsHidden()
                                        .tint(TravColors.accent)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(TravColors.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                                .overlay(
                                    RoundedRectangle(cornerRadius: TravRadius.md)
                                        .stroke(TravColors.border, lineWidth: 1)
                                )

                                HStack {
                                    Text("End Date")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(TravColors.primary)
                                    Spacer()
                                    DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                                        .labelsHidden()
                                        .tint(TravColors.accent)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(TravColors.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                                .overlay(
                                    RoundedRectangle(cornerRadius: TravRadius.md)
                                        .stroke(TravColors.border, lineWidth: 1)
                                )
                            }
                        }
                    }

                    // Step 4: Category Tag Selection (No Freeform Text)
                    VStack(alignment: .leading, spacing: TravSpacing.xs) {
                        Text("WHAT SPOTS ARE YOU LOOKING FOR?")
                            .font(TravTypography.overline())
                            .foregroundStyle(TravColors.muted)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                            ForEach(UpcomingTrip.presetRecommendationTags, id: \.self) { tag in
                                let isSelected = selectedTags.contains(tag)
                                Button {
                                    if isSelected {
                                        selectedTags.remove(tag)
                                    } else {
                                        selectedTags.insert(tag)
                                    }
                                } label: {
                                    Text(tag)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity)
                                        .background(isSelected ? TravColors.accent : TravColors.surfaceElevated)
                                        .foregroundStyle(isSelected ? .white : TravColors.primary)
                                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: TravRadius.md)
                                                .stroke(isSelected ? TravColors.accent : TravColors.border, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(TravPressButtonStyle(scale: 0.96))
                            }
                        }
                    }

                    Spacer(minLength: 20)

                    // Publish Button
                    Button {
                        publishTrip()
                    } label: {
                        Text(selectedTripType == .dayTrip ? "Publish Day Trip" : "Publish Upcoming Trip")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selectedLocation != nil ? TravColors.accent : Color.gray.opacity(0.4))
                            .foregroundStyle(selectedLocation != nil ? .white : .white.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                    }
                    .disabled(selectedLocation == nil)
                }
                .padding(TravSpacing.lg)
            }
            .travScreenBackground()
            .navigationTitle(selectedTripType == .dayTrip ? "Post Day Trip" : "Post Upcoming Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func performAutocomplete(_ text: String) {
        guard text.count >= 2 else {
            searchResults = []
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.address]
        Task {
            if let response = try? await MKLocalSearch(request: request).start() {
                let filtered = response.mapItems.filter { item in
                    // Filter out stores/POIs so only cities, states, countries & regions remain
                    item.pointOfInterestCategory == nil
                }
                await MainActor.run {
                    self.searchResults = filtered
                }
            }
        }
    }

    private func publishTrip() {
        guard let loc = selectedLocation else { return }
        let tagsFormatted = selectedTags.isEmpty ? nil : selectedTags.sorted().joined(separator: ", ")
        Task {
            _ = await UpcomingTripService.shared.createTrip(
                destinationName: loc.name,
                latitude: loc.lat,
                longitude: loc.lng,
                startDate: startDate,
                endDate: selectedTripType == .dayTrip ? nil : (hasEndDate ? endDate : nil),
                note: tagsFormatted,
                tripType: selectedTripType,
                currentUser: environment.session.currentUser
            )
            dismiss()
        }
    }
}

// MARK: - Trip Detail & Spot Recommendation Sheet (STRICT NO TEXT COMMENTS RULE)

struct TripDetailSheet: View {
    let trip: UpcomingTrip
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment

    @State private var showingSpotPicker: Bool = false

    private var isOwnTrip: Bool {
        guard let currentUserId = environment.session.currentUser?.id else { return false }
        return trip.user.id == currentUserId
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TravSpacing.lg) {
                    // Header Trip Card
                    VStack(alignment: .leading, spacing: TravSpacing.sm) {
                        HStack(spacing: 10) {
                            AvatarView(url: trip.user.avatarURL, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trip.user.displayName)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(TravColors.primary)
                                Text("\(trip.tripType.rawValue) • \(trip.dateRangeLabel)")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(TravColors.accent)
                            }
                            Spacer()
                        }

                        Text(trip.destinationName)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(TravColors.primary)

                        if !trip.categoryTags.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(trip.categoryTags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(TravColors.accent)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(TravColors.accent.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(TravColors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.xl))

                    // Spot Recommendation Banner
                    VStack(alignment: .leading, spacing: TravSpacing.xs) {
                        HStack {
                            Text("RECOMMENDED PLACES (\(trip.recommendations.count))")
                                .font(TravTypography.overline())
                                .foregroundStyle(TravColors.muted)
                                .tracking(1.5)
                            Spacer()
                        }

                        if !isOwnTrip {
                            Button {
                                showingSpotPicker = true
                            } label: {
                                Text("Recommend a Spot from Apple Maps")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .padding(14)
                                    .background(TravColors.accent)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                            }
                            .buttonStyle(TravPressButtonStyle(scale: 0.98))
                        } else {
                            Text("Your Post — Friends can recommend spots for you.")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(TravColors.muted)
                                .padding(.vertical, 4)
                        }

                        Text("Freeform text comments disabled — recommendations are verified Apple Maps spots.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(TravColors.muted)
                            .padding(.top, 2)
                    }

                    // List of Spot Recommendation Comment Cards
                    if trip.recommendations.isEmpty {
                        VStack(spacing: 10) {
                            Text("No spot recommendations yet")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(TravColors.primary)
                            Text("Be the first to recommend a cool spot for this trip!")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(TravColors.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(TravColors.surfaceElevated.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg))
                    } else {
                        VStack(spacing: 12) {
                            ForEach(trip.recommendations) { rec in
                                SpotRecommendationCard(
                                    rec: rec,
                                    onUpvote: {
                                        UpcomingTripService.shared.toggleUpvote(tripID: trip.id, recommendationID: rec.id, currentUser: environment.session.currentUser)
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(TravSpacing.md)
            }
            .travScreenBackground()
            .navigationTitle("Trip Recommendations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingSpotPicker) {
                SpotPickerSheet(trip: trip)
            }
        }
    }
}

// MARK: - Spot Recommendation Comment Card

private struct SpotRecommendationCard: View {
    let rec: TripRecommendation
    var onUpvote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Recommender header
            HStack(spacing: 8) {
                AvatarView(url: rec.user.avatarURL, size: 24)
                Text("\(rec.user.displayName) recommended")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(TravColors.primary)
                Spacer()
                Button(action: onUpvote) {
                    HStack(spacing: 4) {
                        Image(systemName: rec.isLikedByCurrentUser ? "heart.fill" : "heart")
                            .font(.system(size: 11, weight: .bold))
                        Text("\(rec.upvoteCount)")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(rec.isLikedByCurrentUser ? Color.red.opacity(0.15) : TravColors.surfaceElevated)
                    .foregroundStyle(rec.isLikedByCurrentUser ? Color.red : TravColors.muted)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // Spot media & title
            HStack(spacing: 12) {
                ExperienceStopsMapView(
                    experience: ExperienceSummary(
                        id: rec.id,
                        kind: .spot,
                        cityID: UUID(),
                        title: rec.spotName,
                        imageURLs: rec.imageURL != nil ? [rec.imageURL!] : [],
                        creator: ExperienceInsert.travCreator,
                        durationMinutes: 45,
                        costLevel: .moderate,
                        stops: [],
                        spotKey: nil,
                        category: rec.spotCategory,
                        latitude: rec.latitude,
                        longitude: rec.longitude
                    ),
                    width: 76,
                    height: 76
                )
                .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))

                VStack(alignment: .leading, spacing: 4) {
                    Text(rec.spotName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(TravColors.primary)
                        .lineLimit(1)

                    if let cat = rec.spotCategory {
                        Text(cat)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(TravColors.muted)
                            .lineLimit(1)
                    }

                    Text("Verified Apple Maps Place")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(TravColors.muted)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(TravColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: TravRadius.lg)
                .stroke(TravColors.border.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Apple Maps Spot Picker Sheet for Recommendations

private struct SpotPickerSheet: View {
    let trip: UpcomingTrip
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment

    @State private var query: String = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching: Bool = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // Search Input Header
                HStack(spacing: 8) {
                    TextField("Search spots in \(trip.destinationCity ?? trip.destinationName)...", text: $query)
                        .font(TravTypography.bodyMedium())
                        .onChange(of: query) { _, newValue in
                            searchSpotsInCity(newValue)
                        }
                    if !query.isEmpty {
                        Button("Clear") {
                            query = ""
                            searchResults = []
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TravColors.muted)
                    }
                }
                .padding(12)
                .background(TravColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: TravRadius.md)
                        .stroke(TravColors.border, lineWidth: 1)
                )
                .padding(TravSpacing.md)

                // Results list
                if isSearching {
                    Spacer()
                    ProgressView("Searching Apple Maps...")
                        .tint(TravColors.accent)
                    Spacer()
                } else if searchResults.isEmpty && !query.isEmpty {
                    Spacer()
                    Text("No places found for \"\(query)\"")
                        .font(TravTypography.bodyMedium())
                        .foregroundStyle(TravColors.muted)
                    Spacer()
                } else if searchResults.isEmpty {
                    VStack(spacing: 8) {
                        Text("Search for a spot to recommend")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("Search any cafe, bar, museum, hike, venue or attraction in \(trip.destinationCity ?? trip.destinationName).")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(TravColors.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(searchResults, id: \.self) { item in
                        Button {
                            recommendSpot(item)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Place")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(TravColors.primary)

                                    if let subtitle = item.placemark.title {
                                        Text(subtitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(TravColors.muted)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Text("Recommend")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(TravColors.accent)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .travScreenBackground()
            .navigationTitle("Recommend a Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func searchSpotsInCity(_ text: String) {
        guard text.count >= 2 else {
            searchResults = []
            return
        }

        let searchQuery = "\(text) in \(trip.destinationCity ?? trip.destinationName)"
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchQuery
        if trip.latitude != 0 && trip.longitude != 0 {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: trip.latitude, longitude: trip.longitude),
                latitudinalMeters: 60000,
                longitudinalMeters: 60000
            )
        }

        isSearching = true
        Task {
            if let response = try? await MKLocalSearch(request: request).start() {
                await MainActor.run {
                    self.searchResults = response.mapItems
                    self.isSearching = false
                }
            } else {
                await MainActor.run { self.isSearching = false }
            }
        }
    }

    private func recommendSpot(_ item: MKMapItem) {
        let name = item.name ?? "Recommended Spot"
        let category = item.pointOfInterestCategory?.rawValue.capitalized ?? "Place"
        let coord = item.placemark.coordinate

        Task {
            await UpcomingTripService.shared.addRecommendation(
                tripID: trip.id,
                spotName: name,
                spotCategory: category,
                latitude: coord.latitude,
                longitude: coord.longitude,
                imageURL: nil,
                currentUser: environment.session.currentUser
            )
            dismiss()
        }
    }
}
