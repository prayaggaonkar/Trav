-- Resync profile follower and following counts with canonical follows table for all users
update public.profiles p
set follower_count  = (select count(*) from public.follows f where f.following_id = p.id),
    following_count = (select count(*) from public.follows f where f.follower_id = p.id);
