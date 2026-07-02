# Trav — Design System

Premium consumer aesthetic inspired by Apple, Airbnb, Beli, and Linear.

---

## Brand

| Token | Value | Usage |
|-------|-------|-------|
| Primary | `#0A0A0B` | Text, dark backgrounds |
| Accent | `#FF5C35` | CTAs, active states, globe city glow |
| Accent Soft | `#FF5C35` @ 12% | Subtle highlights |
| Surface | `#FFFFFF` | Cards, sheets |
| Surface Elevated | `#F7F7F8` | Secondary backgrounds |
| Border | `#E8E8EA` | Dividers (use sparingly) |
| Success | `#22C55E` | Completion badge |
| Muted | `#6B6B70` | Secondary text |

Dark mode inverts surfaces; accent remains consistent.

---

## Typography

**Font family**: SF Pro (system) with semantic styles.

| Style | Size | Weight | Tracking | Use |
|-------|------|--------|----------|-----|
| `displayLarge` | 34 | Bold | -0.4 | City hero titles |
| `displayMedium` | 28 | Bold | -0.3 | Experience titles |
| `titleLarge` | 22 | Semibold | -0.2 | Section headers |
| `titleMedium` | 17 | Semibold | -0.1 | Card titles |
| `bodyLarge` | 17 | Regular | 0 | Primary body |
| `bodyMedium` | 15 | Regular | 0 | Descriptions |
| `labelMedium` | 13 | Medium | 0.2 | Metadata, caps labels |
| `caption` | 12 | Regular | 0.3 | Timestamps, counts |

Line height: 1.25 for titles, 1.45 for body.

---

## Spacing

4pt base grid.

| Token | Value |
|-------|-------|
| `xxs` | 4 |
| `xs` | 8 |
| `sm` | 12 |
| `md` | 16 |
| `lg` | 24 |
| `xl` | 32 |
| `xxl` | 48 |
| `hero` | 64 |

Screen horizontal padding: **20pt** (compact), **24pt** (regular).

---

## Radius

| Token | Value | Use |
|-------|-------|-----|
| `sm` | 8 | Chips, small buttons |
| `md` | 12 | Input fields |
| `lg` | 16 | Cards |
| `xl` | 24 | Hero images, sheets |
| `full` | 999 | Avatars, pills |

---

## Shadows

Minimal — prefer elevation via background contrast.

| Level | Shadow |
|-------|--------|
| Card | `0 2px 8px rgba(0,0,0,0.06)` |
| Floating | `0 8px 32px rgba(0,0,0,0.12)` |

---

## Components

### RoutePreview

Vertical stop list with emoji, connector line, and truncated labels. **Signature Trav element.**

```
☕ Blue Bottle
│
📚 City Lights Books
│
🍜 Ippudo
│
🌃 Twin Peaks
```

### ExperienceCard

- 4:5 cover image, rounded `lg`
- Title + creator row
- Metadata row: duration · cost · saves · completions
- RoutePreview embedded at bottom

### StatPill

Icon + count in capsule (`Surface Elevated`, `caption` text).

### PrimaryButton

Full-width, accent fill, 52pt height, `md` radius, subtle press scale (0.97).

### Avatar

Circle, sizes: 32 / 40 / 56 / 80. Ring on story-style contexts.

### Skeleton

Shimmer gradient animation matching component geometry.

---

## Motion

| Interaction | Duration | Curve |
|-------------|----------|-------|
| Screen push | 0.35s | easeInOut |
| Sheet present | 0.4s | spring(0.85, 0.78) |
| Globe fly-to | 1.2s | easeInOut |
| Button press | 0.15s | easeOut |
| Card appear | 0.3s | stagger 0.05s |

Haptics: light impact on save, success on completion, medium on city tap.

---

## Iconography

SF Symbols primary. Custom only for route connector if needed.

Common symbols:
- Save: `bookmark`
- Complete: `checkmark.circle.fill`
- Share: `square.and.arrow.up`
- Duration: `clock`
- Cost: `dollarsign.circle`
- Distance: `figure.walk`

---

## Layout Patterns

### City Page

1. Full-bleed hero (380pt) with gradient scrim
2. Floating stats overlay
3. Featured experience — horizontal card, edge-to-edge image
4. Masonry feed — 2 columns, variable height

### Experience Page

1. Parallax hero
2. Sticky action bar (save, complete, share)
3. Route overview card
4. Map section (280pt min height)
5. Timeline stops — full-bleed media alternating
6. Completion gallery grid
7. Comments
8. Similar experiences carousel

---

## Accessibility

- Dynamic Type supported on all text styles
- Minimum touch target: 44×44pt
- VoiceOver labels on all interactive elements
- Reduce Motion: disable parallax and shorten globe animations
