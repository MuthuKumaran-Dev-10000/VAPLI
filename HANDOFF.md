# VAPLI Project Handoff

This document is a full knowledge-transfer guide for future AI/human maintainers.

---

## 1. Project Identity

- **Project name**: `lubrication_indicator` (brand name shown as **VAPLI**)
- **Stack**:
  - Flutter (mobile/desktop/web capable; current implementation centered on mobile UX)
  - Firebase Realtime Database
  - Firebase Core
  - Cloudinary (image uploads)
  - `fl_chart` (trends charts)
  - `excel` + PNG/PDF export support
- **Core domain**: Industrial lubrication inspection and monitoring

---

## 2. High-Level Product Purpose

The app manages client-specific lubrication inspection workflows:

- Client-based data isolation
- Tank creation + hierarchical grouping (tank tree)
- Inspection/readings entry with constraints
- Alerts and violations
- Dashboard with live stats
- Trends and reporting exports
- Admin and super-admin management
- Audit logging for DB-impacting admin actions

---

## 3. Codebase Structure

Top-level important areas:

- `lib/main.dart`  
  App bootstrap, Firebase init, entry routing.

- `lib/core/`
  - `constants/app_constants.dart`
  - `models/client_model.dart`
  - `services/` (critical infra services)
  - `utils/` (session/hash helpers)

- `lib/features/`
  - `auth/`
  - `home/`
  - `admin/`
  - `tanks/`
  - `readings/`
  - `dashboard/`
  - `reports/` (trends)
  - `alerts/` (models/repo-related)

---

## 4. Multi-Client Data Isolation (Critical)

### 4.1 How isolation works

`DatabaseModeService` dynamically prefixes scoped paths using selected client DB key:

- Example client key: `vsypaper`
- Scoped access: `vsypaper/tanks`, `vsypaper/readings`, etc.

This is handled by:

- `lib/core/services/database_mode_service.dart`

### 4.2 Global vs scoped paths

Global paths (not client-prefixed):

- `users`
- `clients`
- `system_settings` (global node; note client-specific also exists when scoped)

Scoped paths (client-prefixed when scope is set):

- `tanks`
- `tank_tree`
- `readings`
- `alerts`
- `alerts_full`
- `violations`
- `dashboard_stats`
- `reading_feedback`
- `sync_logs`
- `completed_tasks`
- `admin_audit_logs`

### 4.3 Important implementation rule

Do **not** keep long-lived cached root DB refs for scoped data unless they are recreated after scope changes.  
Current code has been updated in key repositories to resolve scoped refs correctly.

---

## 5. Authentication + Client Selection Flow

## 5.1 Current intended flow

1. Open login screen.
2. If clients exist:
   - User searches client by typing at least 3 characters.
   - Selects target client.
   - Scope set to selected client.
   - Username/password auth happens against selected client scope.
3. If no clients exist:
   - Root fallback login allowed for:
     - username: `admin`
     - password: `Admin@123`
   - This enables first-time bootstrap/admin operations.

Files:

- `lib/features/auth/presentation/pages/login_screen.dart`
- `lib/features/auth/data/repositories/auth_repository.dart`

## 5.2 Session handling

- Session saved via `SessionManager`.
- Home session validity checks and expiry prompt exist.

---

## 6. Client Bootstrap Behavior

When creating/selecting a client, bootstrap ensures client has minimum required state:

- Default super admin user in `clientDbKey/users`
  - username `admin`
  - password `Admin@123` (hashed)
  - role `super admin`
- Default session settings in `clientDbKey/system_settings/session`

File:

- `lib/core/services/client_repository.dart`

---

## 7. Roles and Access Control

Roles:

- `super admin`
- `admin`
- `user`

Privileges defined and checked through:

- `lib/core/services/access_control_service.dart`

Admin UI uses privilege checks heavily before exposing actions.

---

## 8. Admin Dashboard

Primary file:

- `lib/features/admin/presentation/pages/admin_dashboard.dart`

Tabs:

- Tanks
- Clients (super admin)
- Users
- Settings (super admin)

Capabilities include:

