# Trav Onboarding Flow - Design & Implementation Guide

## Overview

This document outlines the complete progressive disclosure onboarding flow introduced to the Trav app. The flow is modern, minimalist, photo-centric, and travel-focused.

## Architecture

The new onboarding flow is entirely contained in `/Trav/Features/Onboarding/` and follows a **NavigationStack-based progressive disclosure pattern**. Each step guides users through one focused action, keeping the main content in the top half and a sticky primary button at the bottom.

### File Structure
```
Trav/Features/Onboarding/
├── OnboardingView.swift          # Main container with NavigationStack
├── AuthEntryView.swift           # Step 1: Email/Phone entry
├── VibeSelectionView.swift       # Step 2: Travel style selection
├── LocationContextView.swift     # Step 3: Location selection
├── SocialSyncView.swift          # Step 4: Social/contacts sync
└── PremiumTeaseView.swift        # Step 5: Premium subscription tease
```

## Flow Steps

### 1. AuthEntryView (Auth Entry)
**Purpose:** Collect user contact information

**Features:**
- Clean title: "Let's get exploring."
- Input field for email or phone with animated bottom border
- Border highlights in accent color when input is valid
- "Continue" button (disabled until text entered)
- Helper text: "We'll verify your contact info in the next step."

**UI Elements:**
- X button to dismiss (top-left)
- Animated appearance with `.travAppear()` modifier
- Uses existing `TravTextField` component

### 2. VibeSelectionView (Vibe Selection)
**Purpose:** Understand user travel preferences

**Features:**
- Title: "What's your travel style?"
- Subtitle: "Select the experiences you love."
- Grid of pill-shaped toggle buttons (8 options):
  - Hidden Cafes
  - Underground Nightlife
  - Scenic Views
  - Vintage Shopping
  - Street Art
  - Local Markets
  - Rooftop Bars
  - Nature Trails
- Tapping a pill highlights it with accent color and fills background
- Shows count of selected vibes: "X vibes selected"
- "Continue" button (enabled only with selections)

**UI Elements:**
- Back button (chevron.left + "Back" text)
- Custom `VibeSelectionChip` component
- 2-column grid layout
- Animated transitions

### 3. LocationContextView (Location Context)
**Purpose:** Determine user travel destination

**Features:**
- Title: "Where are you looking to go?"
- Subtitle: "We'll find the best local gems nearby."
- Search bar with magnifying glass icon
- "Use my current location" prominent row with map pin icon
- List of 10 popular cities:
  - New York, Tokyo, Barcelona, Paris, Bangkok
  - London, Dubai, Amsterdam, Singapore, Sydney
- Checkmark indicator for selected location
- Shows selected destination: "Heading to [Location]"

**UI Elements:**
- Back button
- Search functionality (filters city list in real-time)
- Custom radio-button-like selection UI
- Animated accent color transitions

### 4. SocialSyncView (Social / Sync)
**Purpose:** Enable social discovery features

**Features:**
- Large, soft-colored vector graphic (person.2.fill icon)
- Headline: "Find where your friends are hanging out."
- Description: "Connect your contacts to see where friends are exploring and get personalized recommendations based on their favorite spots."
- Primary "Allow Contacts" button (with loading state)
- "Skip for now" secondary button

**UI Elements:**
- Back button
- Icon in accent soft background circle
- Simulated contact access flow (1-second delay for demo)
- Clean typography hierarchy

### 5. PremiumTeaseView (Premium Subscription Tease)
**Purpose:** Introduce Trav Pro premium features

**Features:**
- Large, prominent premium icon (sparkles) with gradient background
- Title: "Trav Pro"
- Three premium features with icons:
  1. ✨ Curated Itineraries - "Hand-picked travel plans tailored to your style"
  2. 🎬 TikTok-Inspired Plans - "Trending experiences and viral-worthy moments"
  3. 🗺️ Unlimited Gems - "Access to all hidden local recommendations"
- Primary "View Plans" button
- Secondary "Start exploring for free" button
- X dismiss button (top-right)

**UI Elements:**
- Feature rows with icons and descriptions
- Soft accent background for feature list
- Gradient-styled premium icon container

## Integration Points

### Entry Point
The onboarding flow is triggered when users click the "Sign In" button on the `GlobeLandingView`. This uses a `@State` boolean (`showOnboarding`) and a `fullScreenCover` modifier:

```swift
@State private var showOnboarding = false

.fullScreenCover(isPresented: $showOnboarding) {
    OnboardingView()
}
```

### Exit Points
- **AuthEntryView**: X button dismisses via `onDismiss` callback
- **VibeSelectionView - PremiumTeaseView**: Back button navigates to previous step
- **PremiumTeaseView**: 
  - X button dismisses the entire flow
  - "Start exploring for free" button dismisses the flow

