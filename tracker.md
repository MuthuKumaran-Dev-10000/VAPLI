# Workspace Refactoring Tracker (tracker.md)

This file tracks all recent feature updates, bug fixes, refactoring work, and verification details in the codebase.

---

## 1. Reading Capture Flow Refactor

### Issue
The reading save functionality suffered from post-navigation timing issues where screens popped before writing operations fully completed. Also, sequential inspections of assets in the same folder required manually returning to the folder browser to open the next asset.

### Solution
- **Fully Enforced Save Completion**: Ensured all asynchronous writes (`saveReading`, `updateStatsAfterReading`, `_auditReadingSave`, `previousCapture` backups, and Firebase alert node updates) are completed and awaited before any navigation logic is scheduled.
- **Sequenced Folder Navigation**: Enabled the `ReadingEntryScreen` to accept the sibling leaf models and active tank index.
- **Auto-Navigation Sequence**: After a successful save, a 3-second delay is scheduled. If there are sibling tanks left in the current folder, it pops back to `TankInputBrowser` with an instruction payload `{'action': 'select_tank', 'tank_id': nextTank.id}`. The browser then automatically updates the active leaf details to that next tank so the user can verify tank info before taking the next reading.
- **Sequence Termination**: Once the final tank in the folder sequence is successfully saved, it pops back to `TankInputBrowser` with `{'action': 'clear_selection'}` to clear the active leaf details selection and return the user to the folder list contents view.
- **Failure Boundary**: If any save operation throws an error, the screen remains open, stops the navigation timer, and displays the error message, enabling retry operations.

### Changes Log
* **[MODIFY] [reading_entry_screen.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/readings/presentation/pages/reading_entry_screen.dart)**:
  * Updated `ReadingEntryScreen` constructor to accept optional `List<TankModel>? siblingTanks` and `int? currentTankIndex` parameters.
* **[MODIFY] [tank_input_browser.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/home/presentation/pages/tank_input_browser.dart)**:
  * Modified `_LeafDetail` to accept `onTakeReading` callback instead of hardcoded route.
  * Added pop results handler inside `onTakeReading` to update selection to the next tank in sequence.
  * Removed path string truncation and ellipsis clipping from `_LeafDetail` and `_PathLabel` to prevent text truncation.
* **[MODIFY] [reading_entry_state.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/readings/presentation/pages/reading_entry_state.dart)**:
  * Modified the `_save()` completion delay block to pop with action selection payloads (`select_tank` or `clear_selection`).

---

## 2. Alert Lifecycle Bug Fix

### Issue
Alerts were filtered by day boundary (`_isToday(a.timestamp)`), causing active alerts to disappear from screens at midnight even if they had not been completed/resolved.

### Solution
- Introduced a state field `status` with a default value of `'active'`.
- Configured active lists to filter by `!acknowledged && status != 'COMPLETED'` to ensure alerts remain visible across date boundaries.
- Configured task completion handlers to set the status to `'COMPLETED'` and log resolved entries.

### Changes Log
* **[MODIFY] [alert_model.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/alerts/data/models/alert_model.dart)**:
  * Added `status` field to the class, mapping, serialization, and constructor.
* **[MODIFY] [_alert_model.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/dashboard/presentation/pages/dashboard_models/_alert_model.dart)**:
  * Added `status` field to dashboard model mappings.
* **[MODIFY] [alert_reposiotry.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/alerts/data/repositories/alert_reposiotry.dart)**:
  * Set `'status': 'active'` upon alert creation.
  * Set `'status': 'COMPLETED'` when resolving alerts.
* **[MODIFY] [reading_entry_state.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/readings/presentation/pages/reading_entry_state.dart)**:
  * Appended `'status': 'active'` to draft alert writes in `_writeLiveAlertWithPhoto`.
  * Added active alerts stream listener subscription (`_activeAlertsSub`) inside `initState()` filtering by unresolved active statuses.
  * Rendered a visual active alerts list panel below the `_MetaCard` widget.
  * Canceled active alerts stream listener in `dispose()`.