- Create/update/delete clients
- Create/update/delete users
- Grant/revoke user access
- Assign users to clients
- Tank browser embedding for structure operations
- Structure import/export
- Audit logging for DB-impacting actions

---

## 9. Audit Logging (DB mutation only)

Goal: forensic traceability for major operations.

Stored fields include:

- actor info (id, username, name, role)
- operation
- entity type/id/name
- client context
- details payload
- timestamp
- outcome

Writes to:

- scoped: `admin_audit_logs`
- master/global: `admin_audit_logs_master`

Actions currently logged:

- client create/update/delete
- user create/update/delete
- user access grant/revoke
- user-client assignment
- settings update
- tank browser mutation actions:
  - create/update/delete group/tank leaf
  - move/reorder
  - duplicate
- import structure (success/failure)

Not logged (by request):

- tab switches
- client selector UI switches
- export structure viewer action

---

## 10. Tanks + Tank Tree

Core files:

- `lib/features/tanks/data/models/tank_model.dart`
- `lib/features/tanks/data/models/tank_node_model.dart`
- `lib/features/tanks/data/repositories/tank_repository.dart`
- `lib/features/tanks/data/repositories/tank_tree_repository.dart`
- `lib/features/tanks/presentation/pages/tank_browser_screen.dart`

### 10.1 Tank model

Includes:

- tank identity + metadata
- inspection properties schema
- scale
- QR data
- inspection frequency config:
  - `inspection_frequency_type` (`daily`, `weekly_once`, `weekly_thrice`, `custom_days`)
  - `inspection_frequency_days` (int fallback/explicit interval)

### 10.2 Tank tree

Hierarchical structure of folders + leaf nodes mapped to tanks.

Operations:

- create folder/leaf
- move
- reorder
- duplicate subtree
- delete subtree

---

## 11. Settings

Main file:

- `lib/features/admin/presentation/pages/admin_settings_page.dart`

Current settings UI supports:

- Session timeout mode:
  - no timeout
  - fixed minutes
- Per-tank inspection frequency editor:
  - daily
  - weekly once
  - weekly thrice
  - custom days

Session settings service:

- `lib/core/services/app_settings_service.dart`

---

## 12. Readings Entry

Main files:

- `lib/features/readings/presentation/pages/reading_entry_screen.dart`
- `lib/features/readings/presentation/pages/reading_entry_state.dart`
- `lib/features/readings/data/repositories/reading_repository.dart`

Features:

- Dynamic inspection properties by tank
- Field types: number, text, multiline, dropdown, slider, dual_text
- Constraint engine with violations
- Live alert writes/updates/removals
- Autofill formulas with dependency evaluation
- Per-parameter photo capture + Cloudinary upload
- Violation photo uploads
- Manual capture list with add/remove

On save:

- Builds `inspectionValues` map
- Persists param image URLs, violation image URLs, manual capture URLs into map
- Saves reading
- Updates dashboard stats incrementally

---

## 13. Dashboard

Main files:

- `lib/features/dashboard/presentation/pages/dashboard_tab.dart`
- `lib/features/dashboard/presentation/pages/dashboard_tab_state.dart`
- `lib/features/dashboard/data/repositories/dashboard_stats_repository.dart`
- `lib/features/dashboard/data/models/dashboard_stats_model.dart`

Features:

- Alerts panel (today tasks)
- Tank stats cards
- Completed tasks sections
- Expected-avg synthetic alerts
- Per-tank PNG export
- Alerts PNG export
- Full dashboard PDF export
- Compliance section at dashboard end:
  - list all tanks
  - show tank name, tank id, tank route, last inspected date
  - green check if within required inspection interval
  - red cross if overdue/not inspected

Last inspection panel includes thumbnails for stored image URL fields.

---

## 14. Trends/Reports

Main files:

- `lib/features/reports/presentation/pages/trends_screen.dart`
- `lib/features/reports/presentation/pages/trends_screen_state.dart`

Features:

- Tank selection + all tanks mode
- Date range filtering
- Multi chart types by property type
- PNG export
- Excel export

---

## 15. Realtime DB Structure (Conceptual)

