-- Migration: Create Main Leaderboard RPC Function
-- Formula: Total Score = (Impact * 5) + (Experiences * 25) + (Streak Days * 15) + (Streak Posts * 5)

create or replace function public.get_main_leaderboard()
returns table (
    user_id uuid,
    username text,
    display_name text,
    avatar_url text,
    impact_count bigint,
    experience_count bigint,
    streak_days integer,
    streak_posts integer,
    total_score bigint,
    rank bigint
)
language plpgsql
security definer
as $$
declare
    today_date date := current_date;
    yesterday_date date := current_date - 1;
begin
    return query
    with user_experiences as (
        select
            e.id as experience_id,
            e.user_id as creator_id,
            e.created_at::date as post_date,
            coalesce(e.save_count, 0) as row_save_count,
            coalesce(e.completion_count, 0) as row_completion_count
        from public.experiences e
        where e.is_published = true
    ),
    saves_tally as (
        select s.experience_id, count(*)::bigint as tbl_saves
        from (
            select experience_id from public.experience_saves
            union all
            select experience_id from public.saved_experiences
        ) s
        group by s.experience_id
    ),
    watchlists_tally as (
        select w.experience_id, count(*)::bigint as tbl_watchlists
        from (
            select experience_id from public.watchlists
            union all
            select experience_id from public.experience_completions
        ) w
        group by w.experience_id
    ),
    experience_scores as (
        select
            ue.experience_id,
            ue.creator_id,
            ue.post_date,
            greatest(ue.row_save_count, coalesce(st.tbl_saves, 0)) as exp_saves,
            greatest(ue.row_completion_count, coalesce(wt.tbl_watchlists, 0)) as exp_watchlists
        from user_experiences ue
        left join saves_tally st on st.experience_id = ue.experience_id
        left join watchlists_tally wt on wt.experience_id = ue.experience_id
    ),
    user_totals as (
        select
            p.id as profile_id,
            p.username,
            p.display_name,
            p.avatar_url,
            coalesce(sum(es.exp_saves + es.exp_watchlists), 0)::bigint as total_impact,
            count(es.experience_id)::bigint as total_experiences
        from public.profiles p
        left join experience_scores es on es.creator_id = p.id
        where lower(p.username) != 'rec_by_trav'
          and lower(coalesce(p.display_name, '')) != 'rec by trav'
        group by p.id, p.username, p.display_name, p.avatar_url
    ),
    user_post_days as (
        select distinct
            e.user_id as creator_id,
            e.created_at::date as pdate
        from public.experiences e
        where e.is_published = true
    ),
    user_streaks as (
        select
            p.id as profile_id,
            (
                with recursive streak_calc as (
                    select
                        case
                            when exists (select 1 from user_post_days upd where upd.creator_id = p.id and upd.pdate = today_date)
                                then today_date
                            when exists (select 1 from user_post_days upd where upd.creator_id = p.id and upd.pdate = yesterday_date)
                                then yesterday_date
                            else null
                        end as current_day,
                        0 as streak_count
                    union all
                    select
                        (sc.current_day - 1)::date,
                        sc.streak_count + 1
                    from streak_calc sc
                    where sc.current_day is not null
                      and exists (
                          select 1 from user_post_days upd
                          where upd.creator_id = p.id and upd.pdate = sc.current_day
                      )
                )
                select coalesce(max(streak_count), 0)::integer
                from streak_calc
            ) as s_days
        from public.profiles p
    ),
    streak_details as (
        select
            us.profile_id,
            us.s_days as streak_days,
            case
                when us.s_days > 0 then (
                    select count(*)::integer
                    from public.experiences e
                    where e.user_id = us.profile_id
                      and e.is_published = true
                      and e.created_at::date >= (
                          case
                              when exists (select 1 from user_post_days upd where upd.creator_id = us.profile_id and upd.pdate = today_date)
                                  then today_date - (us.s_days - 1)
                              else yesterday_date - (us.s_days - 1)
                          end
                      )
                      and e.created_at::date <= (
                          case
                              when exists (select 1 from user_post_days upd where upd.creator_id = us.profile_id and upd.pdate = today_date)
                                  then today_date
                              else yesterday_date
                          end
                      )
                )
                else 0
            end as streak_posts
        from user_streaks us
    ),
    final_scores as (
        select
            ut.profile_id as user_id,
            ut.username,
            coalesce(ut.display_name, ut.username) as display_name,
            ut.avatar_url,
            ut.total_impact as impact_count,
            ut.total_experiences as experience_count,
            sd.streak_days,
            sd.streak_posts,
            (
                (ut.total_impact * 5) +
                (ut.total_experiences * 25) +
                (sd.streak_days * 15) +
                (sd.streak_posts * 5)
            )::bigint as total_score
        from user_totals ut
        join streak_details sd on sd.profile_id = ut.profile_id
    )
    select
        fs.user_id,
        fs.username,
        fs.display_name,
        fs.avatar_url,
        fs.impact_count,
        fs.experience_count,
        fs.streak_days,
        fs.streak_posts,
        fs.total_score,
        dense_rank() over (order by fs.total_score desc, fs.display_name asc)::bigint as rank
    from final_scores fs
    order by fs.total_score desc, fs.display_name asc;
end;
$$;

grant execute on function public.get_main_leaderboard() to anon, authenticated;
