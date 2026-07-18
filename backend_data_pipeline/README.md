# 🌍 Overture Maps to Supabase Data Pipeline

This folder contains a standalone Python data pipeline designed to extract Point of Interest (POI) data, filter it to find high-quality hangout spots, and load it into your Supabase database.

---

## 📂 Pipeline Structure
All pipeline files are isolated in the root-level `backend_data_pipeline/` directory so they do not pollute the iOS Swift codebase:
- [pipeline.py](file:///Users/nikhil23rao/Dev/Trav/backend_data_pipeline/pipeline.py) — The main executable Python pipeline.
- [requirements.txt](file:///Users/nikhil23rao/Dev/Trav/backend_data_pipeline/requirements.txt) — Python dependency declaration.

---

## 🗄️ 1. Setup Supabase Table
Run this SQL query in your **Supabase Dashboard SQL Editor** to create the required `places` table and index before running the script:

```sql
-- Create the places table
CREATE TABLE IF NOT EXISTS public.places (
  id text PRIMARY KEY,                       -- Overture place ID (32-character string)
  name text NOT NULL,                        -- Name of the venue/spot
  basic_category text NOT NULL,              -- E.g. bar, park, museum, bookstore
  latitude double precision NOT NULL,        -- Latitude coordinate
  longitude double precision NOT NULL,       -- Longitude coordinate
  photo_urls text[] NOT NULL DEFAULT '{}',   -- Image URLs scraped for visual previews
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Enable Row Level Security (RLS)
ALTER TABLE public.places ENABLE ROW LEVEL SECURITY;

-- Create policies for access
CREATE POLICY "Allow public read access" ON public.places
  FOR SELECT USING (true);

CREATE POLICY "Allow service role write access" ON public.places
  FOR ALL USING (true);

-- Index coordinates for geographic querying
CREATE INDEX IF NOT EXISTS idx_places_coordinates ON public.places (latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_places_category ON public.places (basic_category);
```

---

## ⚙️ 2. Environment Configuration
Create a `.env` file inside the `backend_data_pipeline/` directory with your Supabase credentials:

```ini
# backend_data_pipeline/.env
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-supabase-service-role-key
```
> [!IMPORTANT]
> Use the **Service Role Key** (secret) instead of the Anon Key, as writing/inserting into the database requires write privileges.

---

## 🚀 3. Installation & Run Instructions

### Set up Virtual Environment
Open your terminal and navigate to the pipeline directory:
```bash
cd backend_data_pipeline
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Run a Dry Run (Safe Test)
Fetches and filters Overture Maps data for the Berkeley bounding box, but **does not write** to the database:
```bash
python3 pipeline.py --dry-run
```

### Run Live Insertion (without images)
Fetches, filters, and loads the data directly into your Supabase database:
```bash
python3 pipeline.py
```

### Run Live Insertion (with images)
Fetches, filters, scrapes up to 3 images for each hangout spot, and loads them into Supabase:
```bash
python3 pipeline.py --fetch-images
```

### Specify a Custom Bounding Box (Optional)
Pass your own bounds in the format `west,south,east,north`:
```bash
python3 pipeline.py --bbox="-122.32,37.84,-122.22,37.90" --fetch-images
```
```

---

## 🧹 Hangout Spot Filtering Logic

### Excluded Chains
Any place containing these chain names (case-insensitive) is automatically skipped to prioritize unique local spots:
* Starbucks, Peet's Coffee, Dunkin, Subway, McDonald's
* Target, Walmart, CVS, Walgreens, Safeway
* Whole Foods, Trader Joe's, Chevron, Shell

### Included Categories
Only POIs whose `basic_category` matches one of the following are kept:
* `bar`
* `shopping`
* `vintage_store`
* `hiking_trail`
* `park`
* `scenic_viewpoint`
* `museum`
* `bookstore`
