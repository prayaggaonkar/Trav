# Trav Onboarding - Visual & Technical Flow

## 🎯 Screen Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│               GlobeLandingView (Home Page)                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                                                     │   │
│  │              🌍 Earth Globe Animation              │   │
│  │              (unchanged, preserved)                │   │
│  │                                                     │   │
│  │         "What should you do today?"                │   │
│  │         [Sign In Button] ◀─────┐                   │   │
│  │                                 │                   │   │
│  │         [City Chips at bottom]  │                   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ showOnboarding = true
                            │ (fullScreenCover)
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                 OnboardingView Container                    │
│              (NavigationStack with 5 steps)                 │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐  │
│  │        AuthEntryView (Step 1/5)                    │  │
│  │  ┌─────────────────────────────────────────────┐  │  │
│  │  │ [X]                                         │  │  │
│  │  │                                             │  │  │
│  │  │ Let's get exploring.                        │  │  │
│  │  │ Enter your email or phone to start.         │  │  │
│  │  │                                             │  │  │
│  │  │ ┌──────────────────────────────────────┐  │  │  │
│  │  │ │ you@example.com                      │  │  │  │
│  │  │ └──────────────────────────────────────┘  │  │  │
│  │  │                                             │  │  │
│  │  │            ┌──────────────────┐            │  │  │
│  │  │            │   [Continue]     │            │  │  │
│  │  │            └──────────────────┘            │  │  │
│  │  └─────────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ navigationPath.append(.vibeSelection)
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              VibeSelectionView (Step 2/5)                  │
│  ┌─────────────────────────────────────────────────────┐  │
│  │ [< Back]                                            │  │
│  │                                                     │  │
│  │ What's your travel style?                          │  │
│  │ Select the experiences you love.                   │  │
│  │                                                     │  │
│  │ ┌──────────────┐  ┌──────────────┐                │  │
│  │ │ Hidden Cafes │  │Underground   │                │  │
│  │ │              │  │Nightlife     │                │  │
│  │ └──────────────┘  └──────────────┘                │  │
│  │ ┌──────────────┐  ┌──────────────┐                │  │
│  │ │Scenic Views  │  │Vintage Shop  │                │  │
│  │ │    (ACTIVE)  │  │              │                │  │
│  │ └──────────────┘  └──────────────┘                │  │
│  │ ┌──────────────┐  ┌──────────────┐                │  │
│  │ │ Street Art   │  │Local Markets │                │  │
│  │ └──────────────┘  └──────────────┘                │  │
│  │ ┌──────────────┐  ┌──────────────┐                │  │
│  │ │Rooftop Bars  │  │Nature Trails │                │  │
│  │ └──────────────┘  └──────────────┘                │  │
│  │                                                     │  │
│  │            ┌──────────────────┐                   │  │
│  │            │   [Continue]     │                   │  │
│  │            └──────────────────┘                   │  │
│  │     1 vibe selected (caption)                     │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ navigationPath.append(.locationContext)
                            ▼
┌─────────────────────────────────────────────────────────────┐
│            LocationContextView (Step 3/5)                  │
│  ┌─────────────────────────────────────────────────────┐  │
│  │ [< Back]                                            │  │
│  │                                                     │  │
│  │ Where are you looking to go?                       │  │
│  │ We'll find the best local gems nearby.             │  │
│  │                                                     │  │
│  │ ┌──────────────────────────────────────────────┐  │  │
│  │ │ 🔍 Search cities...                          │  │  │
│  │ └──────────────────────────────────────────────┘  │  │
│  │                                                     │  │
│  │ ┌──────────────────────────────────────────────┐  │  │
│  │ │ 📍 Use my current location        [○]        │  │  │
│  │ │    Enable location access                    │  │  │
│  │ └──────────────────────────────────────────────┘  │  │
│  │                                                     │  │
│  │ ┌──────────────────────────────────────────────┐  │  │
│  │ │ 📍 New York                                  │  │  │
│  │ └──────────────────────────────────────────────┘  │  │
│  │ ┌──────────────────────────────────────────────┐  │  │
│  │ │ 📍 Tokyo                       [✓ SELECTED] │  │  │
│  │ └──────────────────────────────────────────────┘  │  │
│  │ ┌──────────────────────────────────────────────┐  │  │
│  │ │ 📍 Barcelona                                 │  │  │
│  │ └──────────────────────────────────────────────┘  │  │
│  │ [... more cities ...]                              │  │
│  │                                                     │  │
│  │            ┌──────────────────┐                   │  │
│  │            │   [Continue]     │                   │  │
│  │            └──────────────────┘                   │  │
│  │         Heading to Tokyo (caption)                │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ navigationPath.append(.socialSync)
                            ▼
