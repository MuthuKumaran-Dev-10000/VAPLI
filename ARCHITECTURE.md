# VAPLI Refactored Architecture

## Goal
Feature-first structure optimized for safe incremental refactor and AI-assisted development.

## Structure

```
lib/
  core/
    constants/
    theme/
    utils/
  features/
    auth/
    admin/
    tanks/
    readings/
    dashboard/
    reports/
    home/
    alerts/
  main.dart
```

## Layer Rules

1. `presentation` handles UI and interaction only.
2. `data/repositories` handles Firebase and external IO.
3. Models are colocated per feature under `data/models`.
4. Cross-feature use should happen through explicit imports, not shared giant files.
5. New files should stay small and single-responsibility.

## Current Note

This refactor reorganizes all `lib` files into feature folders while preserving existing behavior code paths.
