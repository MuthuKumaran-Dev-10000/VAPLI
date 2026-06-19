# VAPLI (Lubrication Monitor) Features Specification & Update Tracker

This document provides a detailed inventory of the features implemented in the VAPLI application, mapping them to their corresponding files and components in the codebase, and tracking recent and future updates.

---

## 1. Feature Specifications & Mappings

### 1.1 Authentication & Access Control (RBAC)
* **Goal**: Secure application access and restrict operations based on role-based access configurations.
* **Key Capabilities**:
  * **Role Hierarchy**: Supports `super admin` (rank 3), `admin` (rank 2), and `user`/`inspector` (rank 1) accounts.
  * **Permission Checks**: Enforces specific access restrictions at runtime via `AccessControlService.can(...)` checks before allowing views or operations (e.g., creating tanks, viewing audit logs, historical overrides).
  * **Session Persistence**: Saves authentication states via `SessionManager` and enforces database-configured session timeouts.
* **Code Components**:
  * [login_screen.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/auth/presentation/pages/login_screen.dart) - Login entry page for normal inspectors.
  * [admin_login.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/admin/presentation/pages/admin_login.dart) - Login entry restricted to users with admin roles.
  * [auth_controller.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/auth/presentation/controllers/auth_controller.dart) - Main business logic controller for auth validation.
  * [auth_repository.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/auth/data/repositories/auth_repository.dart) - Handles password hash comparison and user node fetching.
  * [access_control_service.dart](file:///c:/Users/muthu/Freelance/vapli/lib/core/services/access_control_service.dart) - The central authority defining permissions, privileges, and rank validation.
  * [session_manager.dart](file:///c:/Users/muthu/Freelance/vapli/lib/core/utils/session_manager.dart) - Handles session storage, validity duration, and credentials cache.

### 1.2 Home Navigation Shell & Environment Toggles
* **Goal**: Provide the main UI navigation framework and support environment-switching controls.
* **Key Capabilities**:
  * **Tabbed Experience**: Bottom navigation bar to toggle between Dashboard, Browse (Tanks), Trends, and Scanner.
  * **Sandbox database (Prod vs Dev Mode)**: A toggle in the app bar allows developers to route all reads/writes either to root nodes or under `/testDB` in Firebase.
  * **Multi-Tenant Scoping**: Restricts asset views and updates to the selected client/tenant boundary by automatically prefixing paths with `activeClientId/` (e.g., `client_123/tanks`).
* **Code Components**:
  * [home_screen.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/home/presentation/pages/home_screen.dart) - Main shell, AppBar, environment toggle, navigation drawer, and tab controllers.
  * [client_selector_page.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/home/presentation/pages/client_selector_page.dart) - Multi-tenant configuration and client selector page.
  * [qr_scan_screen.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/home/presentation/pages/qr_scan_screen.dart) - Scanner shortcut modal.
  * [database_mode_service.dart](file:///c:/Users/muthu/Freelance/vapli/lib/core/services/database_mode_service.dart) - Normalizes and resolves paths based on dev/prod mode and client scoping.

### 1.3 Asset Browser & Tank Hierarchy
* **Goal**: Browse, search, and navigate through the structured hierarchy of asset folders and tanks.
* **Key Capabilities**:
  * **Nested Tree Navigation**: Renders collapsible folders and leaf assets (tanks, gearboxes) grouped by parent relationships.
  * **Search Caching**: Dynamic client-side caching of tree contents to enable instant filtering.
  * **QR Identification**: Supports scanning an asset QR code to jump directly to its reading entry form.
* **Code Components**:
  * [tank_browser_screen.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/tanks/presentation/pages/tank_browser_screen.dart) - Tree widget page.
  * [tank_browser_screen_state.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/tanks/presentation/pages/tank_browser_screen_state.dart) - Logic for rendering folders, searching, expanding nodes, and triggering actions.
  * [tank_repository.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/tanks/data/repositories/tank_repository.dart) - Performs CRUD operations on individual tank asset parameters.
  * [tank_tree_repository.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/tanks/data/repositories/tank_tree_repository.dart) - Handles structure updates, hierarchy node lists, and subtree queries.

### 1.4 Parameter Configuration Builder (Property Builder)
* **Goal**: Build and configure dynamic fields, constraints, calculations, and alarms for asset inspections.
* **Key Capabilities**:
  * **Dynamic Inputs**: Support fields of type `number`, `text`, `dropdown`, `slider`, `group`, and `dual_text`.
  * **Threshold Limits & Alarm Triggers**: Configures constraint limits (e.g., `> 80` or `contains "Low"`) that trigger warning sounds, haptics, photos requirements, or block submission when violated.
  * **Autofill Formula Engine**: Mathematical formulas (e.g. `{oil_temp} * 1.05`) parsed and calculated at runtime via an AST expression parser.
* **Code Components**:
  * [property_builder_page.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/tanks/presentation/pages/property_builder_page.dart) - Property builder layout entry.
  * [property_builder_page_state.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/tanks/presentation/pages/property_builder_page_state.dart) - Handles configuration CRUD, limits editor, variable mappings, and expression validation.
  * [expression_engine.dart](file:///c:/Users/muthu/Freelance/vapli/lib/core/services/expression_engine.dart) - Evaluates variables and evaluates algebraic expressions with division-by-zero protection.

### 1.5 Reading Entry Form & Dynamic Validation
* **Goal**: Provide the form where inspectors record values, capture verification photos, and submit readings.
* **Key Capabilities**:
  * **Real-time Autofill Calculations**: Dynamically updates calculated parameters as values of their dependencies change in form inputs.
  * **Instant Cloud Uploads**: Inspection photos taken by the camera upload immediately to Cloudinary and link to parameter values.
  * **Real-time Violation Alerts**: Triggers alert sounds and haptics, and creates a draft alert node in the database if constraints are violated.
  * **Duplicate Inspection Warning**: Warns if a reading was submitted in the last 30 minutes, requiring a mandatory justification reason.
  * **Historical Timestamp Override**: Allows authorized inspectors (`historical_upload` privilege) to override default timestamps via pickers.
  * **Sequenced Navigation**: Guides the inspector through all sibling assets in a folder sequentially without needing to go back to the browser.
* **Code Components**:
  * [reading_entry_screen.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/readings/presentation/pages/reading_entry_screen.dart) - Dynamic form builder layout page.
  * [reading_entry_state.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/readings/presentation/pages/reading_entry_state.dart) - Handles inputs state, duplicate checks, override validation, alert generation, and folder-sequenced progression.
  * [reading_repository.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/readings/data/repositories/reading_repository.dart) - Handles Firebase writes, historical logging, and stats update triggers.

### 1.6 Visual Hotspot Verification (Image Marker)
* **Goal**: Enable placement of point markers and labels on uploaded asset diagrams.
* **Key Capabilities**:
  * **Coordinate Annotations**: Tapping diagrams maps proportional coordinate points (`dx`/`dy`) to ensure scaling across different screen sizes.
  * **Sticker Annotations**: Draggable, editable, and delete-zone-responsive text stickers layered over the diagram.
* **Code Components**:
  * [image_marker_screen.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/readings/presentation/pages/image_marker_screen.dart) - Handles visual drawing, eraser modes, text stickers, and position calculations.

### 1.7 Dashboard Analytics & Alert Resolution
* **Goal**: Real-time summary overview of system health, active alerts, and action resolution workflows.
* **Key Capabilities**:
  * **Real-time Counter Cards**: Displays counts of completed checks, pending checks, open alerts, and task completion percentages.
  * **Active Alerts List**: Lists all active alerts across all assets.
  * **Complete Task Sign-Off**: Admin actions to resolve alerts, updating the status to `COMPLETED` and logging the entry under `/completed_tasks`.
* **Code Components**:
  * [dashboard_tab.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/dashboard/presentation/pages/dashboard_tab.dart) - Main stats widgets and alerts panels.
  * [dashboard_tab_state.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/dashboard/presentation/pages/dashboard_tab_state.dart) - Fetches RTDB nodes, evaluates active list states, and triggers resolution database writes.

### 1.8 Reports & Historical Trends Graph
* **Goal**: Analyze history via graphs and generate production-ready PDF & Excel reports.
* **Key Capabilities**:
  * **Trends Graph**: Renders parameter historical values as a line chart with threshold constraint line markers.
  * **Executive PDF Matrix**: Generates a matrix report grouping parameters as columns, assets as rows, and showing trend arrows and photo links.
  * **Excel Abnormality Log**: Creates multi-tab Excel files listing anomaly details, duplicate reasons, and links.
* **Code Components**:
  * [trends_screen.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/reports/presentation/pages/trends_screen.dart) - Graph UI page.
  * [trends_screen_state.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/reports/presentation/pages/trends_screen_state.dart) - Filters data points and orchestrates exports.

### 1.9 System Administration Operations
* **Goal**: Enforce system configuration, backup actions, and auditing.
* **Key Capabilities**:
  * **User & Client Onboarding**: Creates and manages accounts and scopes.
  * **JSON Backup Import/Export**: Backs up/restores asset configuration tree structure.
  * **Audit Log Viewer**: Lists all administrative actions recorded in `/admin_audit_logs`.
* **Code Components**:
  * [admin_dashboard.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/admin/presentation/pages/admin_dashboard.dart) - Main tab shell for admins.
  * [admin_audit_logs_page.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/admin/presentation/pages/admin_audit_logs_page.dart) - Logs search table.
  * [admin_settings_page.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/admin/presentation/pages/admin_settings_page.dart) - Controls session rules and configurations.

---

## 2. Chronological Update Log (Changelog)

This section tracks all feature modifications, refactorings, and updates applied to the codebase. When introducing future changes, document them in this section.

### June 18, 2026 (Constraint Popups, Null Safety, and PDF Report Overhaul)
* **Bottom Constraint Violation Popups**:
  * Implemented a bottom sheet popup (`_showViolationBottomSheet`) in `ReadingEntryScreen` styled by alert severity (danger/warning/info) with colors and icons to notify inspectors immediately when a constraint fails.
  * Triggered the bottom sheet in `_handleConstraintFired` alongside the alert sound/vibration alarm.
* **Autofill & Optional Null Safety**:
  * Guarded constraint checks in `_evaluateAllConstraints` to skip evaluation for empty optional fields (values that are null, `null` as string, or empty).
  * Refactored `_collectValues` to store `null` instead of default values (like `0.0`, `""`, or empty maps) when optional number, text, multiline, dropdown, or dual_text fields are left blank.
* **PDF Inspection Report Overhaul**:
  * Shifted report orientation from Landscape to Portrait (`PdfPageFormat.a4`).
  * Unified "Readings Taken" and "Readings Not Taken" pages into a single **Asset Inspection Detailed List** table.
  * Sorted assets alphabetically within folders, with folders sorted alphabetically. Highlighted uninspected tank rows with a light cyan-blue background decoration.
  * Rebuilt the Page 1 stats table to format counts as blue underlined hyperlinks that navigate directly to corresponding sections in the PDF.
  * Appended a final page displaying active unresolved alerts at the end of the report.
  * Prevented trend indicators (up/down arrows) from drawing when `expected_avg` is missing or null, rather than assuming it to be 0.
  * Formatted column flex widths, headers, and cell alignments to scale and wrap cleanly without overlaps or scrambling in portrait orientation.

### June 18, 2026 (Active Alert Warnings on Leaf Details & Sibling Auto-Routing)
* **Active Alert Warnings on Leaf Details**:
  * Moved the active alerts warning popup dialog and dynamic severity banner from the Reading Entry page to the intermediate **Leaf Details** page (displayed after selecting a tank leaf, before taking a reading).
  * Automatically plays a warning sound (`assets/sounds/alert.mp3` or system fallback beep) and triggers a haptic vibration pattern when active alerts are loaded for the selected tank leaf.
  * Renders a non-dismissible warning popup dialog detailing active alerts: Title, Message, Tank, Captured By, Timestamp, Severity color badge, and photo thumbnail using `CachedNetworkImage` with fullscreen tap-to-zoom.
* **Skip Tank Sibling Routing**:
  * Added "No, Skip Tank" and "Yes, Continue" controls to the warning popup.
  * If the operator selects "No", the browser automatically navigates to the next sibling tank in the folder sequence. If it is the last tank, the selection is cleared.
* **Reading Form References**:
  * Retained the dynamic active alerts banner inside `ReadingEntryScreen` for operator reference, but disabled the popup dialog warning there to prevent duplicate alerts.
* **Clean Code Integration**:
  * Left the `AlertModel` definition unchanged to protect database compatibility and existing workflows.
  * Resolved Flutter SDK warnings by replacing deprecated `dialogBackgroundColor` configurations with direct `AlertDialog.backgroundColor` styling.

### June 18, 2026 (Dashboard Layout Optimization & Settings Controls)
* **Reordered Dashboard Tab Layout**: Moved reports generation, time range dropdowns, and download buttons to the very top of the tab (below the header) so inspectors don't have to scroll past dozens of tank cards to download reports.
* **Client-Scoped Visibility Toggles**:
  * Added `'settings'` to `_scopedPaths` in `DatabaseModeService` to ensure settings are stored per client (`clientname/settings`).
  * Expanded `AppSettingsService` and `AdminSettingsPage` to support four dashboard visibility switches (sliders):
    * *Show Inspection Averages & Last Values*
    * *Display Alerts (Not Completed)*
    * *Display Alerts (Completed)*
    * *Display Inspection Compliance*
  * Set up a live database stream subscription on the dashboard to dynamically show or hide sections based on these saved preferences.
* **"Today Only" Alerts Filter**:
  * Added a `Today Only` filter chip next to `By Time` and `By Severity` on the active alerts dashboard panel.
  * Filters active alerts to only show those triggered on the current day.

### June 18, 2026 (Refactoring & Feature Optimization Pass)
* **Reorganized Folder Architecture**: Moved legacy directories (`lib/data`, `lib/presentation`) into a feature-first pattern (`lib/features/*` and `lib/core/*`), resolving broken relative imports.
* **Centralized Auth & Controllers**: Split the large login UI into modular widgets, introduced `AuthController` to separate business logic from pages, and loaded credentials securely via `dotenv` from `.env/.env`.
* **Database Mode Service**: Introduced `DatabaseModeService` to support Prod/Dev database sandbox swapping (`testDB`) and multi-tenant client-scope isolation.
* **Split Large State Files**: Reorganized large page files (e.g. `reading_entry_screen.dart`, `dashboard_tab.dart`, `property_builder_page.dart`) into separate Page widgets, state controller classes (`_state.dart`), and component parts to improve maintainability.
* **Autofill Engine Hardening**: Configured `ExpressionEngine` to parse numeric parameter IDs safely as variables rather than literal numbers, eliminating formula evaluation bugs.
* **Folder Delete Cascades**: Implemented subtree queries in `TankTreeRepository` so deleting a folder cleanly deletes all nested subfolders and assets.
* **Folder-Sequenced Reading Flow**:
  * Added auto-navigation sequence inside `ReadingEntryScreen` and `reading_entry_state.dart`.
  * After saving a reading, a 3-second delay triggers a jump to the next tank in the current folder.
  * When the final tank in a folder is saved, the selection clears, popping the user back to the folder list.
  * Ensured database writes (logs, updates, previous capture backups) complete before navigation begins.
* **Alert Lifecycle Fixes**:
  * Added `status` fields (`active` or `COMPLETED`) to alerts.
  * Removed the midnight boundary query rule (`_isToday`). Alerts now persist across days on the dashboard and in reports until they are resolved by an admin.
* **Duplicate Readings Check**:
  * Checks if a reading exists for the selected asset in the last 30 minutes.
  * Prompts the inspector to confirm or cancel. If they confirm, they must supply a justification reason that is saved under `duplicate_reason`.
* **Historical Timestamp Override**:
  * Verified if the active user possesses the `historical_upload` privilege.
  * Displays calendar/clock edit buttons on the metadata card, allowing inspectors to select custom start/end times.
* **Created Feature Tracking Spec**: Established `FEATURES.md` as the unified system specification and change log to track updates.

---

## 3. Future Roadmap

The following tasks are queued for future system updates:
1. **SQLite Offline Sync**: Enable local caching of readings and asset trees for offline inspection.
2. **QR Regeneration on Rename**: Auto-generate new QR codes when tank codes or names are edited.
3. **Pull-To-Refresh**: Add drag-to-refresh gestures across the dashboard and tank browser screens.
4. **Loss Calculation Pipeline**: Integrate oil loss calculation rules directly into number and slider parameters.
5. **Client Hierarchy Phase 2**: Replace the interim `root` parameter with a parent/client inheritance model across the asset tree, tanks, and QR payloads.
