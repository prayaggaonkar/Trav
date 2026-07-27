-- APNs device tokens for push notification delivery.
-- The send-push Edge Function (database webhook on notifications insert)
-- reads these with the service role.

create table if not exists public.device_tokens (
  token text primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  platform text not null default 'ios' check (platform in ('ios')),
  environment text not null default 'production' check (environment in ('production', 'sandbox')),
  updated_at timestamptz not null default now()
);

create index if not exists idx_device_tokens_user on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

drop policy if exists "Users manage their own device tokens" on public.device_tokens;
create policy "Users manage their own device tokens"
  on public.device_tokens for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update, delete on public.device_tokens to authenticated;
