# Trav — Database Schema

PostgreSQL schema for Supabase. All tables use UUID primary keys and `timestamptz` for dates.

---

## Enums

```sql
CREATE TYPE cost_level AS ENUM ('free', 'budget', 'moderate', 'premium');
CREATE TYPE transport_mode AS ENUM ('walking', 'driving', 'transit', 'mixed');
CREATE TYPE media_type AS ENUM ('photo', 'video');
CREATE TYPE notification_type AS ENUM (
  'follow', 'save', 'new_experience'
  -- reserved for later: like, comment, completion, mention
);
```

---

## Core Tables

### `cities`

| Column | Type | Notes |
|--------|------|-------|
| id | uuid PK | |
| name | text | Display name |
| slug | text UNIQUE | URL-safe |
| country_code | char(2) | ISO 3166-1 |
| latitude | double precision | Globe marker |
| longitude | double precision | Globe marker |
| hero_image_url | text | CDN URL |
| timezone | text | IANA |
| experience_count | int | Denormalized |
| creator_count | int | Denormalized |
| created_at | timestamptz | |

### `profiles`

Extends `auth.users`.

| Column | Type | Notes |
|--------|------|-------|
| id | uuid PK FK → auth.users | |
| username | text UNIQUE | Lowercase, 3–30 chars |
| display_name | text | |
| bio | text | Max 160 chars |
| avatar_url | text | |
| home_city_id | uuid FK → edited → cities | |
| follower_count | int | Denormalized |
| following_count | int | Denormalized |
| experience_count | int | |
| completion_count | int | |
| is_verified | boolean | Default false |
| created_at | timestamptz | |
| updated_at | timestamptz | |

### `experiences`

| Column | Type | Notes |
|--------|------|-------|
| id | uuid PK | |
| city_id | uuid FK → cities | Exactly one city |
| creator_id | uuid FK → profiles | |
| title | text | |
| description | text | |
| cover_image_url | text | |
| duration_minutes | int | Total estimated |
| cost_level | cost_level | |
| estimated_cost_usd | numeric(8,2) nullable | Optional exact |
| transport_mode | transport_mode | |
| total_distance_meters | int | From routing |
| save_count | int | |
| like_count | int | |
| completion_count | int | Primary engagement metric |
| comment_count | int | |
| is_published | boolean | |
| is_featured | boolean | City page featured |
| published_at | timestamptz nullable | |
| rating | jsonb nullable | Creator radar scores (`{"Cost": 5.5, ...}`) |
| created_at | timestamptz | |
| updated_at | timestamptz | |

### `stops`

Ordered sequence within an experience.

| Column | Type | Notes |
|--------|------|-------|
| id | uuid PK | |
| experience_id | uuid FK → experiences ON DELETE CASCADE | |
| order_index | int | 0-based, unique per experience |
| name | text | |
| description | text | |
| creator_notes | text | Personal tips |
| latitude | double precision | |
| longitude | double precision | |
| place_id | text nullable | MapKit / Google place ID |
| recommended_time | text nullable | e.g. "Late afternoon" |
| duration_minutes | int | At this stop |
| emoji | text nullable | Route preview icon |
| created_at | timestamptz | |

### `stop_media`

| Column | Type | Notes |
|--------|------|-------|
| id | uuid PK | |
| stop_id | uuid FK → stops ON DELETE CASCADE | |
| media_type | media_type | |
| url | text | |
| thumbnail_url | text nullable | Videos |
| order_index | int | Max 2 per stop |
| width | int | |
| height | int | |
| created_at | timestamptz | |

### `route_segments`

Computed path between consecutive stops.

| Column | Type | Notes |
|--------|------|-------|
| id | uuid PK | |
| experience_id | uuid FK → experiences | |
| from_stop_id | uuid FK → stops | |
| to_stop_id | uuid FK → stops | |
| distance_meters | int | |
| duration_seconds | int | |
| polyline | text | Encoded polyline |
| transport_mode | transport_mode | |

---

## Social Tables

### `follows`

| Column | Type |
|--------|------|
| follower_id | uuid FK → profiles |
| following_id | uuid FK → profiles |
| created_at | timestamptz |

PK: `(follower_id, following_id)`

### `experience_saves`

| Column | Type |
|--------|------|
| user_id | uuid FK → profiles |
| experience_id | uuid FK → experiences |
| created_at | timestamptz |

### `experience_likes`

Same shape as saves.

### `experience_completions`

| Column | Type | Notes |
|--------|------|-------|
| id | uuid PK | |
| user_id | uuid FK → profiles | |
| experience_id | uuid FK → experiences | |
| completed_at | timestamptz | |
| note | text nullable | |
| photo_urls | text[] | Gallery |

Unique: `(user_id, experience_id)`

### `comments`

| Column | Type | Notes |
|--------|------|-------|
| id | uuid PK | |
| experience_id | uuid FK → experiences | |
| author_id | uuid FK → profiles | |
| parent_id | uuid FK nullable → comments | Threading |
| body | text | |
| like_count | int | |
| created_at | timestamptz | |
| updated_at | timestamptz | |

### `notifications`

| Column | Type | Notes |
|--------|------|-------|
| id | uuid PK | |
| user_id | uuid FK → profiles | Recipient |
| actor_id | uuid FK → profiles | Who caused the event |
| type | notification_type | `follow`, `save`, `new_experience` |
| reference_id | uuid | Experience id (`save` / `new_experience`) or actor id (`follow`) |
| is_read | boolean | Default false |
| created_at | timestamptz | |

Populated by Postgres triggers on follow insert, `experience_saves` insert, and `experiences` insert (fan-out to followers; bookmark sentinel rows skipped). Clients may only SELECT/UPDATE their own rows.

Included in the `supabase_realtime` publication so the iOS app can subscribe to inserts for live badges and in-app banners.

---

## Indexes

```sql
CREATE INDEX idx_experiences_city_published ON experiences (city_id, published_at DESC)
  WHERE is_published = true;
CREATE INDEX idx_experiences_creator ON experiences (creator_id);
CREATE INDEX idx_stops_experience_order ON stops (experience_id, order_index);
CREATE INDEX idx_completions_experience ON experience_completions (experience_id);
CREATE INDEX idx_profiles_username ON profiles (username);
```

---

## Row Level Security (summary)

| Table | Select | Insert | Update | Delete |
|-------|--------|--------|--------|--------|
| profiles | Public | Own | Own | — |
| experiences | Published OR own | Auth | Own | Own |
| stops | Via experience | Creator | Creator | Creator |
| saves/likes | Own + aggregates | Own | — | Own |
| completions | Public gallery | Own | Own | Own |
| comments | Public | Auth | Own | Own |

---

## Storage Buckets

| Bucket | Path pattern | Access |
|--------|--------------|--------|
| `avatars` | `{user_id}/avatar.jpg` | Public read, owner write |
| `experiences` | `{experience_id}/cover.jpg` | Public read, creator write |
| `stops` | `{experience_id}/{stop_id}/{index}.jpg` | Public read, creator write |
| `completions` | `{completion_id}/{index}.jpg` | Public read, owner write |

---

## Swift Model Mapping

Core models live in `Trav/Core/Models/`:

- `City`, `Experience`, `ExperienceSummary`, `Stop`, `StopMedia`, `RouteSegment`
- `Profile`, `Comment`, `Completion`
- `Paginated<T>`, `CostLevel`, `TransportMode`

All models are `Codable`, `Sendable`, and `Identifiable` where appropriate.
