# VAPLI End-to-End Test Cases

## 1) Scope
This suite validates:
- Auth + client bootstrap
- Roles/permissions
- Tank tree (folders/subfolders/tanks)
- Parameter schema parity in reading page
- Constraints (single + multiple)
- Autofill (current values + `(last)` previous capture)
- Dashboard stats/alerts/completed
- Trends visualization + XLSX data correctness
- Minimum 50 readings (10 per tank, 5 tanks) with varied timestamps

Note: Image capture deep-testing is excluded by request.

## 2) Test Environment
- Build: latest local build from current branch
- Database: Firebase Realtime Database (scoped mode)
- Default root fallback (no clients): `admin / Admin@123`

## 3) Test Data Setup

### 3.1 Users and Clients
- Create clients:
  - `Client_A` (`client_a`)
  - `Client_B` (`client_b`)
- Create users:
  - `sa_a` role `super admin` (Client_A)
  - `admin_a` role `admin` (Client_A)
  - `user_a1` role `user` (Client_A)
  - `user_a2` role `user` (Client_A)
  - `admin_b` role `admin` (Client_B)
  - `user_b1` role `user` (Client_B)

### 3.2 Tank Tree and Tanks (Client_A)
Create structure:
- `Plant-1`
  - `Line-1`
    - Tank `TK-A1` (Tank name `Hydraulic A1`)
    - Tank `TK-A2` (Tank name `Gearbox A2`)
  - `Line-2`
    - Tank `TK-A3` (Tank name `Compressor A3`)
- `Plant-2`
  - `Line-3`
    - Tank `TK-A4` (Tank name `Coolant A4`)
    - Tank `TK-A5` (Tank name `Pump A5`)

### 3.3 Parameter Sets

Use these in each tank (adapted by tank where needed):
- `Oil Level` (`number`, required, `keep_previous_capture=true`)
- `Oil Temp` (`number`, required)
- `Vibration` (`slider`, min 0 max 100)
- `Condition` (`dropdown`: Good/Monitor/Critical)
- `Before/After Pressure` (`dual_text`)
- `Remarks` (`multiline`)
- `Consumption` (`number`, autofill)
  - Expression: `${oil_level} - ${oil_level__last}`
  - Display expression should show `Oil Level - Oil Level (last)`

Constraint samples:
- Single constraint case:
  - `Oil Temp > 90` => warning
- Multiple constraints case:
  - `Oil Temp > 90` warning
  - `Oil Temp > 100` critical + block submission

## 4) Test Cases

### AUTH + CLIENT + PERMISSION

TC-001 Root bootstrap login  
Steps:
1. Ensure no clients exist (or use fresh DB).
2. Login with `admin / Admin@123`.
Expected:
- Login succeeds.
- Admin area accessible.

TC-002 Client bootstrap creation  
Steps:
1. Create `Client_A`.
2. Inspect DB under `client_a`.
Expected:
- `client_a/users/admin` equivalent bootstrap user exists.
- `client_a/system_settings/session` exists.

TC-003 Client search/login flow  
Steps:
1. On login page type `Cli` and pick `Client_A`.
2. Login as `admin_a`.
Expected:
- Session scoped to `client_a`.
- No `client_b` data visible.

TC-004 Super admin permission check  
Steps:
1. Login `sa_a`.
2. Open admin tabs.
Expected:
- Can manage Clients/Users/Settings/Tanks.

TC-005 Admin permission check  
Steps:
1. Login `admin_a`.
Expected:
- Can manage users/tanks per allowed policy.
- Restricted super-admin-only actions hidden/blocked.

TC-006 User permission check  
Steps:
1. Login `user_a1`.
Expected:
- Can perform assigned operational flows (readings/reports as designed).
- Cannot access restricted admin operations.

TC-007 Cross-client isolation  
Steps:
1. Login `admin_b` on `Client_B`.
Expected:
- Cannot view `Client_A` tanks/readings/alerts.

### TANK TREE + SCHEMA

TC-010 Create folders/subfolders/tanks  
Steps:
1. Build tree from section 3.2.
Expected:
- Nodes persist and reload correctly.

TC-011 Reorder/move nodes  
Steps:
1. Move `TK-A5` from `Plant-2/Line-3` to `Plant-1/Line-2`.
Expected:
- Tree + linked tank references remain valid.

TC-012 Parameter parity on reading page  
Steps:
1. Open each tank reading page.
Expected:
- Field list/order/type matches tank inspection properties exactly.

### PREVIOUS CAPTURE + AUTOFILL

TC-020 Previous-capture toggle persistence  
Steps:
1. Enable `keep_previous_capture` for `Oil Level` in tank parameter builder.
2. Save tank, reopen parameter editor.
Expected:
- Toggle remains enabled.

