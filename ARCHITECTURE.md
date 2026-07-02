# Trav — iOS Architecture

Native-first iOS application for discovering, sharing, and recreating real-world experiences. This document defines the complete system architecture before feature implementation.

---

## 1. Principles

| Principle | Implementation |
|-----------|----------------|
| Native-first | SwiftUI +OpenURL, MapKit, SceneKit — no WebView product surfaces |
| Clean boundaries | Features depend on Core protocols, not concrete backends |
| Type safety | Swift 6 strict concurrency, Sendable models, typed navigation |
| Ship-quality UI | Design system tokens, loading/empty/error states on every screen |
| Offline-aware | Cached reads, optimistic writes, sync on reconnect |
| Tested | `@Observable` view models, `@MainActor` UI, async/await networking |

---

## 2. Repository Layout

```
Trav/
├── ARCHITECTURE.md
├── README.md
├── docs/
│   ├── DATABASE_SCHEMA.md
│   └── DESIGN_SYSTEM.md
├── Trav/                          # Main app target
│   ├── App/
│   │   ├── TravApp.swift
│   │   ├── AppEnvironment.swift
│   │   └── RootCoordinator.swift
│   ├── Core/
│   │   ├── Models/
│   │   ├── Navigation/
│   │   ├── Repositories/          # Protocol definitions
│   │   ├── Services/
│   │   └── Mock/                    # Preview & dev data
│   ├── DesignSystem/
│   │   ├── Theme/
│   │   ├── Typography/
│   │   ├── Components/
│   │   └── Animations/
│   ├── Features/
│   │   ├── Globe/
│   │   ├── City/
│   │   ├── Experience/
│   │   ├── Auth/
│   │   ├── Onboarding/
│   │   ├── Profile/
│   │   ├── CreateExperience/
│   │   └── Social/
│   └── Resources/
│       ├── Assets.xcassets
│       ├── Textures/                # Earth, stars, city lights
│       └── Localizable.xcstrings
├── Trav.xcodeproj
└── TravTests/
```

Future extraction into SPM packages (`TravCore`, `TravUI`) when the module graph stabilizes.

---

## 3. Navigation Hierarchy

```
RootCoordinator
├── Unauthenticated
│   ├──();
│       ├── GlobeLanding (always visible behind auth sheet)
│       ├── AuthSheet
│       │   ├── SignIn
│       │   ├── SignUp
│       │   ├── ForgotPassword
│       │   ├── VerifyEmail
│       │   └── TwoFactor
│       └── Onboarding (post sign-up)
│           ├── Name & Username
│           ├── Profile Photo
│           ├── Bio
│           └── Home City (optional)
│
└── Authenticated
    └── MainTabView (minimal — globe remains primary)
        ├── Explore (Globe → City → Experience)
        ├── Create (Experience creation flow)
        ├── Activity (notifications, completions feed)
        └── Profile (self + other users)
```

### Deep linking

| Route | Screen |
|-------|--------|
| `trav://city/{slug}` | City page |
| `trav://experience/{id}` | Experience detail |
| `trav://user/{username}` | Public profile |
| `trav://auth/reset?token=` | Password reset |
| `trav://auth/verify?token=` | Email verification |

Navigation uses a typed `NavigationPath` with `TravRoute` enum. Modals (auth, create flow) use `@Observable AppRouter`.

---

## 4. Feature Modules

Each feature follows **View → ViewModel → Repository → Service**:

```
Features/Globe/
├── Views/
│   ├── GlobeLandingView.swift
│   └── GlobeSceneView.swift       # SceneKit wrapper
├── ViewModels/
│   └── GlobeViewModel.swift
└── GlobeCityMarker.swift
```

| Feature | Responsibility |
|---------|----------------|
| **Globe** | 3D Earth, city markers, zoom-to-city |
| **City** | Hero, stats, featured experience, Pinterest feed |
| **Experience** | Full experience detail: map, timeline, social |
| **Auth** | Sign in/up, Google, verify, reset, 2FA |
| **Onboarding** | Profile setup after registration |
| **Profile** | Public profile, edit, followers |
| **CreateExperience** | 8-step guided creation flow |
| **Social** | Comments, likes, saves, completions, share |

---

## 5. State Management

### App-level

- `AppEnvironment` — dependency container (repositories, services, router)
- `SessionStore` — auth state, current user (`@Observable`, `@MainActor`)
- `AppRouter` — global navigation, sheets, deep links

### Feature-level

- `@Observable` ViewModels per screen
- Unidirectional flow: View → intent → ViewModel → Repository → state update
- No third-party state library; Swift Observation + async sequences

### Caching

- `ImageCache` — URLCache + in-memory for thumbnails
- `ExperienceCache` — disk-backed JSON for recently viewed experiences
- `CityCache` — city metadata and feed pages

---

## 6. Backend Integration

**Primary backend: Supabase** (PostgreSQL + Auth + Storage + Realtime)

