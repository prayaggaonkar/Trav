-- Migration to restructure popups table with location coordinates, broad categories, and RPC location search
-- Categories: sports, music, meetups, food, art, general

ALTER TABLE public.popups
  ADD COLUMN IF NOT EXISTS city text DEFAULT 'Berkeley, CA',
  ADD COLUMN IF NOT EXISTS latitude double precision,
  ADD COLUMN IF NOT EXISTS longitude double precision,
  ADD COLUMN IF NOT EXISTS category text DEFAULT 'general',
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS external_url text,
  ADD COLUMN IF NOT EXISTS image_url text,
  ADD COLUMN IF NOT EXISTS source text DEFAULT 'community';

-- Index coordinates & category for fast location/category queries
CREATE INDEX IF NOT EXISTS idx_popups_coordinates ON public.popups (latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_popups_category ON public.popups (category);
CREATE INDEX IF NOT EXISTS idx_popups_city ON public.popups (city);

-- Stored procedure to fetch popups near a given latitude/longitude ordered by proximity & date
CREATE OR REPLACE FUNCTION public.fetch_popups_near(
    user_lat double precision,
    user_lng double precision,
    radius_miles double precision DEFAULT 50.0,
    limit_count integer DEFAULT 50
)
RETURNS TABLE (
    id uuid,
    event_name text,
    address text,
    city text,
    latitude double precision,
    longitude double precision,
    category text,
    description text,
    start_time timestamptz,
    end_time timestamptz,
    external_url text,
    image_url text,
    source text,
    distance_miles double precision
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id,
        p.event_name,
        p.address,
        p.city,
        p.latitude,
        p.longitude,
        p.category,
        p.description,
        p.start_time,
        p.end_time,
        p.external_url,
        p.image_url,
        p.source,
        CASE 
            WHEN p.latitude IS NOT NULL AND p.longitude IS NOT NULL AND (user_lat != 0 OR user_lng != 0) THEN
                (
                    3959 * acos(
                        least(1.0, greatest(-1.0, 
                            cos(radians(user_lat)) * cos(radians(p.latitude)) * 
                            cos(radians(p.longitude) - radians(user_lng)) + 
                            sin(radians(user_lat)) * sin(radians(p.latitude))
                        ))
                    )
                )
            ELSE 0.0
        END AS distance_miles
    FROM public.popups p
    WHERE 
        -- If location is supplied (non-zero), filter by radius; otherwise return recent/upcoming popups
        (user_lat = 0 AND user_lng = 0) OR
        (
            p.latitude IS NOT NULL AND p.longitude IS NOT NULL AND
            (
                3959 * acos(
                    least(1.0, greatest(-1.0, 
                        cos(radians(user_lat)) * cos(radians(p.latitude)) * 
                        cos(radians(p.longitude) - radians(user_lng)) + 
                        sin(radians(user_lat)) * sin(radians(p.latitude))
                    ))
                )
            ) <= radius_miles
        )
    ORDER BY p.start_time ASC
    LIMIT limit_count;
END;
$$;

-- Grant execution permissions
GRANT EXECUTE ON FUNCTION public.fetch_popups_near TO anon, authenticated;