┌─────────────────────────────────────────────────────────────┐
│             SocialSyncView (Step 4/5)                      │
│  ┌─────────────────────────────────────────────────────┐  │
│  │ [< Back]                                            │  │
│  │                                                     │  │
│  │                   ┌─────────┐                      │  │
│  │                   │ ⭐⭐⭐  │                      │  │
│  │                   │  👫     │                      │  │
│  │                   └─────────┘                      │  │
│  │                                                     │  │
│  │ Find where your friends are hanging out.          │  │
│  │                                                     │  │
│  │ Connect your contacts to see where friends        │  │
│  │ are exploring and get personalized                │  │
│  │ recommendations based on their favorite spots.    │  │
│  │                                                     │  │
│  │            ┌──────────────────┐                   │  │
│  │            │ [Allow Contacts] │  ⏳               │  │
│  │            └──────────────────┘                   │  │
│  │                                                     │  │
│  │            Skip for now (button)                  │  │
│  │                                                     │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
         ┌──────────────────┼──────────────────┐
         │                  │                  │
         │ [Allow]          │ [Skip]           │ [< Back]
         │ (after delay)    │                  │
         ▼                  ▼                  ▼
   [Continue]            [Continue]     (back to LocationView)
         │                  │
         └──────────────────┴──────────────────┐
                            │
                            │ navigationPath.append(.premiumTease)
                            ▼
┌─────────────────────────────────────────────────────────────┐
│            PremiumTeaseView (Step 5/5)                     │
│  ┌─────────────────────────────────────────────────────┐  │
│  │                                              [X]    │  │
│  │                                                     │  │
│  │                   ┌─────────┐                      │  │
│  │                   │ ✨      │                      │  │
│  │                   │ sparkle │                      │  │
│  │                   └─────────┘                      │  │
│  │                                                     │  │
│  │               Trav Pro                             │  │
│  │                                                     │  │
│  │ ┌─────────────────────────────────────────────┐   │  │
│  │ │ ✨ Curated Itineraries                      │   │  │
│  │ │    Hand-picked travel plans...              │   │  │
│  │ │ 🎬 TikTok-Inspired Plans                    │   │  │
│  │ │    Trending experiences...                  │   │  │
│  │ │ 🗺️ Unlimited Gems                           │   │  │
│  │ │    Access to all hidden recommendations     │   │  │
│  │ └─────────────────────────────────────────────┘   │  │
│  │                                                     │  │
│  │            ┌──────────────────┐                   │  │
│  │            │   [View Plans]   │                   │  │
│  │            └──────────────────┘                   │  │
│  │                                                     │  │
│  │        Start exploring for free (button)          │  │
│  │                                                     │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                    ┌───────┴───────┐
                    │               │
         [View Plans]    [Start Free]
         or [X]         or [X]
                    │               │
                    └───────┬───────┘
                            │
                            │ router.dismissAuth()
                            ▼