Global:

- `/users`
- `/clients`
- `/admin_audit_logs_master`

Per client scope (`/{clientDbKey}/...`):

- `meta`
- `users`
- `system_settings/session`
- `tanks`
- `tank_tree`
- `readings`
- `dashboard_stats`
- `alerts`
- `alerts_full`
- `violations`
- `completed_tasks`
- `admin_audit_logs`
- other scoped nodes (`reading_feedback`, `sync_logs`)

---

## 16. Important Operational Defaults

- Root bootstrap fallback credentials (no clients):
  - `admin / Admin@123`
- Default per-client bootstrap admin:
  - `admin / Admin@123`
- Default session timeout:
  - 60 minutes unless overridden
- Default tank inspection frequency:
  - daily (1 day)

---

## 17. Key Edge Cases Already Addressed

- Silent export failures replaced with feedback in dashboard exports.
- Scoped DB bypass reduced by resolving path through `DatabaseModeService` in key repositories.
- Audit logs filtered to DB-impacting actions.
- Manual capture delete behavior restored to original expected UX.
- Dashboard export can force-expand last inspection values before capture.

---

## 18. Known Risk Areas / Technical Debt

1. `main.dart` still contains `createTestAdmin()` test/bootstrap utility writing to `testDB/users`; evaluate if this should remain in production builds.
2. Some modules may still have legacy assumptions about global `users` vs per-client `users`; keep auth and user-management flows consistent before major refactors.
3. Session settings currently read through scoped/global service path behavior; verify intended precedence if both global and client session settings exist.
4. Login/client/bootstrap flow is customized and should be regression-tested carefully for:
   - no-client system startup
   - first client creation
   - existing client multi-user login

---

## 19. Recommended Validation Checklist After Any Major Change

1. Login with no clients using root admin fallback.
2. Create a client and confirm bootstrap user/settings created.
3. Login through client search + selection and verify scoped data only.
4. Create/edit/delete users and clients; verify audit logs.
5. Create/edit/move/delete tank groups/tanks; verify audit logs.
6. Save reading with parameter image + manual capture + violation image.
7. Verify dashboard last inspection shows values + thumbnails.
8. Verify compliance table status based on inspection frequency.
9. Test PNG/PDF dashboard exports include expanded last-inspection data.

---

## 20. Quick File Map (Most Critical)

- App entry:
  - `lib/main.dart`
- Scope + infra:
  - `lib/core/services/database_mode_service.dart`
  - `lib/core/services/client_repository.dart`
  - `lib/core/services/app_settings_service.dart`
  - `lib/core/services/access_control_service.dart`
- Auth:
  - `lib/features/auth/presentation/pages/login_screen.dart`
  - `lib/features/auth/data/repositories/auth_repository.dart`
- Admin:
  - `lib/features/admin/presentation/pages/admin_dashboard.dart`
  - `lib/features/admin/presentation/pages/admin_settings_page.dart`
- Tanks:
  - `lib/features/tanks/data/models/tank_model.dart`
  - `lib/features/tanks/data/repositories/tank_repository.dart`
  - `lib/features/tanks/data/repositories/tank_tree_repository.dart`
  - `lib/features/tanks/presentation/pages/tank_browser_screen.dart`
- Readings:
  - `lib/features/readings/presentation/pages/reading_entry_state.dart`
  - `lib/features/readings/data/repositories/reading_repository.dart`
- Dashboard:
  - `lib/features/dashboard/presentation/pages/dashboard_tab_state.dart`
  - `lib/features/dashboard/data/repositories/dashboard_stats_repository.dart`
  - `lib/features/dashboard/data/models/dashboard_stats_model.dart`
- Trends:
  - `lib/features/reports/presentation/pages/trends_screen_state.dart`

---

## 21. Final Guidance for Future AI

When modifying this project:

1. Treat **client scope correctness** as highest priority.
2. Avoid adding root DB references for scoped entities.
3. Preserve existing behavior unless explicitly requested.
4. Log only DB-impacting admin mutations in audit.
5. Keep all exports and dashboard summaries deterministic and user-validated.

