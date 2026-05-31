# VAPLI Feature Modification Handoff Map (Connection.md)

If you want to modify, update, or troubleshoot a feature in the VAPLI application, provide this document along with the specific files and classes outlined under that feature area to the AI. This ensures the AI gets the full context it needs without exceeding token limits or getting lost in unrelated files.

---

## 1. Authentication, Login, or Client Selection
If you are changing how users search for their clients, adding password requirements, setting session limits, or changing login screen behavior:

### Related Files & Paths:
1. **Login Page (UI)**: [login_screen.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/auth/presentation/pages/login_screen.dart) — Handles search, client selector lists, user fields, and validation logic.
2. **Auth Repository**: [auth_repository.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/auth/data/repositories/auth_repository.dart) — Controls login attempts, user locks, password hashes, and user creations.
3. **User Model**: [user_model.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/auth/data/models/user_model.dart) — User attributes, user role fields, and permissions map.
4. **Client Context Tracker**: [client_context_service.dart](file:///c:/Users/muthu/Freelance/vapli/lib/core/services/client_context_service.dart) — Writes selected client scopes to SharedPreferences.
5. **Session Expiration Engine**: [session_manager.dart](file:///c:/Users/muthu/Freelance/vapli/lib/core/utils/session_manager.dart) — Validates session expiry timestamps and deletes sessions on logout.
6. **DB Scope Prefix Logic**: [database_mode_service.dart](file:///c:/Users/muthu/Freelance/vapli/lib/core/services/database_mode_service.dart) — Scopes child operations to client-specific database keys.

---

## 2. Dynamic Reading Forms, Formulations, & Cloudinary Photos
If you want to add a new parameter type (e.g. checkbox), modify mathematical parsing, update the formulas evaluation flow, or adjust Cloudinary image marker workflows:

### Related Files & Paths:
1. **Form UI Shell**: [reading_entry_screen.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/readings/presentation/pages/reading_entry_screen.dart) — Contains the visual layout of parameters.
2. **Form State & Formulas logic**: [reading_entry_state.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/readings/presentation/pages/reading_entry_state.dart) — Handles dependency trees, re-evaluating calculations, capturing images, and validation.
3. **Formula Parser**: [expression_engine.dart](file:///c:/Users/muthu/Freelance/vapli/lib/core/services/expression_engine.dart) — Tokenizes, parses, and evaluates math formulas (`${param_id}`).
4. **Reading Repository**: [reading_repository.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/readings/data/repositories/reading_repository.dart) — Submits finalized readings and filters historical reading lists.
5. **Reading Model**: [reading_model.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/readings/data/models/reading_model.dart) — Declares schema maps and translates database values.

---

## 3. Constraint Engine, Alarm System, or Notification Tones
If you need to change how threshold checks are run, add constraints operators, change alert severity mapping, or update alert resolution buttons:

### Related Files & Paths:
1. **Form State Controller**: [reading_entry_state.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/readings/presentation/pages/reading_entry_state.dart) — Contains `_evaluateAllConstraints` and immediate alarm posting logic.
2. **Alert Model**: [alert_model.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/alerts/data/models/alert_model.dart) — Maps alert records (severity, messages, and snapshots of parameter violations).
3. **Alerts Database Controller**: [alert_reposiotry.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/alerts/data/repositories/alert_reposiotry.dart) — Saves alerts, lists unresolved dashboard indicators, and flags items as resolved.

---

## 4. Tank Structures, Hierarchy Browsers, Node Reordering, or QR Data
If you want to edit tank properties, change how folders are moved or duplicated in the hierarchical tree, or modify QR payload configurations:

### Related Files & Paths:
1. **Tree Browser Screen**: [tank_browser_screen.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/tanks/presentation/pages/tank_browser_screen.dart) & [tank_browser_screen_state.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/tanks/presentation/pages/tank_browser_screen_state.dart) — Tree UI, drag-and-drop targets, and edit nodes dialog boxes.
2. **Tank Creation flows**: [create_tank_screen.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/tanks/presentation/pages/create_tank_screen.dart) & [create_tank_screen_main.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/tanks/presentation/pages/create_tank_screen_main.dart) — Handles properties builder forms and QR image setups.
3. **Tree Repository**: [tank_tree_repository.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/tanks/data/repositories/tank_tree_repository.dart) — Governs folder/leaf CRUD, node moving, reordering lists, and path propagation.
4. **Tank Data Repository**: [tank_repository.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/tanks/data/repositories/tank_repository.dart) — Creates tanks, manages duplication, deletes related sub-collections, and handles Cloudinary QR code removals.
5. **Tank Models**: [tank_model.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/tanks/data/models/tank_model.dart) & [tank_node_model.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/tanks/data/models/tank_node_model.dart) — Outlines tank metadata structures and tree path hierarchies.

---

## 5. Administrative Dashboard, Client Onboarding, & Auditing
If you want to modify client creation/bootstrapping, update user role rankings, assign users to clients, or write custom admin logs:

### Related Files & Paths:
1. **Admin Workspace (UI)**: [admin_dashboard.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/admin/presentation/pages/admin_dashboard.dart) — Tabs for clients, user records, and settings.
2. **Access Security Rules**: [access_control_service.dart](file:///c:/Users/muthu/Freelance/vapli/lib/core/services/access_control_service.dart) — Assigns privileges based on user roles and ranks users.
3. **Client Loader/Bootstrap**: [client_repository.dart](file:///c:/Users/muthu/Freelance/vapli/lib/core/services/client_repository.dart) — Handles client registrations and creates fallback credentials.

---

## 6. Live Dashboard Statistics, Completed Inspections, & Exporters
If you need to change telemetry calculations, modify compliance check indicators, or change summary table export configurations:

### Related Files & Paths:
1. **Dashboard Tab**: [dashboard_tab.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/dashboard/presentation/pages/dashboard_tab.dart) & [dashboard_tab_state.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/dashboard/presentation/pages/dashboard_tab_state.dart) — Visual stats, compliance indicators, and trigger buttons for PDF/PNG exports.
2. **Telemetry Repository**: [dashboard_stats_repository.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/dashboard/data/repositories/dashboard_stats_repository.dart) — Recalculates averages, min/max values, and option counts incrementally.
3. **Telemetry Models**: [dashboard_stats_model.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/dashboard/data/models/dashboard_stats_model.dart) — Defines `ParamStat` objects that map aggregates.

---

## 7. Reports, Trend Analysis, Chart Displays, & Excel Tables
If you need to modify trends filtering, update fl_chart graphing options, or change formatting in Excel reports:

### Related Files & Paths:
1. **Trends Page**: [trends_screen.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/reports/presentation/pages/trends_screen.dart) & [trends_screen_state.dart](file:///c:/Users/muthu/Freelance/vapli/lib/features/reports/presentation/pages/trends_screen_state.dart) — Filtering controls, date picks, and Excel generation algorithms.

---

## 8. Globals, Environment Configuration, & Settings Paths
If you need to register new database nodes, configure API keys, or change global defaults:

### Related Files & Paths:
1. **Global Constants**: [app_constants.dart](file:///c:/Users/muthu/Freelance/vapli/lib/core/constants/app_constants.dart) — Stores routes, paths, and baseline session lifetimes.
2. **Database Mode Scoping**: [database_mode_service.dart](file:///c:/Users/muthu/Freelance/vapli/lib/core/services/database_mode_service.dart) — Manages global vs client-scoped collection sets.
3. **Application Settings Service**: [app_settings_service.dart](file:///c:/Users/muthu/Freelance/vapli/lib/core/services/app_settings_service.dart) — Reads and writes global or client-specific configurations.
4. **Environment Secrets**: [env_config.dart](file:///c:/Users/muthu/Freelance/vapli/lib/core/services/env_config.dart) — Loads variables from environment configs.
5. **App Bootstrap Entry**: [main.dart](file:///c:/Users/muthu/Freelance/vapli/lib/main.dart) — Initializes Firebase options, Environment configurations, and development test administrators.
