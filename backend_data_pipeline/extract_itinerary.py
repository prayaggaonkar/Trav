"""
================================================================================
Trav Backend Pipeline - Social Media Video Itinerary Extractor
================================================================================
Requirements:
    yt-dlp>=2024.0.0
    faster-whisper>=1.0.0
    opencv-python>=4.8.0
    pyobjc-framework-Vision>=10.0
    pyobjc-framework-Quartz>=10.0
    pyobjc-framework-Cocoa>=10.0
    requests>=2.31.0

Prerequisites:
    1. macOS running on Apple Silicon (M1/M2/M3/M4).
    2. Ollama installed and running locally with llama3.2 (or another model):
       $ ollama run llama3.2
================================================================================
"""

import argparse
import json
import logging
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

import cv2
import requests
import yt_dlp
from faster_whisper import WhisperModel

# macOS Vision / Cocoa bindings for offline Apple Silicon OCR
try:
    import Cocoa
    import Quartz
    import Vision
    VISION_AVAILABLE = True
except ImportError:
    VISION_AVAILABLE = False

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S"
)
logger = logging.getLogger("extract_itinerary")


# ==============================================================================
# Step 1: Download Media using yt-dlp
# ==============================================================================
def download_media(
    url: str,
    cookies_browser: str = "chrome",
    temp_dir: str = "."
) -> Dict[str, Any]:
    """
    Step 1: Download Media
    Uses yt-dlp to extract video metadata (caption, uploader) and download
    the MP3 audio file and MP4 video file. Attempts to pass browser cookies
    (Chrome/Safari) to bypass anti-bot blocks.
    """
    logger.info(f"Step 1: Downloading media from URL: {url}")
    
    video_path = os.path.join(temp_dir, "temp_video.mp4")
    audio_path = os.path.join(temp_dir, "temp_audio.mp3")

    # Clean up pre-existing temporary files if any
    for path in (video_path, audio_path):
        if os.path.exists(path):
            try:
                os.remove(path)
            except OSError:
                pass

    # Try browser cookies with graceful fallback
    browsers_to_try = [cookies_browser]
    if cookies_browser != "safari":
        browsers_to_try.append("safari")
    browsers_to_try.append(None)  # Try without cookies as last resort

    info_dict = None
    last_err = None

    for b in browsers_to_try:
        ydl_opts: Dict[str, Any] = {
            "quiet": True,
            "no_warnings": True,
            "outtmpl": os.path.join(temp_dir, "temp_download.%(ext)s"),
            "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
        }
        if b:
            ydl_opts["cookiesfrombrowser"] = (b,)

        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info_dict = ydl.extract_info(url, download=False)
                if info_dict:
                    logger.info(f"Successfully retrieved video info using browser cookies: {b or 'None'}")
                    break
        except Exception as e:
            last_err = e
            logger.warning(f"Browser cookies check failed for '{b}': {e}. Retrying with next option...")

    if not info_dict:
        raise RuntimeError(f"Failed to fetch metadata from URL with yt-dlp: {last_err}")

    caption = info_dict.get("description") or info_dict.get("title") or ""
    uploader = info_dict.get("uploader") or info_dict.get("channel") or info_dict.get("uploader_id") or "Unknown"

    # Download MP4 Video
    ydl_opts_video: Dict[str, Any] = {
        "quiet": True,
        "no_warnings": True,
        "outtmpl": video_path,
        "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
    }
    if cookies_browser:
        ydl_opts_video["cookiesfrombrowser"] = (cookies_browser,)

    try:
        with yt_dlp.YoutubeDL(ydl_opts_video) as ydl:
            ydl.download([url])
    except Exception as e:
        logger.warning(f"Video download with browser '{cookies_browser}' failed: {e}. Retrying without cookies...")
        ydl_opts_video.pop("cookiesfrombrowser", None)
        with yt_dlp.YoutubeDL(ydl_opts_video) as ydl:
            ydl.download([url])

    # Download MP3 Audio
    ydl_opts_audio: Dict[str, Any] = {
        "quiet": True,
        "no_warnings": True,
        "outtmpl": audio_path,
        "format": "bestaudio/best",
        "postprocessors": [{
            "key": "FFmpegExtractAudio",
            "preferredcodec": "mp3",
            "preferredquality": "192",
        }],
    }
    if cookies_browser:
        ydl_opts_audio["cookiesfrombrowser"] = (cookies_browser,)

    try:
        with yt_dlp.YoutubeDL(ydl_opts_audio) as ydl:
            ydl.download([url])
    except Exception as e:
        logger.warning(f"Audio extraction via yt-dlp failed: {e}. Downloading raw audio...")
        # Fallback raw audio download
        ydl_opts_audio.pop("postprocessors", None)
        ydl_opts_audio.pop("cookiesfrombrowser", None)
        with yt_dlp.YoutubeDL(ydl_opts_audio) as ydl:
            ydl.download([url])

    # Ensure files exist or create audio from video if ffmpeg postprocessor was skipped
    if not os.path.exists(audio_path) and os.path.exists(video_path):
        # Fallback to audio path pointing to video or renamed raw audio
        possible_audio_files = [f for f in os.listdir(temp_dir) if f.startswith("temp_audio")]
        if possible_audio_files:
            audio_path = os.path.join(temp_dir, possible_audio_files[0])
        else:
            audio_path = video_path

    logger.info(f"Download complete! Uploader: '{uploader}', Caption length: {len(caption)}")
    return {
        "caption": caption,
        "uploader": uploader,
        "video_path": video_path,
        "audio_path": audio_path,
    }


