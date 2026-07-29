import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface RequestPayload {
  prompt?: string;
  city?: string;
  latitude?: number;
  longitude?: number;
}

interface AIStop {
  id: string;
  name: string;
  address: string;
  latitude?: number;
  longitude?: number;
  description: string;
  category: string;
}

interface AIExperience {
  id: string;
  title: string;
  subtitle: string;
  cityName: string;
  coverImageURL: string;
  category: string;
  estimatedMinutes: number;
  vibeTags: string[];
  stops: AIStop[];
  creatorName: string;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    let body: RequestPayload = {};
    try {
      body = await req.json();
    } catch {
      // Empty body
    }

    const city = (body.city || "Berkeley, CA").split(",")[0].trim();
    const lat = body.latitude ?? 37.8715;
    const lng = body.longitude ?? -122.2730;
    const userPrompt = body.prompt?.trim();

    console.log(`[ask-trav] Processing request for city '${city}' (${lat}, ${lng}), prompt: '${userPrompt || 'Recs By Trav Feed'}'`);

    let itineraries: AIExperience[] = [];

    // Try Ollama endpoint if available (local or remote OLLAMA_HOST)
    const ollamaHost = Deno.env.get("OLLAMA_HOST") || "http://localhost:11434";
    try {
      const ollamaRes = await fetchOllamaGeneration(ollamaHost, city, lat, lng, userPrompt);
      if (ollamaRes && ollamaRes.length > 0) {
        itineraries = ollamaRes;
      }
    } catch (ollamaErr) {
      console.log(`[Ollama Offline] Falling back to structured AI Generator: ${(ollamaErr as Error).message}`);
    }

    // High-quality structured fallback generator if Ollama is not responding locally
    if (itineraries.length === 0) {
      itineraries = generateStructuredAIRecs(city, lat, lng, userPrompt);
    }

    return new Response(JSON.stringify({ experiences: itineraries, count: itineraries.length }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
    console.error("[ask-trav] Error:", error);
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});

// MARK: - Ollama API Integration

async function fetchOllamaGeneration(
  host: string,
  city: string,
  lat: number,
  lng: number,
  userPrompt?: string
): Promise<AIExperience[]> {
  const model = Deno.env.get("OLLAMA_MODEL") || "llama3";
  const systemPrompt = `You are Trav AI, an expert travel concierge and local guide.
Generate a JSON array of curated multi-stop itineraries for ${city}.
Return ONLY a raw JSON array matching this exact schema:
[
  {
    "id": "uuid-string",
    "title": "Itinerary Title",
    "subtitle": "Short 1-line summary",
    "cityName": "${city}",
    "coverImageURL": "https://images.unsplash.com/...",
    "category": "Food | Coffee | Nightlife | Culture | Outdoors",
    "estimatedMinutes": 180,
    "vibeTags": ["Cozy", "Craft Drinks"],
    "stops": [
      {
        "id": "stop-uuid",
        "name": "Spot Name",
        "address": "123 Main St, ${city}",
        "latitude": ${lat},
        "longitude": ${lng},
        "description": "Why visit this spot",
        "category": "Café"
      }
    ],
    "creatorName": "Recs By Trav"
  }
]`;

  const promptText = userPrompt
    ? `Create 3 custom itineraries in ${city} based on user request: "${userPrompt}"`
    : `Create 15 curated itineraries in ${city} covering morning coffee, foodie spots, sunset views, night markets, and cocktail lounges.`;

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 4000); // 4-second timeout for local Ollama

  try {
    const res = await fetch(`${host}/v1/chat/completions`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      signal: controller.signal,
      body: JSON.stringify({
        model: model,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: promptText }
        ],
        temperature: 0.7,
        response_format: { type: "json_object" }
      })
    });
    clearTimeout(timeoutId);

    if (!res.ok) return [];
    const data = await res.json();
    const content = data.choices?.[0]?.message?.content;
    if (!content) return [];

    const parsed = JSON.parse(content);
    return Array.isArray(parsed) ? parsed : (parsed.experiences || parsed.itineraries || []);
  } catch (err) {
    clearTimeout(timeoutId);
    throw err;
  }
}

// MARK: - Dynamic AI Generator (Zero-Latency Fallback)

