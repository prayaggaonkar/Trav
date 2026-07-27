-- Expand notification_type with values the app already models
-- (AppNotificationType.watchlist) and the new social loop (like, comment).
-- Kept in its own migration: enum values added here must not be used in the
-- same transaction that adds them.

alter type public.notification_type add value if not exists 'watchlist';
alter type public.notification_type add value if not exists 'like';
alter type public.notification_type add value if not exists 'comment';