### Data Flow
The `OnboardingView` manages state for:
- `authInput: String` - Email/phone from AuthEntryView
- `selectedVibes: Set<String>` - Travel style preferences
- `selectedLocation: String?` - Selected destination
- `navigationPath: NavigationPath` - Navigation state management

## Design System Integration

All views use the existing Trav design system:

**Typography:**
- `TravTypography.displayMedium()` - Section titles
- `TravTypography.titleLarge()` - Feature titles
- `TravTypography.bodyMedium()` - Body text
- `TravTypography.labelMedium()` - Button labels and helper text
- `TravTypography.caption()` - Fine print and counters

**Colors:**
- `TravColors.primary` - Text and primary UI elements
- `TravColors.accent` - Active/selected states (vibrant coral)
- `TravColors.accentSoft` - Soft background for features
- `TravColors.surface` - Main background
- `TravColors.surfaceElevated` - Input field and chip backgrounds
- `TravColors.muted` - Disabled states and secondary text

**Spacing:**
- `TravSpacing.screenHorizontal` - Screen padding (20pt)
- `TravSpacing.lg` - Large section spacing (24pt)
- `TravSpacing.md` - Standard spacing (16pt)
- `TravSpacing.sm` - Compact spacing (12pt)

**Animations:**
- `TravAnimation.quick` - Fast transitions (0.18s)
- `TravAnimation.enter` - Modal entry animation (0.45s)
- Staggered appears with `.travAppear(delay:)` modifier

**Buttons:**
- `PrimaryButton` - Accent-colored, wide format with text
- `SecondaryButton` - Outline style buttons
- Custom `VibeSelectionChip` - Toggle buttons for selections
- `.travPressButtonStyle()` - Subtle scale animation on press

## Progressive Disclosure Pattern

Each screen follows the progressive disclosure principle:

1. **One focus per screen** - Only one primary decision/input
2. **Clear hierarchy** - Title, content, action at bottom
3. **Sticky primary button** - Always visible for quick action
4. **Lazy evaluation** - Continue button only enabled when requirements met
5. **Clear progression** - Back button always available (except entry point)
6. **Staggered animations** - Elements fade in with delay for polish

## Existing Features Preserved

The implementation does **NOT** modify:
- Existing `AuthSheetView` (still available via `router.presentAuth()`)
- `GlobeLandingView` visual design or layout
- Existing login logic or authentication flow
- Tab navigation or other app features

### Backward Compatibility
If needed, the old auth sheet can still be accessed via:
```swift
router.presentAuth() // Shows AuthSheetView in sheet
```

The new onboarding flow uses:
```swift
showOnboarding = true // Shows OnboardingView in fullScreenCover
```

## Customization Points

### Vibe Options
Edit the `vibes` array in `VibeSelectionView`:
```swift
let vibes = [
    "Hidden Cafes",
    "Underground Nightlife",
    // ... add/remove options
]
```

### Location List
Edit the `popularCities` array in `LocationContextView`:
```swift
let popularCities = [
    "New York",
    "Tokyo",
    // ... add/remove cities
]
```

### Feature Descriptions
Edit feature rows in `PremiumTeaseView`:
```swift
PremiumFeatureRow(
    icon: "sparkles",
    title: "Curated Itineraries",
    description: "Hand-picked travel plans..."
)
```

## Mock Behavior Notes

Current implementations use mock behavior:
- Contact sync has 1-second simulated delay
- No actual premium subscription integration
- Location is stored but not used for backend queries
- Vibes are collected but not persisted

These should be integrated with actual backend services in production.

## Testing Considerations

### Preview Support
All views include SwiftUI `#Preview` blocks for Xcode preview canvas.

### State Management
- Views use `@Binding` for parent-child communication
- `NavigationStack` manages forward/backward navigation
- `@State` in `OnboardingView` maintains cross-step state

### Accessibility
- Back buttons have semantic labels
- Buttons use standard styles for proper hit targets (min 44pt)
- Text contrast meets WCAG standards
- Color is not the only indicator (checkmarks paired with fill colors)

## Future Enhancements

1. **Analytics Integration** - Track step completion rates
2. **Persistence** - Save user preferences across sessions
3. **Conditional Steps** - Skip steps based on auth method (phone vs email)
4. **A/B Testing** - Variants of vibes/cities
5. **Dynamic Content** - Populate cities from backend based on popularity
6. **Social Integration** - Real contacts sync with actual permissions flow
7. **Premium Upgrade** - Complete subscription purchase flow
8. **Onboarding Analytics** - Funnel metrics for drop-off rates

## Notes

- All views follow modern SwiftUI best practices with `@Observable` support
- Animations are GPU-efficient using built-in SwiftUI animation APIs
- Dark mode is fully supported through TravColors system
- Images use system SF Symbols for consistency
- Proper view lifecycle management with `.navigationBarBackButtonHidden()` on intermediate steps
