import os
from dotenv import load_dotenv
from supabase import create_client, Client

def main():
    env_path = os.path.join(os.path.dirname(__file__), ".env")
    load_dotenv(env_path)
    
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        print("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env")
        return
        
    supabase: Client = create_client(url.strip(), key.strip())
    
    print("Fetching all events from popups table...")
    res = supabase.table("popups").select("id, event_name, start_time").execute()
    rows = res.data
    print(f"Total rows in popups table: {len(rows)}")
    
    seen = set()
    duplicate_ids = []
    
    for row in rows:
        name = row.get("event_name", "").strip()
        start = row.get("start_time")
        # Define duplicate key by name and start time
        unique_key = (name.lower(), start)
        
        if unique_key in seen:
            duplicate_ids.append(row["id"])
        else:
            seen.add(unique_key)
            
    print(f"Found {len(duplicate_ids)} duplicate rows to delete.")
    
    deleted_count = 0
    # Delete duplicates by ID
    for rid in duplicate_ids:
        try:
            supabase.table("popups").delete().eq("id", rid).execute()
            deleted_count += 1
        except Exception as e:
            print(f"Error deleting row {rid}: {e}")
            
    print(f"Clean-up complete. Successfully deleted {deleted_count} duplicate rows.")

if __name__ == "__main__":
    main()
