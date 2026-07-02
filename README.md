# Trav

A native iOS social platform for discovering, sharing, and recreating real-world experiences.

## Requirements

- Xcode 16+ (tested with Xcode 26)
- iOS 17.0+
- Swift 6

## Getting Started

1. Open `Trav.xcodeproj` in Xcode
2. Select the **Trav** scheme and an iPhone simulator
3. Build and run (⌘R)

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full system design.

- [Database Schema](docs/DATABASE_SCHEMA.md)
- [Design System](docs/DESIGN_SYSTEM.md)

## Configuration

Copy `Trav/Resources/Secrets.example.xcconfig` to `Secrets.xcconfig` and add your Supabase and Google OAuth credentials. The app runs with mock data when secrets are not configured.

## Project Structure

```
Trav/
├── App/           # Entry point, routing, environment
├── Core/          # Models, repositories, services
├── DesignSystem/  # Theme, typography, components
├── Features/      # Feature modules (Globe, City, Experience, …)
└── Resources/     # Assets, textures, localization
```

## License

Proprietary — All rights reserved.
