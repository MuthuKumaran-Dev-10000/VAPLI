# AI Refactor Tracker

Updated: 2026-05-22 (latest pass #2)

## Completed in code

1. Feature-first structure already applied under `lib/features/*`.
2. Auth login orchestration centralized:
   - Added `lib/features/auth/presentation/controllers/auth_controller.dart`
   - `login_screen.dart` now calls controller instead of repository directly.
   - `admin_login.dart` now uses the same controller (`loginAdmin`).
3. Login UI split into reusable small widgets:
   - `lib/features/auth/presentation/widgets/auth_brand_header.dart`
   - `lib/features/auth/presentation/widgets/login_error_banner.dart`
4. `home_screen.dart` split:
   - QR scan screen extracted to `lib/features/home/presentation/pages/qr_scan_screen.dart`
   - Removed inline QR scan class from `home_screen.dart`.
5. Large-file structural split (behavior-preserving) using Dart `part` files:
   - `reading_entry_screen.dart` + `reading_entry_components.dart`
   - `dashboard_tab.dart` + `dashboard_tab_components.dart`
   - `tank_browser_screen.dart` + `tank_browser_components.dart`
   - `property_builder_page.dart` + `property_builder_components.dart`
   - `trends_screen.dart` + `trends_components.dart`
6. Credentials moved out of `lib` code into `.env/.env`:
   - Added `EnvConfig` and `FirebaseEnvOptions`
   - `main.dart` now loads `.env/.env` and initializes Firebase from env values
   - Cloudinary usages switched to env-driven values
   - Removed `lib/firebase_options.dart` (hardcoded keys no longer in `lib`)
7. Page/widget atomization pass (one-class-per-file direction) applied further:
   - Added `pages/widgets/` structure for:
     - `features/readings/presentation/pages`
     - `features/dashboard/presentation/pages`
     - `features/tanks/presentation/pages`
     - `features/reports/presentation/pages`
   - Moved `_*.dart` UI classes into these `widgets/` folders and updated `part` references.
8. Large page state/data extraction:
   - `reading_entry_screen.dart` now split into:
     - page widget class
     - `reading_entry_state.dart`
     - `reading_entry_models/*`
   - `dashboard_tab.dart` now split into:
     - page widget class
     - `dashboard_tab_state.dart`
     - `dashboard_models/*`
   - `tank_browser_screen.dart` now split into:
     - page widget class
     - `tank_browser_screen_state.dart`
     - `tank_browser_models/*`
   - `property_builder_page.dart` now split into:
     - page widget class
     - `property_builder_page_state.dart`
     - `property_builder_models/*`
   - `trends_screen.dart` now split into:
     - page widget class
     - `trends_screen_state.dart`
9. DB mode toggle infrastructure (Prod/Dev):
   - Added `lib/core/services/database_mode_service.dart`
   - `main.dart` initializes DB mode at startup
   - Home app bar now has `PROD/DEV` toggle (switches root vs `testDB`)
   - Repositories and runtime screens now use `DatabaseModeService.ref(...)`
10. Admin settings foundation (DB-backed session timeout):
   - Added `lib/core/services/app_settings_service.dart`
   - Added `lib/features/admin/presentation/pages/admin_settings_page.dart`
   - Admin dashboard now has `Settings` tab
   - `SessionManager` now respects DB settings (`none` or configured minutes)
11. Image marker upgrades:
   - Added text sticker support with white background
   - Double-tap text to edit
   - Drag text to move
   - Drag to top-left delete zone to remove
   - Existing draw/erase/export behavior preserved
12. Autofill token/eval hardening:
   - `ExpressionEngine.evaluate` now aliases `${...}` tokens to safe variable names before parsing.
   - Prevents numeric param IDs from being treated as numbers (fixes ID-summing bug).
13. Cascade protection + scope isolation:
   - Parameter delete is blocked when referenced by another autofill expression.
   - Local parameter cache is now scope-based (`scopeId`) for tank/draft isolation.
14. Admin structure transfer:
   - Export for `tanks` + `tank_tree` JSON added.
   - Import supports pasted JSON and local file-path JSON.
15. Folder delete cascade:
   - Deleting a folder now cascades through descendants and deletes child tanks.
16. Tank delete retention rule:
   - Tank delete still removes tree/dashboard/alerts related data.
   - Readings deletion is now commented out (preserved history).
17. Client/root direction (interim):
   - Tank create flow now defaults location/client to `root` and uses fixed root for new tree folder/leaf zone.
   - Scale Max / Scale Side removed from tank-create UI (defaults applied in save path).
   - Search cache in input browser now refreshes when tree updates.
18. Expression editor delete semantics:
   - DEL now removes `${paramId...}` tokens as a single block even when cursor is inside token.
   - Range delete expands to whole token blocks when selection overlaps tokens.
19. Expression engine parser stability:
   - Variable token grammar adjusted so alias tokens (e.g., `__v1 - __v2`) are parsed correctly.
   - Fixes false "missing variable" style failures during numeric-id formula evaluation.
20. Admin import flow UX:
   - Import switched to file-picker based JSON selection (no paste/path input required).
21. Login timeout display:
   - Login screen timeout message now pulls current DB-backed settings (mode-aware via DB root).
22. Automated test coverage added:
   - Added `test/core/services/expression_engine_test.dart` with regular + edge cases:
     - numeric-id token eval
     - dual-side tokens
     - precedence, parentheses, unary minus, decimals
     - missing variable / invalid token / divide by zero
   - Added `test/core/services/database_mode_service_test.dart`:
     - PROD path behavior
     - DEV `testDB` path prefix behavior
   - Test run status: passing (`11` tests).
23. Tank creation crash hardening (`String` vs `Map` cast):
   - Added safe mixed-shape parsing for RTDB payloads in:
     - `TankModel.fromMap` (`inspection_properties` now supports `List`/`Map` and skips invalid entries)
     - `TankTreeRepository` stream/fetch/count paths (guards for non-map rows)
     - `TankRepository.updateTank` tree-sync block (safe map conversion)
   - Goal: avoid runtime `String is not a subtype of Map<dynamic,dynamic>` while creating/loading tanks.
24. Delete-scope correction:
   - Tank delete remains single-tank scoped (tank + related records + tree refs for that tank).
   - Folder delete now resolves only that folder subtree and deletes only tanks inside that subtree.
   - Added `TankTreeRepository.fetchSubtree` and integrated it in browser delete flow.

## Remaining high-priority splits

1. Controller/service extraction from still-large state files:
   - `reading_entry_screen.dart` (~1870 LOC) state + upload/autofill logic
   - `dashboard_tab.dart` (~735 LOC) orchestration/state still mixed in page
   - `property_builder_page.dart` (~2209 LOC) expression/session logic in UI state
   - `tank_browser_screen.dart` (~981 LOC) tree ops + side effects in UI state
   - `trends_screen.dart` (~1780 LOC) filtering/export orchestration in UI state
2. Introduce feature-level controllers/state files for each above page.
3. Move remaining direct network/file side effects from pages to services where possible.
4. Add route files per feature (`*_routes.dart`) and central app route map.
5. Add tests for extracted services/controllers.
6. Request-specific pending work:
   - Autofill expression engine rewrite (`id`-based references only, robust cascade update/delete)
   - Tank-local parameter source unification with SQLite sync rules
   - Admin import/export of tank + tree structure JSON into current open folder
   - QR regeneration on tank rename/update (always latest caption payload)
   - Pull-to-refresh for all key pages
   - Loss calculation pipeline + UI integration for number/slider params
   - Client hierarchy phase-2: replace interim `root` with parent/client inheritance model across tree/tank/QR payloads

## Next safe execution order

1. `reading_entry_state.dart` -> split into controllers/services + small state slices
2. `property_builder_page_state.dart` -> expression/service split
3. `trends_screen_state.dart` -> export/chart query split
4. `tank_browser_screen_state.dart` -> tree action service split
5. `home/tank_input_browser.dart` and `image_marker_screen.dart` atomization
