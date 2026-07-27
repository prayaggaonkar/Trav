-- Moderation primitives required for a UGC app (App Store guideline 1.2):
-- content/user reports and user blocks. Blocked users' content is filtered
-- client-side; reports are reviewed via the dashboard.

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  -- Exactly one target: an experience, a comment, or a user.
  experience_id uuid references public.experiences (id) on delete cascade,
  comment_id uuid references public.comments (id) on delete cascade,
  reported_user_id uuid references public.profiles (id) on delete cascade,
  reason text not null check (reason in (
    'spam', 'inappropriate', 'harassment', 'misinformation', 'copyright', 'other'
  )),
  details text check (details is null or char_length(details) <= 500),
  status text not null default 'open' check (status in ('open', 'reviewed', 'actioned', 'dismissed')),
  created_at timestamptz not null default now(),
  constraint reports_single_target check (
    (experience_id is not null)::int
    + (comment_id is not null)::int
    + (reported_user_id is not null)::int = 1
  )
);

create index if not exists idx_reports_status_created
  on public.reports (status, created_at desc);

alter table public.reports enable row level security;

drop policy if exists "Users can file reports" on public.reports;
create policy "Users can file reports"
  on public.reports for insert
  with check (auth.uid() = reporter_id);

drop policy if exists "Users can read their own reports" on public.reports;
create policy "Users can read their own reports"
  on public.reports for select
  using (auth.uid() = reporter_id);

grant select, insert on public.reports to authenticated;

-- ---------------------------------------------------------------------------
-- blocks
-- ---------------------------------------------------------------------------
create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocks_no_self check (blocker_id <> blocked_id)
);

create index if not exists idx_blocks_blocked on public.blocks (blocked_id);

alter table public.blocks enable row level security;

drop policy if exists "Users can read their own blocks" on public.blocks;
create policy "Users can read their own blocks"
  on public.blocks for select
  using (auth.uid() = blocker_id);

drop policy if exists "Users can block others" on public.blocks;
create policy "Users can block others"
  on public.blocks for insert
  with check (auth.uid() = blocker_id);

drop policy if exists "Users can unblock" on public.blocks;
create policy "Users can unblock"
  on public.blocks for delete
  using (auth.uid() = blocker_id);

grant select, insert, delete on public.blocks to authenticated;

-- Blocking someone removes the follow edges in both directions.
create or replace function public.tg_blocks_remove_follows()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.follows
  where (follower_id = new.blocker_id and following_id = new.blocked_id)
     or (follower_id = new.blocked_id and following_id = new.blocker_id);
  return new;
end;
$$;

drop trigger if exists blocks_remove_follows_ai on public.blocks;
create trigger blocks_remove_follows_ai
  after insert on public.blocks
  for each row execute function public.tg_blocks_remove_follows();
