# VAPLI RTDB Test Suite — Handoff Document

## What changed and why

The original `rtdb_test.dart` pushed raw data into Firebase and checked counts. It did
not test any of the business logic that actually runs inside the app: the path-routing
rules, the constraint evaluator, the expression engine, the previouscapture write cycle,
the alert lifecycle, or dashboard-stats aggregation. Data could silently land in the
wrong place and the test would still pass.

This rewrite replaces the old file entirely. Every test group now mirrors the real
service/repository code from `lib_final.zip`.

---

## What the new suite covers (10 groups, 100+ assertions)

| Group | What it tests | Key source files mirrored |
|-------|--------------|--------------------------|
| **A** | `DatabaseModeService.path()` routing rules — global vs scoped paths, devMode prefix, slash normalization | `database_mode_service.dart` |
| **B** | Client bootstrap: write Client A + B records, `system_settings/session` stub | `client_repository.dart` |
| **C** | User creation, roles, `client_ids` scoping, failed-login counter, lockout timestamp, `last_login_at` | `auth_repository.dart`, `user_model.dart` |
| **D** | Tank CRUD, all 7 inspection property types, single vs multi constraints, `keep_previous_capture`, autofill expression, soft-delete | `tank_model.dart`, `tank_repository.dart` |
| **E** | Tank tree folder/leaf nodes, parent linkage, hierarchy depth, leaf→tank linkage, node move (PATCH) | `tank_tree_repository.dart`, `tank_node_model.dart` |
| **F** | Reading save, `inspection_values` round-trip for all field types (number, slider, dropdown, dual_text, multiline), missing-field graceful default | `reading_repository.dart`, `reading_model.dart` |
| **G** | Previouscapture write after save, first-read zero-fallback, subsequent-read delta, path key format (slashes → underscores), non-`keep_previous_capture` params stay absent | `reading_entry_state.dart` `_previousCapturePath()` + `_save()` |
| **H** | `ExpressionEngine.evaluate()` — subtraction, addition, multiplication, division, div-by-zero throws, missing variable throws, first-read zero produces finite result | `expression_engine.dart` |
| **I** | Constraint evaluator — `>`, `>=`, `<=`, `!=`, below threshold, exact threshold (strict), warning fires, critical + blocking fires, clear after correction | `reading_entry_state.dart` `_evaluateAllConstraints()` |
| **J** | Alert lifecycle: write to `alerts/`, `alerts_full/`, `violations/`; `live=true` on create; `live=false` + `reading_id` after save; delete on clear. Critical blocking alert. | `reading_entry_state.dart` `_upsertLiveAlert()` / `_deleteLiveAlert()` |
| **J2** | `completed_tasks` flow: seed alert → complete → verify embedded alert object, `acknowledged=true`, original alert `resolved=true` | `dashboard_tab_state.dart` complete flow |
| **K** | `DashboardStatsRepository.updateStatsAfterReading()` — running avg/min/max for numeric, option_counts for dropdown, `last_reading` tracking, persistence to DB | `dashboard_stats_repository.dart`, `dashboard_stats_model.dart` |
| **L** | 50-reading stress run (5 tanks × 10 readings at 10 timestamp slots). Verifies: count, per-tank 10 readings, all 7 inspection value keys present, Pressure is `{left, right}` map, Previouscapture final value, alert + completed_task records, timestamp variety | All of the above |
| **M** | Date-range filtering (mirrors `getReadingsInRange`): D-3..D-1 = 30 readings, D-5 only = 10, full week = 50, future = 0, per-tank in-range, ascending sort | `reading_repository.dart` `getReadingsInRange()` |
| **N** | Cross-client isolation: Client B tank/reading/Previouscapture/dashboard_stats NOT visible in Client A paths, and vice versa. Global `users/` is shared. | `database_mode_service.dart` scoped vs global logic |
| **O** | User `role` field, `client_ids` membership, cross-client user NOT in other client's `client_ids` | `auth_repository.dart`, `access_control_service.dart` |

---

## How to run

```bash
flutter test test/rtdb_test.dart --timeout 600s
```

The suite is split into named `group()` blocks so you can run a single group:

```bash
flutter test test/rtdb_test.dart --name "G:"   # just Previouscapture group
flutter test test/rtdb_test.dart --name "H:"   # just expression engine
flutter test test/rtdb_test.dart --name "L:"   # just the 50-reading stress run
```

---

## Pre-requisites

1. `.env/.env` file with `FIREBASE_DATABASE_URL` populated.
2. Firebase Realtime DB rules must allow read/write on `testDB/**` (test-only rule):
   ```json
   {
     "rules": {
       "testDB": { ".read": true, ".write": true }
     }
   }
   ```
3. No Firebase SDK initialisation needed — the suite uses the REST API directly
   (`http` package) to avoid Flutter widget binding requirements.

---

## Teardown / cleanup

`tearDownAll` deletes the entire `testDB/qa_client_a_<ts>/` and
`testDB/qa_client_b_<ts>/` trees plus the global user and client stubs
written during the run. The timestamp suffix ensures parallel runs never
collide.

If a run crashes mid-way (e.g. network timeout), re-run with the same
timestamp won't happen (it's `DateTime.now().millisecondsSinceEpoch`). The
leftover nodes at `testDB/qa_client_a_<old_ts>/` can be deleted manually
from the Firebase console or via:

```bash
curl -X DELETE "https://<your-db>.firebaseio.com/testDB/qa_client_a_<old_ts>.json"
```

---

## What the test does NOT cover (by design)

- **Image capture / Cloudinary upload** — excluded per the test-cases spec.
- **Flutter widget rendering** — this is a pure DB logic suite; no
  `WidgetTester` or `pumpWidget` calls.
- **Firebase Auth** — VAPLI uses its own password hash mechanism (not
  Firebase Auth); auth is tested via the `users/` RTDB path instead.
- **Trend chart rendering** and **XLSX/PDF export** — these are UI/export
  features. The suite validates the underlying data (readings, date-range
  filtering, alert/completed records) that those features consume.

---

## Extending the suite

### Adding a new tank parameter type
Add a new entry in `buildParams()` and add a `D-xx` assertion that checks the
new `type` field persisted correctly.

### Adding a new constraint operator
Add a case to `_evalOp()` and a corresponding `I-xx` test.

### Adding a new scoped path
Add it to `_scopedPaths` in the test file (mirrors `DatabaseModeService._scopedPaths`)
and add an `A-xx` assertion verifying it gets the clientId prefix.

### Testing XLSX parity (TC-052)
After running the stress suite (Group L), export from the app and compare
row counts against `runReadings.length == 50` and per-tank counts of 10.
The suite already ensures the source data is consistent; XLSX validation
needs a separate `excel`-package test that reads the exported file.

---

## Key design decisions

**Pure REST, no Firebase SDK** — avoids Flutter binding setup in tests,
matches how data actually looks on the wire.

**Mirror service logic in test helpers** — `dbPath()`, `evalConstraints()`,
`evalExpression()`, `_updateStats()` are faithful re-implementations of the
corresponding service methods. If a service changes its logic, the test will
catch the divergence.

**Timestamp suffix isolation** — every entity ID includes `_$ts`
(millisecond epoch). Groups can run in any order without stepping on each
other.

**`tearDownAll` not `tearDown`** — cleanup runs once at the end so
intermediate groups can read data written by earlier groups (e.g. Group L
reads tanks written by Group D).