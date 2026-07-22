#!/usr/bin/env python3
import os
import argparse
import sys
from dotenv import load_dotenv
import pandas as pd
import geopandas as gpd
from supabase import create_client, Client
import overturemaps
import ssl
import time
import random
import json
import uuid
import math
from duckduckgo_search import DDGS

# Bypass SSL certificate verification for macOS environments facing missing local issuer certificates
try:
    ssl._create_default_https_context = ssl._create_unverified_context
except AttributeError:
    pass

# Load environment variables
load_dotenv()

# Berkeley BBox by default: (west, south, east, north)
DEFAULT_BBOX = (-122.28, 37.86, -122.24, 37.88)

# Excluded massive chains (case-insensitive checks)
EXCLUDED_CHAINS = {
    "starbucks", "target", "walmart", "mcdonald's", "mcdonalds", "subway", 
    "dunkin", "dunkin' donuts", "peet's coffee", "peets coffee", "7-eleven", "7 eleven",
    "safeway", "walgreens", "cvs", "trader joe's", "trader joes", "whole foods",
    "peet's", "chevron", "shell", "starbucks coffee", "peet’s"
}

# Permitted non-food hangout category vibes
ALLOWED_CATEGORIES = {
    "bar", "shopping", "vintage_store", "hiking_trail", "park", 
    "scenic_viewpoint", "museum", "bookstore"
}

def parse_args():
    parser = argparse.ArgumentParser(description="Overture Maps to Supabase Data Pipeline")
    parser.add_argument(
        "--bbox", 
        type=str, 
        default="-122.28,37.86,-122.24,37.88",
        help="Bounding box as 'west,south,east,north' (default: Berkeley area)"
    )
    parser.add_argument(
        "--dry-run", 
        action="store_true", 
        help="Fetch and filter data, but do not push to the database"
    )
    parser.add_argument(
        "--fetch-images", 
        action="store_true", 
        help="Automatically fetch up to 3 image URLs for each matched hangout spot"
    )
    return parser.parse_args()

def fetch_image_urls(query, limit=3):
    try:
        if not query:
            return []
        # Polite delay to avoid rate limiting blocks from DuckDuckGo
        time.sleep(random.uniform(0.7, 1.4))
        with DDGS() as ddgs:
            results = list(ddgs.images(query, max_results=limit))
            if results:
                return [r['image'] for r in results if 'image' in r]
    except Exception as e:
        print(f"   ⚠️ Warning: Failed to fetch images for '{query}': {e}")
    return []

def emoji_for_category(category):
    emojis = {
        "bar": "🍻",
        "shopping": "🛍️",
        "vintage_store": "🧥",
        "hiking_trail": "🥾",
        "park": "🌳",
        "scenic_viewpoint": "🌅",
        "museum": "🖼️",
        "bookstore": "📚",
        "cafe": "☕"
    }
    return emojis.get(category.lower(), "📍")

def get_or_create_system_profile(supabase: Client):
    try:
        res = supabase.table("profiles").select("id").eq("username", "rec_by_trav").execute()
        if res.data and len(res.data) > 0:
            return res.data[0]["id"]
    except Exception as e:
        print(f"   ⚠️ Warning checking profiles: {e}")
        
    system_id = str(uuid.uuid4())
    try:
        res = supabase.table("profiles").select("id").limit(1).execute()
        if res.data and len(res.data) > 0:
            return res.data[0]["id"]
            
        profile_data = {
            "id": system_id,
            "username": "rec_by_trav",
            "display_name": "Rec by Trav",
            "bio": "System recommendation feed.",
            "is_verified": True
        }
        supabase.table("profiles").insert(profile_data).execute()
        print(f"   ✅ Created system profile: 'rec_by_trav' ({system_id})")
        return system_id
    except Exception as e:
        print(f"   ⚠️ Error creating system profile, using random uuid: {e}")
        return system_id

