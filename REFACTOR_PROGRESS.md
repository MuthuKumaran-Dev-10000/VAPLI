# Refactor Progress

## Completed
- Moved all files from legacy `lib/data` and `lib/presentation/screens` into `lib/features/*`.
- Kept `lib/core/*` as shared foundation.
- Updated `main.dart` imports to new feature paths.
- Rewrote stale imports across moved files.
- Verified all relative imports resolve to existing files.

## In Place (Behavior-preserving, not yet deep-split)
- Large files are still present but now feature-isolated:
  - `property_builder_page.dart`
  - `reading_entry_screen.dart`
  - `dashboard_tab.dart`
  - `tank_browser_screen.dart`
  - `trends_screen.dart`

## Next Incremental Steps
1. Extract controllers from each 2k+ LOC file.
2. Move Firebase logic from UI pages into feature repositories/services where still inline.
3. Add feature route files and app-level route registry.
4. Introduce Riverpod providers feature-by-feature (starting with auth, then dashboard, then readings, then tanks).
5. Add targeted tests on refactored services/repositories.

