import SwiftUI

struct CreateExperienceView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SessionStore.self) private var session
    
    @State private var title = ""
    @State private var description = ""
    @State private var selectedCity: City?
    @State private var cities: [City] = []
    @State private var stops: [StopPreview] = []
    @State private var newStopName = ""
    @State private var newStopEmoji = "📍"
    
    @State private var isSubmitting = false
    @State private var showSuccess = false
    
    let emojis = ["📍", "☕", "📚", "🍜", "🌃", "🍕", "🌳", "🏛️", "🍷", "🏖️", "🛍️", "🏨"]
    
    var body: some View {
        NavigationStack {
            ZStack {
                TravColors.surface.ignoresSafeArea()
                
                if showSuccess {
                    successView
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: TravSpacing.lg) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Create Experience")
                                    .font(TravTypography.displayMedium())
                                    .foregroundStyle(TravColors.primary)
                                Text("Map your favorite stops and share them with the world.")
                                    .font(TravTypography.bodyMedium())
                                    .foregroundStyle(TravColors.muted)
                            }
                            .padding(.top, TravSpacing.md)
                            
                            // Section 1: Basic Info
                            VStack(alignment: .leading, spacing: TravSpacing.xs) {
                                Text("Experience Title")
                                    .font(TravTypography.labelMedium())
                                    .foregroundStyle(TravColors.muted)
                                TextField("e.g. SF Coffee & Books Tour", text: $title)
                                    .padding()
                                    .background(TravColors.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                                
                                Text("Description")
                                    .font(TravTypography.labelMedium())
                                    .foregroundStyle(TravColors.muted)
                                    .padding(.top, 4)
                                TextField("What makes this experience special?", text: $description)
                                    .padding()
                                    .background(TravColors.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                            }
                            
                            // Section 2: Choose City
                            VStack(alignment: .leading, spacing: TravSpacing.xs) {
                                Text("Select Destination City")
                                    .font(TravTypography.labelMedium())
                                    .foregroundStyle(TravColors.muted)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: TravSpacing.sm) {
                                        ForEach(cities) { city in
                                            Button {
                                                selectedCity = city
                                            } label: {
                                                Text(city.name)
                                                    .font(TravTypography.labelMedium())
                                                    .foregroundStyle(selectedCity?.id == city.id ? .white : TravColors.primary)
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 10)
                                                    .background(selectedCity?.id == city.id ? TravColors.accent : TravColors.surfaceElevated)
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            
                            // Section 3: Add Stops
                            VStack(alignment: .leading, spacing: TravSpacing.xs) {
                                Text("Stops Along the Way")
                                    .font(TravTypography.labelMedium())
                                    .foregroundStyle(TravColors.muted)
                                
                                if !stops.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(stops) { stop in
                                            HStack {
                                                Text(stop.emoji ?? "📍")
                                                Text(stop.name)
                                                    .font(TravTypography.bodyMedium())
                                                    .foregroundStyle(TravColors.primary)
                                                Spacer()
                                                Button {
                                                    stops.removeAll { $0.id == stop.id }
                                                } label: {
                                                    Image(systemName: "minus.circle.fill")
                                                        .foregroundStyle(.red.opacity(0.8))
                                                }
                                            }
                                            .padding()
                                            .background(TravColors.surfaceElevated)
                                            .clipShape(RoundedRectangle(cornerRadius: TravRadius.sm))
                                        }
                                    }
                                    .padding(.bottom, 8)
                                }
                                
                                HStack(spacing: TravSpacing.xs) {
                                    Menu {
                                        ForEach(emojis, id: \.self) { emoji in
                                            Button(emoji) { newStopEmoji = emoji }
                                        }
                                    } label: {
                                        Text(newStopEmoji)
                                            .font(.title2)
                                            .padding(10)
                                            .background(TravColors.surfaceElevated)
                                            .clipShape(RoundedRectangle(cornerRadius: TravRadius.sm))
                                    }
                                    
                                    TextField("Add a new stop name...", text: $newStopName)
                                        .padding()
                                        .background(TravColors.surfaceElevated)
                                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                                    
                                    Button {
                                        guard !newStopName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                                        let newStop = StopPreview(id: UUID(), name: newStopName, emoji: newStopEmoji)
                                        stops.append(newStop)
                                        newStopName = ""
                                        newStopEmoji = "📍"
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(18)
                                            .background(TravColors.accent)
                                            .clipShape(RoundedRectangle(cornerRadius: TravRadius.sm))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            // Publish Button
                            Button {
                                submit()
                            } label: {
                                if isSubmitting {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Publish Experience")
                                        .font(TravTypography.titleMedium())
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 52)
                                        .background(canPublish ? TravColors.accent : TravColors.muted.opacity(0.4))
                                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                                }
                            }
                            .disabled(!canPublish || isSubmitting)
                            .padding(.top, TravSpacing.md)
                        }
                        .padding(TravSpacing.screenHorizontal)
                        .padding(.bottom, 120)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task {
                do {
                    cities = try await environment.cities.fetchGlobeCities()
                } catch {}
            }
        }
    }
    
    private var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        selectedCity != nil &&
        !stops.isEmpty
    }
    
    private func submit() {
        isSubmitting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isSubmitting = false
            withAnimation(.spring(duration: 0.4)) {
                showSuccess = true
            }
        }
    }
    
    private var successView: some View {
        VStack(spacing: TravSpacing.xl) {
            Spacer()
            
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundStyle(TravColors.success)
                .symbolEffect(.bounce, value: showSuccess)
            
            VStack(spacing: TravSpacing.sm) {
                Text("Experience Published!")
                    .font(TravTypography.displayMedium())
                    .foregroundStyle(TravColors.primary)
                Text("Your itinerary \"\(title)\" is now live on the globe of \(selectedCity?.name ?? "the world")!")
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Button {
                title = ""
                description = ""
                selectedCity = nil
                stops = []
                showSuccess = false
            } label: {
                Text("Create Another")
                    .font(TravTypography.titleMedium())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(TravColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }
}
