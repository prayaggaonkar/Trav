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
            "photo_urls": []
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

    # 3.5 Fetch Images if requested
    if args.fetch_images:
        print(f"\n📸 Fetching image URLs for {len(filtered_places)} hangout spots (this will take a moment due to rate-limiting safety delays)...")
        for i, place in enumerate(filtered_places):
            query = f"{place['name']} Berkeley"
            print(f"   [{i+1}/{len(filtered_places)}] Searching images for: '{query}'...")
            photo_urls = fetch_image_urls(query, limit=3)
            place["photo_urls"] = photo_urls
            if photo_urls:
                print(f"      Found {len(photo_urls)} image(s)")
            else:
                print(f"      No images found")

    # 4. Insert into Supabase
    if args.dry_run:
        print("\n📝 Sample filtered records (up to 5):")
        for p in filtered_places[:5]:
            img_status = f"{len(p['photo_urls'])} image(s)" if args.fetch_images else "images skipped"
            print(f"   - {p['name']} ({p['basic_category']}) at ({p['latitude']}, {p['longitude']}) [{img_status}]")
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
            
    print("🎉 Pipeline finished successfully!")

if __name__ == "__main__":
    main()
