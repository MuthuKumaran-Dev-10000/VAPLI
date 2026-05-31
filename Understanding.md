# VAPLI Application Understanding

This document outlines our complete understanding of **VAPLI** (the Lubrication Indicator app), including its design patterns, architecture, state flow, and database structure.

---

## 1. Project Overview & Context
- **Product Name**: VAPLI (Lubrication Indicator)
- **Domain**: Industrial lubrication inspection and monitoring.
- **Goal**: Help inspectors perform routine lubrication checks, track hierarchical equipment trees, trigger automated alerts upon threshold violations, log DB modifications for audit compliance, and export reports for industrial decision-making.
- **Core Technology Stack**:
  - **Flutter**: Cross-platform frontend client optimized for mobile UX.
  - **Firebase Realtime Database (RTDB)**: Low-latency NoSQL database for realtime data sync, state retention, and configuration.
  - **Cloudinary**: Cloud image hosting for param photos, violation images, and manual capture references.
  - **fl_chart**: Dynamic chart plotting for trend analysis.
  - **Excel + PDF/PNG Generators**: Exporters for sharing summaries and compliance logs.

---

## 2. Architecture & File Structure
VAPLI implements a **feature-first, layered architecture** to isolate concerns and make additions or refactorings easy and safe.

```
lib/
├── core/                        # Global resources and shared services
│   ├── constants/               # Global strings and config parameters
│   ├── models/                  # Global entities (e.g. ClientModel)
│   ├── services/                # Isolation, settings, context, access control, math formulas
│   ├── theme/                   # central ThemeData styles for dark mode
│   └── utils/                   # Shared utility logic (hashing, session storage)
│
├── features/                    # Core vertical feature divisions
│   ├── admin/                   # Client management, user creation, privileges, session config
│   ├── alerts/                  # Threshold warnings, history, resolutions
│   ├── auth/                    # Client search, session validations, secure logins
│   ├── dashboard/               # Live counts, telemetry cards, compliance indicators, exports
│   ├── home/                    # Shell tabs, quick navigators, QR scanners
│   ├── readings/                # Dynamic inputs, constraint checks, photo uploads, formulas
│   ├── reports/                 # Date filtering, fl_charts trend lines, excel exporters
│   └── tanks/                   # Hierarchy tree, grouping nodes, duplicate/rename, QR codes
│
└── main.dart                    # App initialization, Firebase boot, entry router
```

### Layer Rules
1. **Presentation Layer**: Handles only UI components and state notifier binds.
2. **Data/Repositories Layer**: Orchestrates database reads/writes, Firebase RTDB stream listeners, and API calls (Cloudinary asset removals).
3. **Models Layer**: Co-located within their corresponding feature (`data/models/`) and defines clean parsing logic (`fromMap`, `toMap`).
4. **Imports**: Strict decoupling. Shared utilities live in `core/` and are imported explicitly.

---

