# Trav — iOS Architecture

Native SwiftUI iOS app (iOS 17+, Swift 6) for discovering, sharing, and recreating
real-world travel experiences. Backend: Supabase (Postgres + Auth + Storage + Realtime).

## Layout

```
Trav/
├── App/                  # TravApp, AppEnvironment, RootCoordinator
├── Core/
│   ├── Models/
│   ├── Navigation/       # AppRouter, EngagementStore, NotificationStore
│   ├── Repositories/     # Protocols + Supabase / Mock implementations
│   ├── Services/         # SupabaseManager, CityCatalog, Push, ImageCache, NetworkMonitor
│   └── Mock/
├── DesignSystem/
├── Features/             # Globe, City, Feed, Experience, Create, Profile, Rankings, Onboarding, Notifications
└── Resources/
```

## Data flow

View → ViewModel / Store → Repository protocol → Supabase (or Mock).

`AppEnvironment.live` wires repositories based on whether `SUPABASE_URL` + anon key
are present. Cities use `SupabaseCityRepository` in production.

## Auth

Session restored via Supabase auth state stream. `SessionStore.phase` starts at
`.loading`, then `.unauthenticated` / `.onboarding` / `.authenticated`.
OAuth uses `ASWebAuthenticationSession` + `trav://auth-callback`.

## Deep links

`trav://experience/{id}`, `trav://profile/{username}`, `trav://city/{id}`,
`trav://notifications` — handled in `TravApp.onOpenURL` and `AppRouter`.

## Push

APNs token registration → `device_tokens` table → Edge Function
`supabase/functions/push-on-notification` (database webhook on notification insert).

## Security

- iOS app uses **anon** key only (never service_role). See `docs/SECRETS_ROTATION.md`.
- RLS on all user-facing tables; schema in `docs/DATABASE_SCHEMA.md` / migrations.

## Testing / CI

- Unit tests live in `TravTests/` (link the target in Xcode if not already).
- GitHub Actions: `.github/workflows/ci.yml` builds the iOS scheme.