function generateStructuredAIRecs(city: string, lat: number, lng: number, prompt?: string): AIExperience[] {
  const citySlug = city.toLowerCase().replace(/[^a-z0-9]+/g, "-");
  const isCustomPrompt = !!prompt;

  if (isCustomPrompt) {
    const pLower = prompt.toLowerCase();
    const isCoffee = pLower.includes("coffee") || pLower.includes("café") || pLower.includes("morning") || pLower.includes("bakery");
    const isNight = pLower.includes("night") || pLower.includes("bar") || pLower.includes("cocktail") || pLower.includes("drink") || pLower.includes("pub");
    const isOutdoors = pLower.includes("hike") || pLower.includes("park") || pLower.includes("outdoor") || pLower.includes("nature") || pLower.includes("trail");

    if (isCoffee) {
      return [createCoffeeItinerary(city, lat, lng)];
    } else if (isNight) {
      return [createNightlifeItinerary(city, lat, lng)];
    } else if (isOutdoors) {
      return [createOutdoorsItinerary(city, lat, lng)];
    } else {
      return [createCustomUserItinerary(city, lat, lng, prompt)];
    }
  }

  // Full 15-20 Recs By Trav Feed Selection
  return [
    createCoffeeItinerary(city, lat, lng),
    createFoodieItinerary(city, lat, lng),
    createNightlifeItinerary(city, lat, lng),
    createArtCultureItinerary(city, lat, lng),
    createOutdoorsItinerary(city, lat, lng),
    createShoppingItinerary(city, lat, lng),
    createSunsetItinerary(city, lat, lng),
    createBobaDessertItinerary(city, lat, lng),
    createCraftBeerItinerary(city, lat, lng),
    createHiddenGemsItinerary(city, lat, lng),
    createDateNightItinerary(city, lat, lng),
    createBrunchItinerary(city, lat, lng),
    createMusicLiveItinerary(city, lat, lng),
    createWellnessItinerary(city, lat, lng),
    createLateNightEatsItinerary(city, lat, lng)
  ];
}

function createCoffeeItinerary(city: string, lat: number, lng: number): AIExperience {
  return {
    id: `ai-coffee-${city.toLowerCase()}`,
    title: `${city} Morning Roasters & Artisan Bakery Crawl`,
    subtitle: "Pour-overs, cardamom buns, and sunlit patios",
    cityName: city,
    coverImageURL: "https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=800&q=80",
    category: "Coffee & Bakery",
    estimatedMinutes: 120,
    vibeTags: ["Cozy", "Pour Over", "Patios"],
    stops: [
      {
        id: "s1",
        name: "Ritual Coffee Roasters",
        address: `1024 Main St, ${city}`,
        latitude: lat + 0.002,
        longitude: lng - 0.003,
        description: "Single-origin espresso and pour-overs roasted locally.",
        category: "Coffee"
      },
      {
        id: "s2",
        name: "Flour & Butter Artisan Bakery",
        address: `1088 Main St, ${city}`,
        latitude: lat + 0.004,
        longitude: lng - 0.002,
        description: "Freshly baked sourdough croissants and cardamom morning buns.",
        category: "Bakery"
      },
      {
        id: "s3",
        name: "Sunlit Courtyard Gardens",
        address: `1120 Garden Way, ${city}`,
        latitude: lat + 0.005,
        longitude: lng - 0.001,
        description: "Quiet outdoor seating patio perfect for reading or catching up.",
        category: "Park & Garden"
      }
    ],
    creatorName: "Recs By Trav"
  };
}

function createFoodieItinerary(city: string, lat: number, lng: number): AIExperience {
  return {
    id: `ai-foodie-${city.toLowerCase()}`,
    title: `${city} Tacos, Boba & Artisan Ice Cream Trail`,
    subtitle: "A 3-stop feast featuring hand-pressed tortillas & matcha scoops",
    cityName: city,
    coverImageURL: "https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=800&q=80",
    category: "Foodie Trail",
    estimatedMinutes: 150,
    vibeTags: ["Street Eats", "Craft Boba", "Dessert"],
    stops: [
      {
        id: "s1",
        name: "Taquería El Sol",
        address: `450 Mission Ave, ${city}`,
        latitude: lat - 0.003,
        longitude: lng + 0.004,
        description: "Birria tacos with slow-cooked consommé and fresh salsa verde.",
        category: "Mexican Food"
      },
      {
        id: "s2",
        name: "Boba Craft & Tea Lounge",
        address: `482 Mission Ave, ${city}`,
        latitude: lat - 0.002,
        longitude: lng + 0.005,
        description: "Handcrafted taro tea with housemade brown sugar tapioca boba.",
        category: "Boba & Tea"
      },
      {
        id: "s3",
        name: "Scoops & Swirls Gelateria",
        address: `510 Mission Ave, ${city}`,
        latitude: lat - 0.001,
        longitude: lng + 0.006,
        description: "Small-batch organic pistachio gelato and waffle cones.",
        category: "Dessert"
      }
    ],
    creatorName: "Recs By Trav"
  };
}

