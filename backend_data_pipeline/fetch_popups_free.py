import asyncio
import os
import json
import requests
from dotenv import load_dotenv
from playwright.async_api import async_playwright
import ollama
from supabase import create_client, Client

# Scrape static or dynamic webpage text using Playwright
async def scrape_webpage(url: str) -> str:
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(
            user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        )
        page = await context.new_page()
        try:
            print(f"Scraping URL: {url}")
            await page.goto(url, wait_until="networkidle", timeout=30000)
            # Wait short time for dynamic items
            await page.wait_for_timeout(2000)
            text = await page.locator("body").inner_text()
            return text
        except Exception as e:
            print(f"Error scraping {url}: {e}")
            return ""
        finally:
            await browser.close()

# Fetch latest post data from Berkeley Reddit search endpoint
# Fetch latest post data from Berkeley Reddit using Playwright browser to bypass Cloudflare 403 blocks
async def scrape_reddit() -> list:
    url = "https://old.reddit.com/r/berkeley/new/"
    print("Fetching Reddit events from /r/berkeley using Playwright browser...")
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(
            user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        )
        page = await context.new_page()
        try:
            await page.goto(url, wait_until="networkidle", timeout=30000)
            
            # Extract post entries on old.reddit
            things = await page.locator("div.thing").all()
            posts = []
            for thing in things[:20]:
                title_el = thing.locator("a.title")
                if await title_el.count() > 0:
                    title = await title_el.inner_text()
                    posts.append(f"Title: {title}")
                    
            if posts:
                # Filter posts locally by keywords
                keywords = ["popup", "pop-up", "event", "hangout", "signing", "market", "meetup", "show", "party", "festival"]
                filtered = [p for p in posts if any(kw in p.lower() for kw in keywords)]
                print(f"Playwright Reddit scraper found {len(filtered)} keyword-matched posts on old.reddit.")
                return filtered
                
            # Fallback to standard reddit new
            print("old.reddit returned no entries. Trying standard /r/berkeley/new/ text extract...")
            await page.goto("https://www.reddit.com/r/berkeley/new/", wait_until="networkidle", timeout=30000)
            await page.wait_for_timeout(3000)
            body_text = await page.locator("body").inner_text()
            
            lines = body_text.split("\n")
            matched_lines = []
            keywords = ["popup", "pop-up", "event", "hangout", "signing", "market", "meetup", "show", "party", "festival"]
            for line in lines:
                if any(kw in line.lower() for kw in keywords):
                    matched_lines.append(line.strip())
            
            unique_lines = list(set([l for l in matched_lines if len(l) > 10]))
            print(f"Playwright standard Reddit scraper found {len(unique_lines)} keyword-matched lines.")
            return unique_lines[:10]
            
        except Exception as e:
            print(f"Error scraping Reddit via Playwright: {e}")
            return []
        finally:
            await browser.close()

# Extract event details using local Ollama model (llama3)
def extract_events_with_ollama(text: str) -> list:
    if not text.strip():
        return []
        
    # Limit context size to prevent token limits on local runner
    text_chunk = text[:3500]
    
    prompt = (
        "Extract the event details from this text and format it strictly as a JSON list. "
        "Each object in the JSON list must have exactly these keys:\n"
        "- event_name: string\n"
        "- address: string (default to 'Berkeley, CA' if vague or missing)\n"
        "- start_time: string (ISO 8601 format, or null if unknown)\n"
        "- end_time: string (ISO 8601 format, or null if unknown)\n\n"
        f"Source Text:\n{text_chunk}\n"
    )
    
    try:
        print("Processing raw text with local llama3 in Ollama...")
        response = ollama.chat(
            model="llama3",
            messages=[
                {
                    "role": "system",
                    "content": "You are a precise data extractor. You must output valid JSON lists only, containing event records matching the specified schema. Output nothing but raw JSON."
                },
                {"role": "user", "content": prompt}
            ],
            options={"temperature": 0.0},
            format="json"  # Forces JSON constraint in Ollama
        )
        
        raw_output = response.get("message", {}).get("content", "").strip()
        if not raw_output:
            return []
            
        parsed = json.loads(raw_output)
        
        # Format normalization
        if isinstance(parsed, dict):
            if "event_name" in parsed:
                return [parsed]
            for val in parsed.values():
                if isinstance(val, list):
                    return val
        elif isinstance(parsed, list):
            return parsed
            
        return []
    except Exception as e:
        print(f"Error during Ollama inference: {e}")
        return []