* **[MODIFY] [dashboard_tab_state.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/dashboard/presentation/pages/dashboard_tab_state.dart)**:
  * Added `'status': 'active'` to average alert creations (`_checkExpectedAvgAlerts`).
  * Updated `_completeAlert()` to write `'status': 'COMPLETED'` to `/alerts/${alert.id}`.
  * Removed `_isToday` filtering from the `_todayOpenAlerts` list getter.
  * Renamed the section header from `"TODAY'S TASKS"` to `"ACTIVE ALERTS"` in `_buildAlertsPanel()`.
  * Updated `_downloadAlertsPdf()` queries to include all unresolved active alerts regardless of selected report date windows.
* **[MODIFY] [trends_screen_state.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/reports/presentation/pages/trends_screen_state.dart)**:
  * Updated `_alertStatus` status check mapping to correctly display completed entries.

---

## 3. Duplicate Reading Validation & Historical Upload Permission

### Issue
- **Duplicate Reading Capture**: Inspectors could submit redundant duplicate readings for the same asset within a short timeframe (e.g. 20-30 minutes) without prompt, cluttering dashboard data and reports.
- **Historical Upload**: No option existed for high-privilege users (e.g. with `historical_upload` privilege) to adjust/edit the Capture Start Date and Capture End Date during entry.

### Solution
- **Duplicate Detection**: On page load, the screen checks if a reading was captured for the current asset in the last 30 minutes. If yes, it displays a premium YES/NO dialog warning the inspector. If they select NO, the inspection form closes. If they select YES, a mandatory text prompt appears requiring a reason (which cannot be empty). The reason is saved under `'duplicate_reason'` inside the reading's `inspectionValues`.
- **Privileged Historical Edit**: Checked if the active user possesses the `historical_upload` privilege using `AccessControlService.can(...)`. If authorized, the Capture Start Date and Capture End Date rows render with calendar edit icons and are tappable. Tapping prompts the date and time picker dialogs to override `_capturedAtStart` and `_capturedAtCustom` (which is saved as `capturedAt`).
- **Data Integration**: Added customized values and `duplicate_reason` to the reading log, which propagates to the dashboard and reports.

### Changes Log
* **[MODIFY] [reading_entry_screen.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/readings/presentation/pages/reading_entry_screen.dart)**:
  * Imported `AccessControlService` for authorization verification.
* **[MODIFY] [reading_entry_state.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/readings/presentation/pages/reading_entry_state.dart)**:
  * Modified `_capturedAtStart` to be mutable, declared `_capturedAtCustom` and `_duplicateReason` state fields.
  * Added `_endLabel` getter.
  * Initialized `_capturedAtCustom = _capturedAtStart` in `initState()` and scheduled `_checkDuplicateReading()` post frame callback.
  * Added `_checkDuplicateReading()` query and warning popup flow.
  * Added `_pickDateTime()`, `_editStartDate()`, and `_editEndDate()` custom pickers.
  * Passed custom date and duplicate reason value under `inspectionValues` in the `_save()` routine.
  * Updated the `_MetaCard` instantiation in the build tree to forward edit handlers and labels when historical permission is active.
* **[MODIFY] [dashboard_tab_state.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/dashboard/presentation/pages/dashboard_tab_state.dart)**:
  * Updated `_buildParameterCell` to use `pw.Wrap` for values/trend arrows, preventing text overflow in narrow columns.
  * Added a dedicated "Duplicate Reason" column and configured widths inside the completed readings table in the Inspection Report PDF (`_downloadInspectionReportPdf`).

---

## 4. Verification & Diagnostic Checks
* Verified project build integrity and clean compilation via `flutter analyze`.
* Ensured null-safe type operations and references are preserved.