TC-021 Session picker shows `(last)` token  
Steps:
1. Edit autofill expression for `Consumption`.
2. Open parameter picker.
Expected:
- Shows both `Oil Level` and `Oil Level (last)` entries.

TC-022 First-read fallback to zero  
Steps:
1. Ensure no `Previouscapture/...` path exists for tank.
2. Enter `Oil Level=55`.
3. Check autofill `Consumption = Oil Level - Oil Level(last)`.
Expected:
- `Consumption=55` (last value resolved as `0`).
- No null/NaN/error.

TC-023 Save writes previous capture path  
Steps:
1. Save reading with `Oil Level=55`.
2. Check DB path `Previouscapture/<tankName>/<oilLevelParamId>/<Oil Level>`.
Expected:
- Path exists with value `55` (or numeric equivalent).

TC-024 Subsequent read uses stored previous  
Steps:
1. Next reading enter `Oil Level=48`.
Expected:
- `Consumption = 48 - 55 = -7`.

TC-025 Non-last missing dependency still blocks autofill  
Steps:
1. Clear current dependency input (not `(last)` token).
Expected:
- Autofill shows dependency-missing behavior (not silent 0 for current token).

### CONSTRAINTS

TC-030 Single constraint alert  
Steps:
1. For `TK-A1`, enter `Oil Temp=95` (single warning rule).
Expected:
- Violation banner shown.
- Alert written in DB (`alerts` and/or `alerts_full` per config).

TC-031 Multiple constraints severity escalation  
Steps:
1. For `TK-A2`, enter `Oil Temp=105` (warning + critical-block).
Expected:
- Critical shown.
- Save blocked if block flag configured.

TC-032 Constraint clear removes live alert  
Steps:
1. Trigger alert, then change value to normal.
Expected:
- Live alert record removed/updated per current behavior.

### DASHBOARD + ALERTS + COMPLETED

TC-040 Dashboard reflects new readings  
Steps:
1. Save multiple readings for each tank.
Expected:
- Last inspection values update.
- Compliance and stats update.

TC-041 Complete alert flow  
Steps:
1. Complete one open alert from dashboard.
Expected:
- Entry appears under completed tasks.
- Original alert acknowledged/updated.

TC-042 Dashboard export sanity  
Steps:
1. Export alerts PNG and dashboard PDF.
Expected:
- Files generated and contain current data panels.

### TRENDS + XLSX VALIDATION

TC-050 Trend chart per parameter type  
Steps:
1. Select each tank and plot number/slider/dual/dropdown params.
Expected:
- Correct chart mode renders.

TC-051 Date-range filtering  
Steps:
1. Use week/month/custom windows.
Expected:
- Points included/excluded correctly by capture time.

TC-052 XLSX content validation  
Steps:
1. Export Excel report.
2. Validate:
   - Summary sheet row count = saved records in selected range.
   - Tank sheet values match entered values.
   - Photo URL columns present for capture-image params.
Expected:
- 100% value parity with DB/source entries.

TC-053 Abnormality PDF validation  
Steps:
1. In Trends abnormality section choose Daily/Weekly/Monthly and type variants.
2. Export PDF.
Expected:
- Rows match `alerts`/`completed_tasks` filters for selected tank and range.

## 5) 50-Reading Execution Plan (10 per tank)

Use these timestamps to ensure variation (local time):
- D-5: 08:10, 14:35
- D-4: 09:00, 17:20
- D-3: 07:45, 12:50
- D-2: 10:15, 19:05
- D-1: 06:55, 16:40

For each tank (`TK-A1..TK-A5`) create 10 readings at above slots.

Per reading minimum fields:
- `Oil Level` numeric
- `Oil Temp` numeric (mix normal/warning/critical)
- `Vibration` slider
- `Condition` dropdown
- `Before/After Pressure` dual values
- `Consumption` autofill
- `Remarks`

Recommended pattern per tank:
- Readings 1-2: normal
- 3: warning temp
- 4: normal
- 5: critical temp (for tanks with block rule, verify save blocked once then corrected)
- 6-10: mixed, including one low oil-level delta to verify `(last)` pulls

## 6) DB Verification Checklist
- `client_a/tanks` schema contains `keep_previous_capture` on expected params.
- `client_a/Previouscapture/<tank>/<paramId>/<paramLabel>` created/updated after each save.
- `client_a/readings` count increments to 50.
- `client_a/dashboard_stats` updated for all 5 tanks.
- `client_a/alerts`, `client_a/alerts_full`, `client_a/completed_tasks` reflect triggered/completed cases.

## 7) Pass/Fail Criteria
- All critical tests TC-001..TC-053 pass.
- 50 readings saved (after intentional blocked attempts corrected).
- XLSX parity check passes for all 5 tank sheets + summary.
- `(last)` autofill behavior correct on first read (0 fallback) and subsequent reads (DB-based previous value).