# Resiliently parse and convert date formats to standard ISO 8601 or fallback to None to prevent database SQL errors
def clean_and_parse_iso8601(date_str: str) -> str:
    import re
    from datetime import datetime
    
    if not date_str or not isinstance(date_str, str):
        return None
        
    date_str = date_str.strip()
    if date_str.lower() in ("null", "none", "unknown", ""):
        return None
        
    # 1. Try direct ISO parsing
    try:
        dt = datetime.fromisoformat(date_str.replace("Z", "+00:00"))
        return dt.isoformat()
    except Exception:
        pass
        
    # 2. Try fuzzy parser from dateutil (dependency of pandas/geopandas/overturemaps)
    try:
        from dateutil import parser as date_parser
        # Clean common symbols like bullet points, dashes, and duplicate spacing
        cleaned = re.sub(r'[•·\-\u2013\u2014]', ' ', date_str)
        cleaned = re.sub(r'\s+', ' ', cleaned).strip()
        
        dt = date_parser.parse(cleaned, fuzzy=True)
        # Handle implied year cases (e.g., Aug 15 without a year parsing as 1900)
        if dt.year < 2000:
            dt = dt.replace(year=datetime.now().year)
        return dt.isoformat()
    except Exception:
        pass
        
    # 3. Fallback to None (safe NULL in Postgres)
    return None

# Write records into Supabase popups table
def insert_popups_to_supabase(events: list):
    supabase_url = os.environ.get("SUPABASE_URL")
    supabase_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not supabase_url or not supabase_key:
        print("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY environment variables.")
        return
        
    supabase: Client = create_client(supabase_url.strip(), supabase_key.strip())
    
    # Pre-fetch existing rows to deduplicate and prevent duplicate writes
    print("Pre-fetching existing events to prevent duplicates...")
    try:
        existing_res = supabase.table("popups").select("event_name").execute()
        existing_names = set(row.get("event_name", "").strip().lower() for row in existing_res.data)
    except Exception as e:
        print(f"Warning: Could not pre-fetch existing popups (using empty set): {e}")
        existing_names = set()
    
    inserted_count = 0
    for event in events:
        name = event.get("event_name")
        if not name or name.lower() == "null" or "test event" in name.lower():
            continue
            
        name_clean = name.strip()
        if name_clean.lower() in existing_names:
            print(f"Skipping duplicate event: {name_clean}")
            continue
            
        address = event.get("address", "Berkeley, CA")
        if not address or address.strip().lower() == "null" or address.strip() == "":
            address = "Berkeley, CA"
            
        # Parse and sanitize timestamps
        start_time = clean_and_parse_iso8601(event.get("start_time"))
        end_time = clean_and_parse_iso8601(event.get("end_time"))
        
        row = {
            "event_name": name_clean,
            "address": address,
            "start_time": start_time,
            "end_time": end_time
        }
        
        try:
            print(f"Writing to database: {name_clean} at {address} (Time: {start_time or 'N/A'})")
            supabase.table("popups").insert(row).execute()
            existing_names.add(name_clean.lower()) # Prevent duplicate inserts within the same batch
            inserted_count += 1
        except Exception as e:
            print(f"Database insert error for '{name_clean}': {e}")
            
    print(f"Database sync complete. Total pop-up events added: {inserted_count}")

async def main():
    # Load env variables from .env
    env_path = os.path.join(os.path.dirname(__file__), ".env")
    load_dotenv(env_path)
    
    # 1. Scraping pages
    luma_url = "https://lu.ma/sf"
    eventbrite_url = "https://www.eventbrite.com/d/ca--berkeley/events/"
    
    luma_text = await scrape_webpage(luma_url)
    eventbrite_text = await scrape_webpage(eventbrite_url)
    
    # 2. Reddit Scraping
    reddit_posts = await scrape_reddit()
    
    all_events = []
    
    # 3. Extraction with Ollama
    if luma_text:
        print("Extracting from Luma search results...")
        luma_events = extract_events_with_ollama(luma_text)
        all_events.extend(luma_events)
        
    if eventbrite_text:
        print("Extracting from Eventbrite search results...")
        eb_events = extract_events_with_ollama(eventbrite_text)
        all_events.extend(eb_events)
        
    for i, post in enumerate(reddit_posts[:10]):  # Limit to top 10 new posts to keep it fast
        print(f"Extracting from Reddit post {i+1}/{min(10, len(reddit_posts))}...")
        post_events = extract_events_with_ollama(post)
        all_events.extend(post_events)
        
    # 4. Filter and insert
    print(f"Extracted {len(all_events)} candidate popups.")
    if all_events:
        insert_popups_to_supabase(all_events)
    else:
        print("No valid events parsed by local LLM.")

if __name__ == "__main__":
    asyncio.run(main())