## 3. Multi-Client Isolation Mechanism
Data isolation is maintained dynamically via the `DatabaseModeService` ([database_mode_service.dart](file:///c:/Users/muthu/Freelance/vapli/lib/core/services/database_mode_service.dart)). 

### 3.1 Path Prefixing
- **Global Paths** (accessed directly):
  - `users` — stores user database records globally so credentials can be checked across clients.
  - `clients` — stores information about registered clients.
- **Client-Scoped Paths** (automatically prefixed with the client key like `clientDbKey/path`):
  - `tanks`, `tank_tree`, `readings`, `alerts`, `completed_tasks`, `admin_audit_logs`, `alerts_full`, `violations`, `dashboard_stats`, `reading_feedback`, `sync_logs`.

### 3.2 Development Mode
- A development root prefix (`testDB`) is applied to both scoped and global paths when the debug environment flag is active.
- Configured routes:
  - Scoped Prod: `{clientDbKey}/tanks`
  - Scoped Dev: `testDB/{clientDbKey}/tanks`
  - Global Prod: `clients`
  - Global Dev: `testDB/clients`

---

## 4. Authentication & Bootstrapping Flow
1. **Client Selection**: When starting the app, users search for their client by typing (>= 3 characters). 
2. **Database Scoping**: Once selected, `DatabaseModeService.setClientScope(dbKey)` is invoked, updating the prefix for all queries.
3. **User Authentication**: Login check runs against the users list associated with the client.
4. **Bootstrap Fallback**:
   - If no clients exist in the system, a root fallback login is allowed (`admin` / `Admin@123`) to let administrators register the first client.
   - Creating a client automatically triggers `ensureClientBootstrap`, generating:
     - A default client admin: `admin` / `Admin@123`.
     - Default system settings: Session timeout set to 60 minutes.

---

## 5. Privilege Management (RBAC)
Role-based access control rank and default maps are declared in `AccessControlService` ([access_control_service.dart](file:///c:/Users/muthu/Freelance/vapli/lib/core/services/access_control_service.dart)):

- **Roles**:
  - `super admin` (Rank 3)
  - `admin` (Rank 2)
  - `user` (Rank 1)
- **Privileges**:
  - `create_client`, `create_users`, `grant_users`, `create_tanks`, `delete_tanks`, `modify_tanks`, `allocate_users_to_clients`, `open_admin_page`, `view_settings`, `change_settings`.
- **Precedence Rule**: Actor rank must be strictly greater than target rank to edit/delete user files (`rankOf(actor) > rankOf(target)`).

---

## 6. Core Data Models
- **UserModel**: Tracks identity, roles, clientIds, explicit permissions, failed login attempts, lock limits, and audit parameters.
- **ClientModel**: Stores ID, name, dbKey, and tree root identifiers.
- **TankModel**: Contains location metadata, list of dynamic `inspectionProperties` (defined inside a schema map), scale dimensions, QR URL, and frequency parameters.
- **TankNode**: Represents hierarchical folder groupings and leaf (tank) pointers inside the tree.
- **ReadingModel**: Collects the `inspectionValues` map, captured images, source type, and inspector info.
- **AlertModel**: Stores violations (e.g. constraints violated, actual value, severity, live status, and resolution details).
- **DashboardStatsModel**: Tracks telemetry counts, latest readings, and parametric metrics (`ParamStat` holds average, min, max, dropdown counts, and latest text outputs).

---

## 7. Reading Submissions & Math Evaluation
When entering readings in `ReadingEntryScreen` ([reading_entry_screen.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/readings/presentation/pages/reading_entry_screen.dart)):

1. **Formula Autofills**: Parameters marked as autofills run through `ExpressionEngine.evaluate(...)` when their dependencies change. Supporting syntax like `${param_id}` and `__last` (to resolve previous inspection scores stored in `Previouscapture/`) are evaluated.
2. **Immediate Violation Warnings**: Constraints are evaluated in real time as values change (`_evaluateAllConstraints`). If a violation fires, it plays an alert sound, triggers haptic vibrations, and writes a pending record to the database under `alerts/`, `violations/`, and `alerts_full/`.
3. **Data Finalization**:
   - Captures param, violation, or manual entry images and uploads them to Cloudinary.
   - Saves the final `ReadingModel` entry via `ReadingRepository`.
   - Runs an incremental update in `DashboardStatsRepository` to recalculate averages/counts.
   - Persists previous capture configurations under `Previouscapture/...`.
   - Modifies live alerts to link their `reading_id` and marks them `live: false`.

---

## 8. Logs & Telemetry Reporting
- **Dashboard Tab**: Summarizes active alarms, completed reports, compliance statuses (comparing current date against tank inspection frequency rules), and exports data.
- **Trends Screen**: Visualizes param details via line graphs and outputs metrics to Excel sheets.
- **Audit Logs**: Mutations affecting database configuration (creation/deletes/assignments) write detail payloads to `admin_audit_logs` (scoped) and `admin_audit_logs_master` (global).
