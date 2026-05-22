# Screen Flow (Current)

1. `main.dart` initializes Firebase.
2. `AppEntry` checks session validity.
3. If invalid -> `features/auth/presentation/pages/login_screen.dart`.
4. If valid -> `features/home/presentation/pages/home_screen.dart`.
5. Home routes users to:
   - Tank input browser
   - Reading entry flow
   - Dashboard
   - Trends/Reports
   - Admin dashboard (role/path dependent in current code)

## Admin/Tanks Flow
- Admin login -> Admin dashboard -> Tank browser -> Create/Edit tank pages and related widgets.

## Readings Flow
- Tank selection -> Reading entry -> Optional image marker -> Save reading -> Dashboard/report visibility.