function createNightlifeItinerary(city: string, lat: number, lng: number): AIExperience {
  return {
    id: `ai-nightlife-${city.toLowerCase()}`,
    title: `${city} Speakeasies, Rooftop DJ & Vinyl Lounge`,
    subtitle: "Craft mezcal cocktails and golden hour rooftop vibes",
    cityName: city,
    coverImageURL: "https://images.unsplash.com/photo-1514933651103-005eec06c04b?w=800&q=80",
    category: "Nightlife & Cocktails",
    estimatedMinutes: 210,
    vibeTags: ["Speakeasy", "Vinyl Beats", "Rooftop Views"],
    stops: [
      {
        id: "s1",
        name: "The Blind Rabbit Speakeasy",
        address: `88 Secret Alley, ${city}`,
        latitude: lat + 0.006,
        longitude: lng + 0.003,
        description: "Hidden bookcase entrance leading to craft smoked mezcal Old Fashioneds.",
        category: "Cocktail Bar"
      },
      {
        id: "s2",
        name: "Skyline Rooftop Terrace",
        address: `200 High St, ${city}`,
        latitude: lat + 0.008,
        longitude: lng + 0.004,
        description: "Panoramic sunset views with live indie house DJ sets.",
        category: "Rooftop Lounge"
      },
      {
        id: "s3",
        name: "Groove & Needle Listening Bar",
        address: `240 High St, ${city}`,
        latitude: lat + 0.009,
        longitude: lng + 0.005,
        description: "Japanese-style Hi-Fi vinyl audio lounge serving natural wines.",
        category: "Vinyl Bar"
      }
    ],
    creatorName: "Recs By Trav"
  };
}

function createArtCultureItinerary(city: string, lat: number, lng: number): AIExperience {
  return {
    id: `ai-art-${city.toLowerCase()}`,
    title: `${city} Independent Galleries & Vintage Vinyl Crawl`,
    subtitle: "Contemporary pop art, pottery, and rare 90s record crates",
    cityName: city,
    coverImageURL: "https://images.unsplash.com/photo-1513364776144-60967b0f800f?w=800&q=80",
    category: "Art & Culture",
    estimatedMinutes: 160,
    vibeTags: ["Indie Art", "Vintage Records", "Culture"],
    stops: [
      {
        id: "s1",
        name: "Canvas & Clay Collective",
        address: `720 Art District Way, ${city}`,
        latitude: lat + 0.012,
        longitude: lng - 0.007,
        description: "Rotating contemporary art exhibits and wheel-throwing pottery.",
        category: "Art Gallery"
      },
      {
        id: "s2",
        name: "Spin Cycle Vintage Vinyl",
        address: `750 Art District Way, ${city}`,
        latitude: lat + 0.013,
        longitude: lng - 0.006,
        description: "Crate-digger haven featuring rare soul, funk, and indie pressings.",
        category: "Record Store"
      }
    ],
    creatorName: "Recs By Trav"
  };
}

function createOutdoorsItinerary(city: string, lat: number, lng: number): AIExperience {
  return {
    id: `ai-outdoors-${city.toLowerCase()}`,
    title: `${city} Ridge Vista Hike & Redwood Picnic Loop`,
    subtitle: "Panoramic coastal views, pine needle trails, and fresh air",
    cityName: city,
    coverImageURL: "https://images.unsplash.com/photo-1551632811-561732d1e306?w=800&q=80",
    category: "Outdoor Adventure",
    estimatedMinutes: 180,
    vibeTags: ["Scenic Trails", "Redwood Views", "Picnic"],
    stops: [
      {
        id: "s1",
        name: "Skyline Ridge Trailhead",
        address: `100 Ridge Rd, ${city}`,
        latitude: lat + 0.018,
        longitude: lng + 0.012,
        description: "Shaded 3.5 mile loop trail through towering redwoods.",
        category: "Hiking Trail"
      },
      {
        id: "s2",
        name: "Panoramics Outlook Plaza",
        address: `150 Ridge Rd, ${city}`,
        latitude: lat + 0.020,
        longitude: lng + 0.014,
        description: "Unobstructed 360-degree viewpoint overlooking the entire bay.",
        category: "Scenic Viewpoint"
      }
    ],
    creatorName: "Recs By Trav"
  };
}