def create_itineraries_from_places(places, creator_id):
    itineraries = []
    used_ids = set()
    
    def get_distance(p1, p2):
        return math.sqrt((p1["latitude"] - p2["latitude"])**2 + (p1["longitude"] - p2["longitude"])**2)
        
    for p1 in places:
        if p1["id"] in used_ids:
            continue
            
        neighbors = []
        for p2 in places:
            if p2["id"] != p1["id"] and p2["id"] not in used_ids:
                dist = get_distance(p1, p2)
                if dist < 0.012:
                    neighbors.append((p2, dist))
                    
        neighbors.sort(key=lambda x: x[1])
        
        selected_spots = [p1]
        used_categories = {p1["basic_category"]}
        
        for neighbor, dist in neighbors:
            if len(selected_spots) >= 3:
                break
            if neighbor["basic_category"] not in used_categories:
                selected_spots.append(neighbor)
                used_categories.add(neighbor["basic_category"])
                
        if len(selected_spots) < 2 and neighbors:
            for neighbor, dist in neighbors:
                if len(selected_spots) >= 3:
                    break
                if neighbor["id"] not in [s["id"] for s in selected_spots]:
                    selected_spots.append(neighbor)
                    
        if len(selected_spots) >= 2:
            for s in selected_spots:
                used_ids.add(s["id"])
                
            cats = [s["basic_category"] for s in selected_spots]
            names = [s["name"] for s in selected_spots]
            
            title = f"{names[0]} & {names[1]} Outing"
            description = f"Explore local favorites starting at {names[0]} and visiting {names[1]}."
            
            if any(c in ["hiking_trail", "scenic_viewpoint", "park"] for c in cats):
                title = f"Berkeley Nature Trail: {names[0]}"
                description = f"A scenic outdoor excursion featuring {', '.join(names)}."
            elif "cafe" in cats and "bookstore" in cats:
                title = "Berkeley Books & Brews Walk"
                description = f"Relax and read! Grab coffee at {names[0]} and browse titles at {names[1]}."
            elif "bar" in cats:
                title = "Berkeley Evening Social Trail"
                description = f"Unwind in town! Stroll between local spots including {names[0]} and {names[1]}."
            elif "shopping" in cats or "vintage_store" in cats:
                title = "Telegraph Ave Shopping Tour"
                description = f"Browse unique stores and local spots starting at {names[0]}."
                
            stops_json_list = []
            for idx, spot in enumerate(selected_spots):
                stop_data = {
                    "id": str(uuid.uuid4()),
                    "name": spot["name"],
                    "emoji": emoji_for_category(spot["basic_category"]),
                    "description": f"Curated stop at {spot['name']}",
                    "latitude": spot["latitude"],
                    "longitude": spot["longitude"],
                    "place_id": spot["id"],
                    "orderIndex": idx
                }
                stops_json_list.append(json.dumps(stop_data))
                
            itineraries.append({
                "id": str(uuid.uuid4()),
                "user_id": creator_id,
                "title": title,
                "description": description,
                "city": "Berkeley",
                "stops": stops_json_list
            })
            
    return itineraries

def extract_primary_name(names_val):
    if names_val is None:
        return None
    if isinstance(names_val, dict):
        return names_val.get('primary')
    try:
        return names_val['primary']
    except (TypeError, KeyError, IndexError):
        pass
    return None

