# Trav — Database Schema (as migrated)

PostgreSQL schema for Supabase. Source of truth: `supabase/migrations/`.

## Core tables

| Table | Purpose |
|-------|---------|
| `profiles` | Extends `auth.users`; username, vibes, counts |
| `cities` | Globe / city catalog (`is_active`) |
| `experiences` | User itineraries (`city` text + `city_id`, `stops` text[] preview, `image` jsonb, `rating` jsonb, `is_published`) |
| `stops` | Normalized stop rows with lat/lng / `place_id` |
| `places` | Pipeline-curated POIs / itineraries (`id` text, `client_uuid`) |
| `popups` | Scraped local events (service-role insert only) |

## Social

| Table | Purpose |
|-------|---------|
| `follows` | Follower graph (canonical; `followers` migrated away) |
| `experience_saves` | Bookmarks (canonical; `saved_experiences` migrated away) |
| `experience_likes` | Likes + `like_count` trigger |
| `experience_completions` | Watchlist / completed with optional note + photos |
| `comments` | Threaded comments |
| `notifications` | In-app + push fan-out (`follow`, `save`, `like`, `comment`, `new_experience`, `watchlist`) |
| `device_tokens` | APNs tokens |

## Moderation

| Table | Purpose |
|-------|---------|
| `reports` | User reports of experiences / comments / profiles |
| `blocks` | Block graph |
| `reserved_usernames` | Read-only reserved names |

## Storage buckets

| Bucket | Path |
|--------|------|
| `avatars` | `{user_id}/…` |
| `experiences` | `{user_id}/{experience_id}/…` |
| `completions` | `{user_id}/{experience_id}/…` (when used) |

## Security notes

- RLS is enabled on all user-facing tables.
- The iOS app must use the **anon** key only; service role is for the pipeline / Edge Functions.
- `popups` inserts are revoked from `anon` / `authenticated` (pipeline uses service role).