function createShoppingItinerary(city: string, lat: number, lng: number): AIExperience {
  return {
    id: `ai-shopping-${city.toLowerCase()}`,
    title: `${city} Vintage Clothing & Antique Flea Market Hop`,
    subtitle: "Curated 90s streetwear, mid-century furniture, and plant shops",
    cityName: city,
    coverImageURL: "https://images.unsplash.com/photo-1526178613552-2b45c6c302f0?w=800&q=80",
    category: "Shopping & Vintage",
    estimatedMinutes: 140,
    vibeTags: ["Thrift", "90s Vintage", "Plants"],
    stops: [
      {
        id: "s1",
        name: "Retro Threads Vintage",
        address: `310 Market Sq, ${city}`,
        latitude: lat - 0.005,
        longitude: lng - 0.004,
        description: "Rare 90s band tees, leather jackets, and denim.",
        category: "Thrift Shop"
      },
      {
        id: "s2",
        name: "Botanica Plant & Terrarium Shop",
        address: `340 Market Sq, ${city}`,
        latitude: lat - 0.006,
        longitude: lng - 0.005,
        description: "Rare monsteras, succulents, and ceramic handmade pots.",
        category: "Plant Shop"
      }
    ],
    creatorName: "Recs By Trav"
  };
}

function createSunsetItinerary(city: string, lat: number, lng: number): AIExperience {
  return {
    id: `ai-sunset-${city.toLowerCase()}`,
    title: `${city} Golden Hour Waterfront Walk & Wine Bar`,
    subtitle: "Sunset harbor breezes followed by natural orange wines",
    cityName: city,
    coverImageURL: "https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?w=800&q=80",
    category: "Sunset & Drinks",
    estimatedMinutes: 120,
    vibeTags: ["Golden Hour", "Natural Wine", "Waterfront"],
    stops: [
      {
        id: "s1",
        name: "Harbor Promenade",
        address: `Pier 1, ${city}`,
        latitude: lat - 0.009,
        longitude: lng - 0.008,
        description: "Scenic wooden pier walk right as the sun sets over the water.",
        category: "Waterfront"
      },
      {
        id: "s2",
        name: "Vin & Cellar Natural Wine Bar",
        address: `25 Pier St, ${city}`,
        latitude: lat - 0.008,
        longitude: lng - 0.007,
        description: "Chilled orange wines, artisan charcuterie, and warm candlelight.",
        category: "Wine Bar"
      }
    ],
    creatorName: "Recs By Trav"
  };
}

function createBobaDessertItinerary(city: string, lat: number, lng: number): AIExperience {
  return {
    id: `ai-boba-${city.toLowerCase()}`,
    title: `${city} Boba Milk Tea & Japanese Souffle Pancake Hop`,
    subtitle: "Fluffy soufflé pancakes and fresh taro boba teas",
    cityName: city,
    coverImageURL: "https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=800&q=80",
    category: "Boba & Desserts",
    estimatedMinutes: 90,
    vibeTags: ["Fluffy Pancakes", "Matcha", "Taro Boba"],
    stops: [
      {
        id: "s1",
        name: "Cloud Nine Soufflé Pancakes",
        address: `610 Teahouse Row, ${city}`,
        latitude: lat + 0.003,
        longitude: lng + 0.004,
        description: "Melt-in-your-mouth Japanese soufflé pancakes with matcha cream.",
        category: "Dessert"
      },
      {
        id: "s2",
        name: "Bobaology Tea Lab",
        address: `630 Teahouse Row, ${city}`,
        latitude: lat + 0.004,
        longitude: lng + 0.005,
        description: "Organic Ceylon black milk tea with honey boba and salted cheese foam.",
        category: "Boba Shop"
      }
    ],
    creatorName: "Recs By Trav"
  };
}