def main():
    args = parse_args()
    
    # Parse bounding box
    try:
        bbox_tuple = tuple(map(float, args.bbox.split(",")))
        if len(bbox_tuple) != 4:
            raise ValueError()
    except ValueError:
        print("Error: Bounding box must be 4 comma-separated float values (west,south,east,north).")
        sys.exit(1)
        
    print(f"🌍 Starting pipeline for bounding box: {bbox_tuple}")
    
    # 1. Initialize Supabase if not dry run
    supabase: Client = None
    if not args.dry_run:
        supabase_url = os.getenv("SUPABASE_URL")
        supabase_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY") or os.getenv("SUPABASE_ANON_KEY") or os.getenv("SUPABASE_KEY")
        
        if not supabase_url or not supabase_key:
            print("Error: SUPABASE_URL and SUPABASE_KEY (or SUPABASE_SERVICE_ROLE_KEY) environment variables must be set.")
            print("Please configure them in a .env file or your shell environment.")
            sys.exit(1)
        
        print("🔗 Connecting to Supabase...")
        supabase = create_client(supabase_url, supabase_key)
    else:
        print("🧪 Running in DRY RUN mode. No data will be written to Supabase.")

    # 2. Extract Data from Overture Maps
    print("📡 Fetching Places data from Overture Maps (this can take a moment)...")
    try:
        reader = overturemaps.record_batch_reader("place", bbox=bbox_tuple)
        table = reader.read_all()
        gdf = gpd.GeoDataFrame.from_arrow(table)
    except Exception as e:
        print(f"Error fetching Overture Maps data: {e}")
        print("Please check your internet connection or the bounding box range.")
        sys.exit(1)
        
    total_raw = len(gdf)
    print(f"✅ Fetched {total_raw} raw places from Overture.")

    if total_raw == 0:
        print("No places found in this area.")
        return

    # Extract name, basic_category, and coordinates
    gdf['name'] = gdf['names'].apply(extract_primary_name)
    gdf['longitude'] = gdf['geometry'].apply(lambda geom: geom.x if geom else None)
    gdf['latitude'] = gdf['geometry'].apply(lambda geom: geom.y if geom else None)

    # 3. Filter Data
    print("🧹 Filtering places according to Hangout Spot logic...")
    
    filtered_places = []
    chains_filtered = 0
    categories_filtered = 0
    missing_data = 0
    
    # Detailed tracking for logs
    matched_categories_count = {}
    excluded_categories_count = {}
    excluded_chains_sample = []

    for idx, row in gdf.iterrows():
        name = row['name']
        category = row['basic_category']
        lat = row['latitude']
        lon = row['longitude']
        place_id = row['id']
        
        # Log parsing progress
        if idx > 0 and idx % 500 == 0:
            print(f"   Processed {idx}/{total_raw} places...")
            
        # Ensure we have valid string names/categories and non-null coordinates
        if not isinstance(name, str) or not isinstance(category, str) or pd.isna(lat) or pd.isna(lon):
            missing_data += 1
            continue
            
        # Chain filtering (case-insensitive)
        name_lower = name.lower()
        is_chain = False
        for chain in EXCLUDED_CHAINS:
            if chain in name_lower:
                is_chain = True
                break
                
        if is_chain:
            chains_filtered += 1
            if len(excluded_chains_sample) < 8:
                excluded_chains_sample.append(name)
            continue
            
        # Category filtering
        category_lower = category.lower()
        if category_lower not in ALLOWED_CATEGORIES:
            categories_filtered += 1
            excluded_categories_count[category_lower] = excluded_categories_count.get(category_lower, 0) + 1
            continue
            
        # Valid place mapping
        filtered_places.append({
            "id": place_id,
            "name": name,
            "basic_category": category_lower,
            "latitude": float(lat),
            "longitude": float(lon),
            "stops": []
        })
        matched_categories_count[category_lower] = matched_categories_count.get(category_lower, 0) + 1

    print(f"\n📊 Detailed Filter Summary:")
    print(f"   - Total Raw Places: {total_raw}")
    print(f"   - Skipped (Missing/Invalid data): {missing_data}")
    print(f"   - Skipped (Chains filtered): {chains_filtered}")
    if excluded_chains_sample:
        print(f"     Sample chains: {', '.join(excluded_chains_sample)}")
    print(f"   - Skipped (Other categories): {categories_filtered}")
    
    print(f"\n✅ Matched Hangout Spots: {len(filtered_places)}")
    for cat, count in sorted(matched_categories_count.items(), key=lambda x: x[1], reverse=True):
        print(f"   - {cat}: {count}")
        
    print(f"\n🚫 Top 5 Excluded Categories:")
    for cat, count in sorted(excluded_categories_count.items(), key=lambda x: x[1], reverse=True)[:5]:
        print(f"   - {cat}: {count}")

    if len(filtered_places) == 0:
        print("\nNo places matched the hangout spot logic. Exiting.")
        return

    # 4. Insert into Supabase
    if args.dry_run:
        print("\n📝 Sample filtered records (up to 5):")
        for p in filtered_places[:5]:
            print(f"   - {p['name']} ({p['basic_category']}) at ({p['latitude']}, {p['longitude']})")
        print("\nDry run completed successfully.")
        return

    print(f"🚀 Inserting {len(filtered_places)} places into Supabase 'places' table...")
    
    # Batched insertion
    batch_size = 100
    inserted_count = 0
    
    for i in range(0, len(filtered_places), batch_size):
        batch = filtered_places[i:i + batch_size]
        try:
            # We use upsert so that running the script multiple times is idempotent
            supabase.table("places").upsert(batch).execute()
            inserted_count += len(batch)
            print(f"   Inserted {inserted_count}/{len(filtered_places)}...")
        except Exception as e:
            print(f"Error inserting batch: {e}")
            print("Ensure that the 'places' table is created in your database.")
            sys.exit(1)
            
    # 5. Generate and Insert Hangout Itineraries into 'places' table
    print("\n🗺️ Generating custom hangout itineraries from matched places...")
    system_user_id = get_or_create_system_profile(supabase)
    itineraries = create_itineraries_from_places(filtered_places, system_user_id)
    
    if itineraries:
        # Convert itineraries to places table format
        itineraries_places = []
        for it in itineraries:
            itineraries_places.append({
                "id": it["id"],
                "name": it["title"],
                "basic_category": "itinerary",
                "latitude": float(json.loads(it["stops"][0])["latitude"]),
                "longitude": float(json.loads(it["stops"][0])["longitude"]),
                "stops": it["stops"]
            })
            
        print(f"🚀 Inserting {len(itineraries_places)} generated itineraries into Supabase 'places' table...")
        try:
            # Batched insertion
            for i in range(0, len(itineraries_places), 50):
                sub_batch = itineraries_places[i:i+50]
                supabase.table("places").upsert(sub_batch).execute()
            print(f"   Successfully inserted/updated {len(itineraries_places)} itineraries in 'places' table!")
        except Exception as e:
            print(f"   ⚠️ Warning: Failed to insert itineraries to Supabase places: {e}")
            print("   Please execute this SQL command in your Supabase dashboard editor first:")
            print("   ALTER TABLE public.places ADD COLUMN IF NOT EXISTS stops text[] NOT NULL DEFAULT '{}';")
    else:
        print("   No itineraries generated (insufficient clustered spots).")
            
    print("🎉 Pipeline finished successfully!")

if __name__ == "__main__":
    main()
