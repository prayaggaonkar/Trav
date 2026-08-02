-- 20260801160000_create_upcoming_trips.sql
-- Create upcoming_trips and trip_recommendations tables for crowdsourced spot recommendations

CREATE TABLE IF NOT EXISTS public.upcoming_trips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    destination_name TEXT NOT NULL,
    destination_city TEXT,
    latitude DOUBLE PRECISION DEFAULT 0,
    longitude DOUBLE PRECISION DEFAULT 0,
    start_date TIMESTAMPTZ NOT NULL,
    end_date TIMESTAMPTZ,
    note TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.trip_recommendations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id UUID NOT NULL REFERENCES public.upcoming_trips(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    spot_name TEXT NOT NULL,
    spot_category TEXT,
    latitude DOUBLE PRECISION DEFAULT 0,
    longitude DOUBLE PRECISION DEFAULT 0,
    image_url TEXT,
    upvote_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.upcoming_trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trip_recommendations ENABLE ROW LEVEL SECURITY;

-- upcoming_trips RLS
CREATE POLICY "Allow public read of upcoming trips"
    ON public.upcoming_trips FOR SELECT
    USING (true);

CREATE POLICY "Allow authenticated insert of upcoming trips"
    ON public.upcoming_trips FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Allow user update of own upcoming trips"
    ON public.upcoming_trips FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Allow user delete of own upcoming trips"
    ON public.upcoming_trips FOR DELETE
    USING (auth.uid() = user_id);

-- trip_recommendations RLS
CREATE POLICY "Allow public read of trip recommendations"
    ON public.trip_recommendations FOR SELECT
    USING (true);

CREATE POLICY "Allow authenticated insert of trip recommendations"
    ON public.trip_recommendations FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Allow user delete of own trip recommendations"
    ON public.trip_recommendations FOR DELETE
    USING (auth.uid() = user_id);

-- Indexes for fast queries
CREATE INDEX IF NOT EXISTS idx_upcoming_trips_start_date ON public.upcoming_trips(start_date DESC);
CREATE INDEX IF NOT EXISTS idx_upcoming_trips_user_id ON public.upcoming_trips(user_id);
CREATE INDEX IF NOT EXISTS idx_trip_recommendations_trip_id ON public.trip_recommendations(trip_id);