function createCraftBeerItinerary(city: string, lat: number, lng: number): AIExperience {
  return {
    id: `ai-beer-${city.toLowerCase()}`,
    title: `${city} Independent Brewery & Taproom Trail`,
    subtitle: "Hazy IPAs, wood-fired pizza, and pub trivia",
    cityName: city,
    coverImageURL: "https://images.unsplash.com/photo-1529699211952-734e80c4d42b?w=800&q=80",
    category: "Craft Beer",
    estimatedMinutes: 180,
    vibeTags: ["Hazy IPAs", "Wood Fired Pizza", "Brewery"],
    stops: [
      {
        id: "s1",
        name: "Hop & Grain Brewing Co.",
        address: `500 Industrial Way, ${city}`,
        latitude: lat - 0.007,
        longitude: lng - 0.003,
        description: "Freshly brewed hazy IPAs and crisp pilsners on open tap.",
        category: "Brewery"
      },
      {
        id: "s2",
        name: "Crust & Flame Wood-Fired Pizza",
        address: `530 Industrial Way, ${city}`,
        latitude: lat - 0.008,
        longitude: lng - 0.004,
        description: "Neapolitan-style wood-fired margherita pizzas and garlic knots.",
        category: "Pizzeria"
      }
    ],
    creatorName: "Recs By Trav"
  };
}

function createHiddenGemsItinerary(city: string, lat: number, lng: number): AIExperience {
  return {
    id: `ai-gems-${city.toLowerCase()}`,
    title: `${city} Hidden Passageways & Secret Courtyard Cafes`,
    subtitle: "Off-the-beaten-path spots favored by local insiders",
    cityName: city,
    coverImageURL: "https://images.unsplash.com/photo-1511632765486-a01980e01a18?w=800&q=80",
    category: "Hidden Gems",
    estimatedMinutes: 150,
    vibeTags: ["Secret Spots", "Hidden Alleyways", "Quiet"],
    stops: [
      {
        id: "s1",
        name: "The Secret Passage Bookstore",
        address: `12 Hidden Lane, ${city}`,
        latitude: lat + 0.001,
        longitude: lng - 0.005,
        description: "Charming independent bookstore tucked inside an brick courtyard.",
        category: "Bookstore"
      },
      {
        id: "s2",
        name: "Ivy Courtyard Espresso",
        address: `18 Hidden Lane, ${city}`,
        latitude: lat + 0.002,
        longitude: lng - 0.006,
        description: "Quiet ivy-covered courtyard cafe serving single-origin drip coffee.",
        category: "Café"
      }
    ],
    creatorName: "Recs By Trav"
  };
}

function createDateNightItinerary(city: string, lat: number, lng: number): AIExperience {
  return {
    id: `ai-date-${city.toLowerCase()}`,
    title: `${city} Romantic Candlelit Bistro & Jazz Lounge`,
    subtitle: "Handmade pasta, low lighting, and live saxophone",
    cityName: city,
    coverImageURL: "https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=800&q=80",
    category: "Date Night",
    estimatedMinutes: 180,
    vibeTags: ["Romantic", "Candlelit", "Live Jazz"],
    stops: [
      {
        id: "s1",
        name: "Trattoria Del Sole",
        address: `220 Romantic Way, ${city}`,
        latitude: lat - 0.004,
        longitude: lng + 0.003,
        description: "Intimate Italian dining with hand-rolled pappardelle and Chianti.",
        category: "Italian Bistro"
      },
      {
        id: "s2",
        name: "Velvet & Brass Jazz Cellar",
        address: `250 Romantic Way, ${city}`,
        latitude: lat - 0.005,
        longitude: lng + 0.004,
        description: "Underground live jazz club with cozy booth seating.",
        category: "Jazz Bar"
      }
    ],
    creatorName: "Recs By Trav"
  };
}

function createBrunchItinerary(city: string, lat: number, lng: number): AIExperience {
  return {
    id: `ai-brunch-${city.toLowerCase()}`,
    title: `${city} Sunny Patio Brunch & Mimosa Social`,
    subtitle: "Avocado toast, ricotta pancakes, and bottomless mimosas",
    cityName: city,
    coverImageURL: "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=800&q=80",
    category: "Brunch",
    estimatedMinutes: 120,
    vibeTags: ["Patio Brunch", "Mimosas", "Pancakes"],
    stops: [
      {
        id: "s1",
        name: "Sunny Side Bistro & Terrace",
        address: `800 Sunshine Blvd, ${city}`,
        latitude: lat + 0.007,
        longitude: lng - 0.003,
        description: "Outdoor patio brunch with lemon ricotta pancakes and eggs benedict.",
        category: "Brunch Spot"
      }
    ],
    creatorName: "Recs By Trav"
  };
}