# ==============================================================================
# Step 2: Audio Transcription using faster-whisper
# ==============================================================================
def transcribe_audio(audio_path: str, model_size: str = "small") -> str:
    """
    Step 2: Audio Transcription
    Loads faster-whisper (model="small", device="cpu", compute_type="int8")
    and transcribes the audio file into a single text string.
    """
    logger.info(f"Step 2: Transcribing audio with faster-whisper (model='{model_size}', device='cpu', compute_type='int8')")
    if not os.path.exists(audio_path):
        logger.warning(f"Audio file '{audio_path}' not found. Returning empty transcript.")
        return ""

    model = WhisperModel(model_size, device="cpu", compute_type="int8")
    segments, info = model.transcribe(audio_path, beam_size=5)

    transcript_parts = [segment.text.strip() for segment in segments if segment.text]
    transcript = " ".join(transcript_parts).strip()
    
    logger.info(f"Audio transcription complete! Transcript length: {len(transcript)} chars")
    return transcript


# ==============================================================================
# Step 3: Video OCR using OpenCV & macOS Vision framework
# ==============================================================================
def extract_video_ocr(video_path: str, sample_interval_sec: float = 3.0) -> str:
    """
    Step 3: Video OCR
    Extracts 1 frame every 3 seconds from the MP4 using OpenCV (cv2).
    Passes frames to macOS Vision & Quartz (via pyobjc) to extract on-screen text.
    Consolidates text and removes duplicate lines.
    """
    logger.info(f"Step 3: Extracting video OCR (1 frame every {sample_interval_sec}s) via macOS Vision framework")
    if not VISION_AVAILABLE:
        logger.error("macOS Vision framework bindings (pyobjc-framework-Vision) are not installed.")
        return ""

    if not os.path.exists(video_path):
        logger.warning(f"Video file '{video_path}' not found for OCR processing.")
        return ""

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        logger.warning(f"Failed to open video file '{video_path}' with OpenCV.")
        return ""

    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 0:
        fps = 30.0

    frame_interval = max(1, int(fps * sample_interval_sec))
    frame_count = 0
    extracted_lines: List[str] = []
    seen_lines = set()

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break

        if frame_count % frame_interval == 0:
            # Encode frame (BGR ndarray) to JPEG bytes
            success, buffer = cv2.imencode(".jpg", frame)
            if success:
                jpeg_bytes = buffer.tobytes()
                # Create Cocoa NSData wrapper
                data = Cocoa.NSData.dataWithBytes_length_(jpeg_bytes, len(jpeg_bytes))
                
                # Perform macOS Vision Text Recognition
                handler = Vision.VNImageRequestHandler.alloc().initWithData_options_(data, None)
                request = Vision.VNRecognizeTextRequest.alloc().init()
                request.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)
                request.setUsesLanguageCorrection_(True)

                req_success, err = handler.performRequests_error_([request], None)
                if req_success and request.results():
                    for observation in request.results():
                        top_candidate = observation.topCandidates_(1)
                        if top_candidate:
                            text_str = top_candidate[0].string().strip()
                            if text_str and text_str.lower() not in seen_lines:
                                seen_lines.add(text_str.lower())
                                extracted_lines.append(text_str)

        frame_count += 1

    cap.release()
    consolidated_ocr = "\n".join(extracted_lines)
    logger.info(f"Video OCR complete! Extracted {len(extracted_lines)} unique text snippets.")
    return consolidated_ocr


