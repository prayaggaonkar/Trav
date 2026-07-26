-- Migration: Add triggers to notify followers on experience watchlist/completion.

create or replace function public.tg_experience_completions_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  follower_record record;
begin
  if tg_op = 'INSERT' then
    -- Update profiles completed counter
    update public.profiles
      set completion_count = completion_count + 1, updated_at = now()
      where id = new.user_id;

    -- Fan out notifications to all followers of the actor
    for follower_record in
      select follower_id from public.followers where following_id = new.user_id
    loop
      perform public.insert_notification(
        follower_record.follower_id,
        new.user_id,
        'new_experience'::public.notification_type,
        new.experience_id
      );
    end loop;

    return new;
  elsif tg_op = 'DELETE' then
    -- Update profiles completed counter
    update public.profiles
      set completion_count = greatest(completion_count - 1, 0), updated_at = now()
      where id = old.user_id;
    return old;
  end if;
  return null;
end;
$$;