| Capability | Supabase feature |
|------------|------------------|
| Email/password auth | Auth |
| Google Sign In | Auth OAuth |
| Email verification | Auth hooks + email templates |
| Password reset | Auth recovery |
| 2FA | Auth MFA (TOTP) |
| Relational data | PostgreSQL with RLS |
| Media | Storage buckets (`avatars`, `experiences`, `completions`) |
| Realtime comments | Realtime subscriptions |

### Repository pattern

```swift
protocol ExperienceRepository: Sendable {
    func fetchExperience(id: UUID) async throws -> Experience
    func fetchCityFeed(cityID: UUID, page: Int) async throws -> Paginated<ExperienceSummary>
    func createExperience(_ draft: ExperienceDraft) async throws -> Experience
    // ...
}
```

Implementations:

- `SupabaseExperienceRepository` — production
- `MockExperienceRepository` — previews, offline dev, tests

Environment flag `AppConfiguration.useMockBackend` toggles at launch.

---

## 7. Authentication Flow

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│ Sign Up     │────▶│ Verify Email │────▶│ Onboarding      │
└─────────────┘     └──────────────┘     └─────────────────┘
       │
       ▼
┌─────────────┐     ┌──────────────┐
│ Sign In     │────▶│ 2FA (if on)  │────▶ Main app
└─────────────┘     └──────────────┘

Google Sign In ──▶ (new user?) Onboarding : Main app
Forgot Password ──▶ Email link ──▶ Reset screen (deep link)
```

Session persisted in Keychain via `KeychainSessionStore`. Token refresh handled by Supabase client middleware.

---

## 8. Key Services

| Service | Role |
|---------|------|
| `AuthService` | Sign in/up, OAuth, MFA, session |
| `GeocodingService` | MapKit local search for stop creation |
| `RoutingService` | MapKit directions between stops |
| `MediaUploadService` | Compress, upload, progress |
| `ShareService` | UIActivityViewController + deep links |
| `GlobeTimeService` | UTC sun position for day/night shader |
| `HapticService` | Centralized haptic feedback |
| `AnalyticsService` | Event tracking (protocol, no-op default) |

---

## 9. 3D Globe Architecture

```
GlobeSceneView (UIViewRepresentable)
└── GlobeSceneController
    ├── SCNScene
    │   ├── earthNode (SCNSphere + custom shader)
    │   ├── atmosphereNode (shell + fresnel)
    │   ├── starFieldNode (particle system)
    │   └── cityMarkerNodes[]
    ├── GlobeGestureHandler (pan, pinch, tap)
    └── GlobeCameraController (orbit, fly-to-city)
```

**Day/night**: Fragment shader blends day texture, night texture (city lights), and specular based on sun vector from UTC.

**City markers**: Billboarding glow sprites; tap ray-casts to nearest marker within threshold.

**Performance**: 60fps target; reduce star count on older devices; texture mipmaps.

---

## 10. Experience Creation Flow

| Step | Screen | Data |
|------|--------|------|
| 1 | Cover image | `UIImage`, crop |
| 2 | Title & description | Text |
| 3 | City picker | `City` |
| 4 | Add stops | Map search → `StopDraft[]` |
| 5 | Reorder | Drag list |
| 6 | Stop details | Media, notes, duration per stop |
| 7 | Route generation | Auto via `RoutingService` |
| 8 | Review & publish | Validation → API |

Draft persisted locally in `ExperienceDraftStore` (UserDefaults + file storage for media) so users can resume.

---

## 11. Error, Loading & Empty States

Every list/detail screen implements:

- **Loading**: Skeleton placeholders matching final layout (shimmer)
- **Empty**: Illustration + contextual CTA
- **Error**: Message + retry button; non-blocking toasts for transient failures

`AsyncContentView<Content, Data>` reusable wrapper.

---

## 12. Testing Strategy

| Layer | Approach |
|-------|----------|
| Models | Unit tests — Codable, validation |
| ViewModels | Unit tests with mock repositories |
| Repositories | Integration tests against Supabase local |
| UI | Snapshot tests for design system components |
| Globe | Performance tests — frame rate, memory |

---

## 13. Implementation Phases

| Phase | Deliverable |
|-------|-------------|
| **1** ✅ | Architecture docs, project scaffold, design system |
| **2** | Globe landing (3D Earth, gestures, city tap) |
| **3** | City page + experience cards + route preview |
| **4** | Experience detail (map, timeline, stats) |
| **5** | Auth + onboarding |
| **6** | Profile + social interactions |
| **7** | Experience creation flow |
| **8** | Supabase integration + polish pass |

Each phase ships a production-ready, reviewable vertical slice before the next begins.

---

## 14. Security

- Row Level Security on all Supabase tables
- Keychain for tokens; never UserDefaults for secrets
- Certificate pinning (optional, phase 8)
- Input validation client + server
- Media upload size limits and type checks

---

## 15. Configuration

`Config.xcconfig` / `Secrets.xcconfig` (gitignored):

```
SUPABASE_URL =
SUPABASE_ANON_KEY =
GOOGLE_CLIENT_ID =
```

`AppConfiguration` reads from Info.plist injected at build time.