# ==============================================================================
# Step 4: Local LLM Extraction using Ollama
# ==============================================================================
def extract_itinerary_llm(
    caption: str,
    transcript: str,
    ocr_text: str,
    model_name: str = "llama3.2",
    ollama_url: str = "http://localhost:11434/api/generate"
) -> Dict[str, Any]:
    """
    Step 4: Local LLM Extraction
    Sends HTTP POST request to local Ollama instance (http://localhost:11434/api/generate).
    Extracts itinerary title and an array of exact physical venues from combined data.
    Enforces strict JSON schema via Ollama's format parameter with keys: title, locations.
    """
    logger.info(f"Step 4: Extracting itinerary via local Ollama LLM (model='{model_name}')")
    
    prompt = f"""You are an expert travel itinerary extraction system.
Analyze the following social media metadata, audio transcript, and on-screen text (OCR) from a video.

Task:
1. Extract a concise, catchy itinerary title summarizing the video (e.g. "Tokyo Coffee Tour" or "Best Tacos in Austin").
2. Extract an array of exact physical venues, places, or location names mentioned or shown in the video (e.g. "Sightglass Coffee", "Golden Gate Park", "Tartine Bakery").
Exclude generic non-venue words like "coffee", "food", "street", "place" unless part of a specific venue name.

INPUT DATA:
- CAPTION: {caption or 'N/A'}
- AUDIO TRANSCRIPT: {transcript or 'N/A'}
- ON-SCREEN OCR TEXT: {ocr_text or 'N/A'}

Respond ONLY with valid JSON following the schema.
"""

    # Enforce strict JSON schema output via Ollama's format parameter
    payload = {
        "model": model_name,
        "prompt": prompt,
        "stream": False,
        "format": {
            "type": "object",
            "properties": {
                "title": {
                    "type": "string"
                },
                "locations": {
                    "type": "array",
                    "items": {
                        "type": "string"
                    }
                }
            },
            "required": ["title", "locations"]
        }
    }

    try:
        response = requests.post(ollama_url, json=payload, timeout=90)
        response.raise_for_status()
        res_json = response.json()
        response_text = res_json.get("response", "{}")
        parsed = json.loads(response_text)
        
        title = parsed.get("title", "Social Media Itinerary")
        locations = parsed.get("locations", [])
        logger.info(f"LLM Extraction complete! Title: '{title}', Locations: {locations}")
        return {"title": title, "locations": locations}
    except requests.exceptions.RequestException as e:
        logger.error(f"Failed to connect to Ollama at {ollama_url}: {e}")
        logger.warning("Falling back to basic keyword extraction...")
        return {"title": "Social Media Itinerary", "locations": []}
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse JSON response from Ollama: {e}")
        return {"title": "Social Media Itinerary", "locations": []}


# ==============================================================================
# Step 5: Geocoding using Nominatim (OpenStreetMap)
# ==============================================================================
def geocode_locations(
    locations: List[str],
    user_agent: str = "TravAppBackend/1.0 (contact@travapp.local)"
) -> List[Dict[str, Any]]:
    """
    Step 5: Geocoding
    Loops through extracted locations array and makes GET requests to OpenStreetMap Nominatim.
    Passes q={location_name}, format=json, limit=1 with custom User-Agent header.
    CRITICAL: Adds time.sleep(1.5) between each request to strictly respect Nominatim rate limits.
    Returns an array of dicts containing location name, lat, and lon.
    """
    logger.info(f"Step 5: Geocoding {len(locations)} locations via Nominatim API...")
    geocoded_results: List[Dict[str, Any]] = []
    headers = {"User-Agent": user_agent}

    for loc in locations:
        loc_clean = loc.strip()
        if not loc_clean:
            continue

        logger.info(f"Geocoding venue: '{loc_clean}'")
        params = {
            "q": loc_clean,
            "format": "json",
            "limit": 1
        }

        try:
            resp = requests.get(
                "https://nominatim.openstreetmap.org/search",
                params=params,
                headers=headers,
                timeout=10
            )
            if resp.status_code == 200:
                data = resp.json()
                if data and isinstance(data, list) and len(data) > 0:
                    first_match = data[0]
                    lat = float(first_match["lat"])
                    lon = float(first_match["lon"])
                    geocoded_results.append({
                        "name": loc_clean,
                        "lat": lat,
                        "lon": lon
                    })
                    logger.info(f"  -> Found coordinates for '{loc_clean}': lat={lat}, lon={lon}")
                else:
                    logger.warning(f"  -> No geocoding results found for '{loc_clean}'")
                    geocoded_results.append({
                        "name": loc_clean,
                        "lat": None,
                        "lon": None
                    })
            else:
                logger.warning(f"  -> Nominatim returned HTTP {resp.status_code} for '{loc_clean}'")
                geocoded_results.append({
                    "name": loc_clean,
                    "lat": None,
                    "lon": None
                })
        except Exception as e:
            logger.error(f"  -> Geocoding error for '{loc_clean}': {e}")
            geocoded_results.append({
                "name": loc_clean,
                "lat": None,
                "lon": None
            })

        # CRITICAL CONSTRAINT: Respect Nominatim policy with 1.5s pause
        time.sleep(1.5)

    return geocoded_results


