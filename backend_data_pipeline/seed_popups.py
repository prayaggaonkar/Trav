import os
import datetime
from dotenv import load_dotenv
from supabase import create_client, Client

def seed_database_popups():
    load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))
    
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        print("Error: Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY")
        return
        
    supabase: Client = create_client(url.strip(), key.strip())
    
    now = datetime.datetime.now(datetime.timezone.utc)
    
    events = [
        {
            "event_name": "Berkeley Open Pickleball Tournament & Social",
            "address": "San Pablo Park Courts, Berkeley, CA",
            "city": "Berkeley, CA",
            "latitude": 37.8540,
            "longitude": -122.2811,
            "category": "sports",
            "description": "Double elimination community pickleball tournament. All skill levels welcome! Refreshments and prizes provided.",
            "start_time": (now + datetime.timedelta(days=1, hours=4)).isoformat(),
            "end_time": (now + datetime.timedelta(days=1, hours=8)).isoformat(),
            "external_url": "https://eventbrite.com",
            "image_url": "https://images.unsplash.com/photo-1626248801379-51a0748a5f96?w=800&q=80",
            "source": "community"
        },
        {
            "event_name": "Telegraph Ave Night Market & Live Music",
            "address": "Telegraph Ave & Haste St, Berkeley, CA",
            "city": "Berkeley, CA",
            "latitude": 37.8655,
            "longitude": -122.2588,
            "category": "food",
            "description": "Street food vendors, artisanal crafts, craft boba, and live acoustic music sets under the lights.",
            "start_time": (now + datetime.timedelta(days=2, hours=6)).isoformat(),
            "end_time": (now + datetime.timedelta(days=2, hours=10)).isoformat(),
            "external_url": "https://eventbrite.com",
            "image_url": "https://images.unsplash.com/photo-1533900298318-6b8da08a523e?w=800&q=80",
            "source": "eventbrite"
        },
        {
            "event_name": "Sunset Live Jazz & Wine Social",
            "address": "Grizzly Peak Overlook, Berkeley, CA",
            "city": "Berkeley, CA",
            "latitude": 37.8816,
            "longitude": -122.2384,
            "category": "music",
            "description": "Outdoor live jazz trio performance overlooking the Bay sunset. Bring lawn chairs and picnic blankets.",
            "start_time": (now + datetime.timedelta(days=3, hours=5)).isoformat(),
            "end_time": (now + datetime.timedelta(days=3, hours=8)).isoformat(),
            "external_url": "https://ticketmaster.com",
            "image_url": "https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=800&q=80",
            "source": "ticketmaster"
        },
        {
            "event_name": "Board Games, Craft Beer & Trivia Night",
            "address": "Fieldwork Brewing Co, Berkeley, CA",
            "city": "Berkeley, CA",
            "latitude": 37.8812,
            "longitude": -122.3021,
            "category": "meetups",
            "description": "Join local tabletop enthusiasts for board game tables, team trivia competition, and fresh craft beers.",
            "start_time": (now + datetime.timedelta(days=4, hours=6)).isoformat(),
            "end_time": (now + datetime.timedelta(days=4, hours=9)).isoformat(),
            "external_url": "https://meetup.com",
            "image_url": "https://images.unsplash.com/photo-1529699211952-734e80c4d42b?w=800&q=80",
            "source": "meetup"
        },
        {
            "event_name": "SF Golden Gate Park Run Club & Coffee",
            "address": "Ocean Beach Plaza, San Francisco, CA",
            "city": "San Francisco, CA",
            "latitude": 37.7694,
            "longitude": -122.4862,
            "category": "sports",
            "description": "5K coastal social run along Ocean Beach followed by complimentary pour-over coffee.",
            "start_time": (now + datetime.timedelta(days=2, hours=2)).isoformat(),
            "end_time": (now + datetime.timedelta(days=2, hours=4)).isoformat(),
            "external_url": "https://strava.com",
            "image_url": "https://images.unsplash.com/photo-1476480862126-209bfaa8edc8?w=800&q=80",
            "source": "community"
        },
        {
            "event_name": "Mission District Mural Walk & DIY Printmaking",
            "address": "Clarion Alley, San Francisco, CA",
            "city": "San Francisco, CA",
            "latitude": 37.7629,
            "longitude": -122.4187,
            "category": "art",
            "description": "Guided street art tour followed by hands-on screen printing and linocut workshops with local artists.",
            "start_time": (now + datetime.timedelta(days=3, hours=3)).isoformat(),
            "end_time": (now + datetime.timedelta(days=3, hours=6)).isoformat(),
            "external_url": "https://luma.ma",
            "image_url": "https://images.unsplash.com/photo-1513364776144-60967b0f800f?w=800&q=80",
            "source": "luma"
        }
    ]
    
    print(f"Connecting to Supabase database at {url}...")
    for ev in events:
        try:
            print(f"Upserting backend popup: {ev['event_name']} ({ev['category'].upper()})")
            res = supabase.table("popups").upsert(ev, on_conflict="event_name,start_time").execute()
            print(f"Successfully wrote {ev['event_name']}")
        except Exception as e:
            print(f"Error inserting {ev['event_name']}: {e}")

if __name__ == "__main__":
    seed_database_popups()
