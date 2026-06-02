# InkSlate

**InkSlate** is a minimalist iOS app that brings notes, budgeting, journaling, recipes, and more into one calm place—without clutter.

[Privacy Policy](https://sirlwaldron.github.io/InkSlate/privacy.html) · [Terms of Use](https://sirlwaldron.github.io/InkSlate/terms.html)

---

## What is InkSlate?

Open the app to a simple home screen, then jump into the tools you need from the circular menu. Everything is designed to stay out of your way: light typography, consistent layout, and optional **iCloud sync** so your data can follow you across iPhone and iPad (when you’re signed into iCloud).

Your content stays on your device and in your personal iCloud account—we don’t run our own servers for your notes or journals.

---

## Free vs InkSlate Pro

| Free (always) | InkSlate Pro |
|---------------|--------------|
| Home | Mind Maps |
| Notes (markdown, tags, projects) | Journal (prompts, streaks) |
| Budget | To-Do |
| Calendar | Recipes (pantry, cook mode) |
| Settings & Profile | Places |
| | Quotes |
| | Watchlist (movies & TV) |

**iCloud sync** is available whether you’re on the free tier or Pro.

Pro is available as monthly or yearly subscriptions (7-day free trial) or a one-time lifetime purchase. Manage or restore purchases in **Settings**.

---

## Features at a glance

**Notes** — Markdown editing, folders and tags, search, pinning, photos, and share/import support.

**Budget** — Track spending by category and subcategory.

**Calendar** — View and work with your calendar from inside the app (with your permission).

**Journal** — Multiple journals, writing prompts, word count, and streak tracking. *(Pro)*

**To-Do** — Tasks and lists. *(Pro)*

**Recipes** — Save recipes, pantry and shopping lists, timers in cook mode. *(Pro)*

**Places** — Remember spots you love—ratings, photos, visit notes. *(Pro)*

**Quotes** — Collect quotes by category. *(Pro)*

**Watchlist** — Search movies and shows via [TMDB](https://www.themoviedb.org/); build your watch list. *(Pro)*

**Mind Maps** — Brainstorm visually. *(Pro)*

**Settings** — Themes, notifications, CloudKit sync status, factory reset, and subscription management.

---

## Privacy & data

- Data is stored **locally** with Core Data.
- **iCloud (CloudKit)** sync is optional and uses your Apple ID.
- The **Watchlist** feature loads public movie/TV metadata from TMDB ([their privacy policy](https://www.themoviedb.org/privacy-policy)).
- Optional **passcode** protection for sensitive notes (your PIN is not stored in the app).
- Hosted legal pages live in [`docs/`](docs/) for GitHub Pages.

---

## Requirements

- **iOS 18.5** or later
- Xcode **16** or later (for building from source)

---

## Build from source

1. Clone the repo:
   ```bash
   git clone https://github.com/sirlwaldron/InkSlate.git
   cd InkSlate
   ```
2. Open `InkSlate.xcodeproj` in Xcode.
3. Select the **InkSlate** scheme and run on a simulator or device.

**StoreKit testing:** The scheme uses `InkSlate.storekit` for local subscription testing.

**Watchlist (optional):** Set `TMDB_API_KEY` in the scheme environment or Info.plist, or use the default read-only key in `InkSlate/Services/TMDBConfig.swift`.

**Share extension:** `InkSlateShareExtension` lets you send content into InkSlate from other apps.

---

## Project layout

```
InkSlate/
├── Core/              App shell, design system, persistence
├── Models/            Core Data helpers
├── Services/          CloudKit assets, subscriptions, TMDB, etc.
├── Views/             Feature screens (Notes, Budget, Journal, …)
├── ShareImport/       Shared content handling
└── InkSlate.xcdatamodeld/

InkSlateShareExtension/   Share sheet target
docs/                     Privacy & terms (GitHub Pages)
```

Built with **SwiftUI**, **Core Data**, and **CloudKit**.

---

## Contributing

Issues and pull requests are welcome. For larger changes, open an issue first so we can align on direction.

---

## License

MIT — see [LICENSE](LICENSE).

---

## Support

Questions or bugs? [Open an issue](https://github.com/sirlwaldron/InkSlate/issues) on GitHub.
