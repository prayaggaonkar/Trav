-- New notification kinds for the rating-driven completion loop.
-- Kept in its own migration: enum values added here must not be used in the
-- same transaction that adds them.

alter type public.notification_type add value if not exists 'rating';
alter type public.notification_type add value if not exists 'completion';