# ==============================================================================
# Step 6: Output & Cleanup
# ==============================================================================
def process_video_itinerary(
    url: str,
    cookies_browser: str = "chrome",
    model_name: str = "llama3.2",
    output_path: str = "itinerary_output.json"
) -> Dict[str, Any]:
    """
    Step 6: Output & Cleanup
    Executes end-to-end pipeline, assembles final JSON object, prints to console,
    saves to itinerary_output.json, and cleans up temporary MP3/MP4 files in a
    try...finally block.
    """
    temp_dir = "."
    video_file = os.path.join(temp_dir, "temp_video.mp4")
    audio_file = os.path.join(temp_dir, "temp_audio.mp3")

    final_result: Dict[str, Any] = {}

    try:
        # Step 1: Download
        download_res = download_media(url, cookies_browser=cookies_browser, temp_dir=temp_dir)
        caption = download_res["caption"]
        uploader = download_res["uploader"]
        actual_video_path = download_res["video_path"]
        actual_audio_path = download_res["audio_path"]

        # Step 2: Audio Transcription
        transcript = transcribe_audio(actual_audio_path, model_size="small")

        # Step 3: Video OCR
        ocr_text = extract_video_ocr(actual_video_path, sample_interval_sec=3.0)

        # Step 4: Local LLM Extraction
        llm_res = extract_itinerary_llm(caption, transcript, ocr_text, model_name=model_name)
        title = llm_res.get("title", "Social Media Itinerary")
        raw_locations = llm_res.get("locations", [])

        # Step 5: Geocoding
        geocoded_locations = geocode_locations(raw_locations)

        # Assemble final JSON object
        final_result = {
            "uploader": uploader,
            "title": title,
            "locations": geocoded_locations
        }

        # Print final result to console
        print("\n" + "=" * 60)
        print("FINAL EXTRACTED ITINERARY JSON:")
        print("=" * 60)
        json_output_str = json.dumps(final_result, indent=2)
        print(json_output_str)
        print("=" * 60 + "\n")

        # Save to file
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(json_output_str)
        logger.info(f"Successfully saved final itinerary to '{output_path}'")

    finally:
        # Step 6: Cleanup temporary MP3/MP4 files
        logger.info("Cleaning up temporary audio/video files...")
        for temp_file in [video_file, audio_file]:
            if os.path.exists(temp_file):
                try:
                    os.remove(temp_file)
                    logger.info(f"Deleted temporary file: '{temp_file}'")
                except Exception as e:
                    logger.warning(f"Could not delete temporary file '{temp_file}': {e}")
        
        # Clean up any leftover temp_download or temp_audio wildcard files
        for f_name in os.listdir(temp_dir):
            if f_name.startswith("temp_download") or f_name.startswith("temp_audio"):
                try:
                    os.remove(os.path.join(temp_dir, f_name))
                except Exception:
                    pass

    return final_result


# ==============================================================================
# CLI Entry Point
# ==============================================================================
def main():
    parser = argparse.ArgumentParser(
        description="Extract physical itinerary locations from social media videos locally on Apple Silicon."
    )
    parser.add_argument(
        "--url",
        type=str,
        required=True,
        help="URL of the TikTok, Instagram Reel, or YouTube Short video."
    )
    parser.add_argument(
        "--cookies-browser",
        type=str,
        default="chrome",
        choices=["chrome", "safari", "firefox", "edge"],
        help="Browser to pass cookies from for yt-dlp to bypass blocks (default: chrome)."
    )
    parser.add_argument(
        "--model",
        type=str,
        default="llama3.2",
        help="Local Ollama model name (default: llama3.2)."
    )
    parser.add_argument(
        "--output",
        type=str,
        default="itinerary_output.json",
        help="Output JSON file path (default: itinerary_output.json)."
    )

    args = parser.parse_args()

    process_video_itinerary(
        url=args.url,
        cookies_browser=args.cookies_browser,
        model_name=args.model,
        output_path=args.output
    )


if __name__ == "__main__":
    main()