┌─────────────────────────────────────────────────────────────┐
│            Back to GlobeLandingView (Home)                 │
│  - Authenticated user can now access features              │
│  - All collected data available for personalization        │
│  - Vibes, location, and contacts synced                   │
└─────────────────────────────────────────────────────────────┘
```

## 📊 State Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    OnboardingView State                     │
│                                                             │
│  @State navigationPath: NavigationPath                     │
│  @State selectedVibes: Set<String>                         │
│  @State selectedLocation: String?                          │
│  @State authInput: String                                  │
│                                                             │
│  ┌───────────────────────────────────────────────────┐     │
│  │  NavigationStack(path: $navigationPath)          │     │
│  │  ├─ AuthEntryView                                │     │
│  │  │  └─ onContinue:                               │     │
│  │  │     navigationPath.append(.vibeSelection)     │     │
│  │  │                                               │     │
│  │  ├─ VibeSelectionView                            │     │
│  │  │  ├─ onContinue:                               │     │
│  │  │  │  navigationPath.append(.locationContext)  │     │
│  │  │  └─ onBack:                                   │     │
│  │  │     navigationPath.removeLast()               │     │
│  │  │                                               │     │
│  │  ├─ LocationContextView                          │     │
│  │  │  ├─ onContinue:                               │     │
│  │  │  │  navigationPath.append(.socialSync)       │     │
│  │  │  └─ onBack:                                   │     │
│  │  │     navigationPath.removeLast()               │     │
│  │  │                                               │     │
│  │  ├─ SocialSyncView                               │     │
│  │  │  ├─ onContinue:                               │     │
│  │  │  │  navigationPath.append(.premiumTease)     │     │
│  │  │  ├─ onSkip:                                   │     │
│  │  │  │  navigationPath.append(.premiumTease)     │     │
│  │  │  └─ onBack:                                   │     │
│  │  │     navigationPath.removeLast()               │     │
│  │  │                                               │     │
│  │  └─ PremiumTeaseView                             │     │
│  │     └─ onDismiss:                                │     │
│  │        router.dismissAuth()                      │     │
│  └───────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

## 🎬 Animation Timeline (per screen)

### AuthEntryView
```
t=0ms    t=100ms  t=200ms  t=250ms
│        │        │        │
Title ◄──────────────────────
Subtitle ◄──────────────────────
Input ◄────────────────────────────
Continue Button ◄──────────────────────────
Helper Text ◄────────────────────────────────
```

### VibeSelectionView
```
t=0ms    t=50ms   t=100ms  t=150ms  t=200ms  t=250ms
│        │        │        │        │        │
Title ◄──────────────────────────────
Vibes (grid) ◄──────┬──────┬──────┬──────┬──────
               Chip0 Chip1 Chip2 Chip3 Chip4...
Continue Button ◄──────────────────────────────────
Count ◄─────────────────────────────────────────────
```

### LocationContextView
```
t=0ms    t=100ms  t=150ms  t=200ms  t=250ms
│        │        │        │        │
Title ◄──────────────────────────────
Search ◄────────────────────────────────
Current Loc ◄───────────────────────────────
Cities ◄──────────────────────────────────────
Continue ◄─────────────────────────────────────
```

## 🔄 Navigation State Machine

```
    START
      │
      ▼
    [1] AuthEntry (initial)
    /    \
  Back    Continue
  /        \
X           ▼
    [2] VibeSelection
        /    \
      Back    Continue
      /        \
    [1]         ▼
              [3] LocationContext
                  /    \
                Back    Continue
                /        \
              [2]         ▼
                        [4] SocialSync
                            /    \    \
                          Back   Skip  Continue
                          /      |      \
                        [3]     [5]     ▼
                                   [5] PremiumTease
                                       /    \    \
                                  ViewPlan  Start  X
                                     |       |     |
                                    END     END   END
```

## 📱 Screen Dimensions & Layouts

### All Screens Follow Pattern
```
┌────────────────────────────────────────┐
│ Header (44pt)                          │
│ [Back/Close Button]                    │
├────────────────────────────────────────┤
│                                        │
│ ScrollView Content                     │
│ ├─ Title                               │
│ ├─ Subtitle                            │
│ ├─ Main Content (variable)             │
│ │                                      │
│                                        │
│                                        │
├────────────────────────────────────────┤
│ Fixed Bottom Section                   │
│ ├─ Primary Button (52pt)               │
│ └─ Helper Text                         │
└────────────────────────────────────────┘
```

## 🎨 Color Transitions

### Input Validation (AuthEntryView)
```
Empty State → Has Text
  │            │
  ├─ Border color
  └─ .border(0.5)  → accent

Focus State
  ├─ Grows in opacity
  └─ Animates with .quick (0.18s)
```

### Selection State (All Selection Views)
```
Unselected → Selected (on tap)
   │            │
   ├─ Background
   └─ .surfaceElevated  → .accent
   ├─ Text color
   └─ .primary  → .white
   ├─ Border
   └─ .border  → .clear
   
Animation: .quick (0.18s easeOut)
```

---

**Note:** All animations use TravAnimation system for consistency
**All colors use TravColors system for dark mode support**
