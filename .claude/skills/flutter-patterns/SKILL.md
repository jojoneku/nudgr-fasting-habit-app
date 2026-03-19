---
name: flutter-patterns
description: Comprehensive Flutter development patterns covering widgets, animations, and performance. Use when you need quick reference for Flutter best practices, common UI patterns, performance optimization, or animation implementations.
metadata:
  source: https://github.com/cleydson/flutter-claude-code
  version: 1.0.0
---

# Flutter Patterns

A comprehensive collection of battle-tested Flutter patterns for building production-quality applications.

## Overview

This skill provides quick-reference patterns for:
- **Widget Patterns** — Cards, lists, forms, dialogs, loading/empty/error states, Material 3
- **Animation Patterns** — Implicit/explicit animations, page transitions, Hero, shimmer
- **Performance Checklist** — Pre-deployment checklist for 60fps, build optimization, memory

## When to Use This Skill

- Need a standard Flutter UI pattern (card, list, dialog, bottom sheet)
- Implementing animations (fade, slide, scale, Hero, staggered)
- Pre-deployment performance review
- Material 3 widget implementations (NavigationBar, SegmentedButton, SearchAnchor)
- Responsive layout patterns

## Pattern Files

| Category | File | Contents |
| --- | --- | --- |
| Widget patterns | `patterns/flutter-widget-patterns.md` | Cards, lists, forms, dialogs, loading/empty states, Material 3 |
| Animation patterns | `patterns/flutter-animation-patterns.md` | Implicit, explicit, page transitions, Hero, shimmer, stagger |
| Performance checklist | `patterns/flutter-performance-checklist.md` | Build config, Impeller, const widgets, list perf, memory |

## Project-Specific Notes

This project uses:
- **State**: `ChangeNotifier` + `ListenableBuilder` (not Provider/BLoC/Riverpod)
- **Theme**: Dungeon/RPG dark aesthetic — use `AppColors` tokens, not `Theme.of(context).colorScheme`
- **Animations**: 150–300ms micro-interactions, ≤ 400ms max (stricter than Material 3 defaults)
- **Touch targets**: ≥ 44×44px; primary actions in bottom 30% of screen

## Quick Examples

**Card (The System style)**
```dart
Container(
  decoration: BoxDecoration(
    color: AppColors.surface,
    border: Border.all(color: AppColors.border, width: 1),
    borderRadius: BorderRadius.circular(12),
  ),
  padding: const EdgeInsets.all(16),
  child: child,
)
```

**ListenableBuilder pattern**
```dart
ListenableBuilder(
  listenable: presenter,
  builder: (context, _) => Text(presenter.formattedTime),
)
```

**Animation within project constraints**
```dart
AnimatedContainer(
  duration: const Duration(milliseconds: 250), // 150-300ms range
  curve: Curves.easeInOut,
  // ...
)
```
