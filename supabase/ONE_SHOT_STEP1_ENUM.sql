-- RUN THIS FIRST (alone). Wait for Success, then run ONE_SHOT_STEP2_SCHEMA.sql

do $$
begin
  if not exists (select 1 from pg_type where typname = 'notification_type') then
    create type public.notification_type as enum (
      'follow', 'save', 'new_experience', 'watchlist', 'like', 'comment'
    );
  end if;
end
$$;

alter type public.notification_type add value if not exists 'watchlist';
alter type public.notification_type add value if not exists 'like';
alter type public.notification_type add value if not exists 'comment';
