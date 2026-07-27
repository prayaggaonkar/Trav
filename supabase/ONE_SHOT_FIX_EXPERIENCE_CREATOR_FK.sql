-- Restore the experiences → profiles FK so PostgREST can embed creators.
-- Safe to re-run. Optional — the iOS app no longer depends on the embed.
-- Run in Supabase SQL Editor if you want creator embeds to work again.

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'experiences_user_id_fkey'
      and conrelid = 'public.experiences'::regclass
  ) then
    -- Only add the FK when every user_id already points at a profile.
    if not exists (
      select 1
      from public.experiences e
      where e.user_id is not null
        and not exists (select 1 from public.profiles p where p.id = e.user_id)
    ) then
      alter table public.experiences
        add constraint experiences_user_id_fkey
        foreign key (user_id) references public.profiles (id) on delete cascade;
    end if;
  end if;
end $$;

notify pgrst, 'reload schema';