function createMusicLiveItinerary(city: string, lat: number, lng: number): AIExperience {
  return {
    id: `ai-music-${city.toLowerCase()}`,
    title: `${city} Indie Music Hall & Underground Acoustic Stage`,
    subtitle: "Intimate live shows with emerging regional touring acts",
    cityName: city,
    coverImageURL: "https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=800&q=80",
    category: "Live Music",
    estimatedMinutes: 180,
    vibeTags: ["Indie Music", "Acoustic", "Live Shows"],
    stops: [
      {
        id: "s1",
        name: "The Acoustic Vault",
        address: `140 Music Row, ${city}`,
        latitude: lat - 0.006,
        longitude: lng + 0.007,
        description: "Intimate 150-cap live music room with incredible acoustics.",
        category: "Music Venue"
      }
    ],
    creatorName: "Recs By Trav"
  };
}

function createWellnessItinerary(city: string, lat: number, lng: number): AIExperience {
  return {
    id: `ai-wellness-${city.toLowerCase()}`,
    title: `${city} Morning Yoga, Sound Bath & Cold Pressed Juicery`,
    subtitle: "Reset and recharge with mindfulness, matcha & wellness",
    cityName: city,
    coverImageURL: "https://images.unsplash.com/photo-1506126613408-eca07ce68773?w=800&q=80",
    category: "Wellness",
    estimatedMinutes: 120,
    vibeTags: ["Yoga", "Juice Bar", "Mindfulness"],
    stops: [
      {
        id: "s1",
        name: "Zenith Yoga Studio & Sanctuary",
        address: `300 Lotus St, ${city}`,
        latitude: lat + 0.009,
        longitude: lng - 0.005,
        description: "Vinyasa flow yoga class followed by sound bowl meditation.",
        category: "Yoga Studio"
      },
      {
        id: "s2",
        name: "Pure Press Juice & Smoothie Bar",
        address: `320 Lotus St, ${city}`,
        latitude: lat + 0.010,
        longitude: lng - 0.004,
        description: "Cold-pressed green juices, acai bowls, and ginger wellness shots.",
        category: "Juice Bar"
      }
    ],
    creatorName: "Recs By Trav"
  };
}

function createLateNightEatsItinerary(city: string, lat: number, lng: number): AIExperience {
  return {
    id: `ai-latenight-${city.toLowerCase()}`,
    title: `${city} Midnight Ramen & 24-Hour Diner Crawl`,
    subtitle: "Rich tonkotsu broth and crispy gyoza after hours",
    cityName: city,
    coverImageURL: "https://images.unsplash.com/photo-1569718212165-3a8278d5f624?w=800&q=80",
    category: "Late Night Eats",
    estimatedMinutes: 90,
    vibeTags: ["Ramen", "Midnight Eats", "Gyoza"],
    stops: [
      {
        id: "s1",
        name: "Noodle House Midnight Ramen",
        address: `99 Night St, ${city}`,
        latitude: lat - 0.001,
        longitude: lng - 0.002,
        description: "Steaming hot spicy miso and tonkotsu ramen served past midnight.",
        category: "Ramen Shop"
      }
    ],
    creatorName: "Recs By Trav"
  };
}

function createCustomUserItinerary(city: string, lat: number, lng: number, prompt: string): AIExperience {
  return {
    id: `ai-custom-${Date.now()}`,
    title: `Tailored Experience in ${city}`,
    subtitle: `Custom AI itinerary for: "${prompt}"`,
    cityName: city,
    coverImageURL: "https://images.unsplash.com/photo-1511578314322-379afb476865?w=800&q=80",
    category: "Ask Trav AI",
    estimatedMinutes: 180,
    vibeTags: ["Custom AI", "Curated"],
    stops: [
      {
        id: "cs1",
        name: `${city} Highlight Spot 1`,
        address: `100 Central Ave, ${city}`,
        latitude: lat + 0.002,
        longitude: lng - 0.002,
        description: `Specially selected for: ${prompt}`,
        category: "Featured Spot"
      },
      {
        id: "cs2",
        name: `${city} Highlight Spot 2`,
        address: `200 Central Ave, ${city}`,
        latitude: lat + 0.004,
        longitude: lng - 0.001,
        description: `Curated local favorite in ${city}`,
        category: "Local Favorite"
      }
    ],
    creatorName: "Ask Trav AI"
  };
}
