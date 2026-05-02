# Plan 017W — Design-System Widget Library

> Depends on **017** (tokens + ThemeData) being merged.
> Blocks **017a–017h** (page plans).

## Goal

Architect a small, tightly-scoped widget library that every page in the app composes from. Built on three principles:

1. **Lean on Material 3.** When the framework already has a themed primitive (`Card`, `FilledButton`, `ListTile`, `Chip`, `TextField`, `BottomSheet`, `Dialog`, `SegmentedButton`, `NavigationBar`), we use it. Our `App*` widget is a thin convenience wrapper that bakes in our defaults — not a from-scratch reinvention.
2. **Pull packages where they pay rent.** `flex_color_scheme` for ThemeData generation, `skeletonizer` for loading states. Anything else stays custom.
3. **Custom only what's genuinely missing.** Cards with header/slot composition, bottom sheet structure, empty/error states, stat pills, ring progress, number displays, toast helper, plus HIG-flavored layouts (action sheet, inset grouped list, large title scaffold).

The widget set was sized against the actual codebase scan (see notes below). **26 primitives total** — every one is justified by 3+ recurrences across modules or by the M3 + HIG taste brief.

---

## Package Additions

| Package | Why | Where Used |
|---|---|---|
| `flex_color_scheme` | Generates M3 light + dark `ThemeData` with all component sub-themes pre-configured. Eliminates ~70% of hand-rolled `*Theme` config in 017 Phase 2. | 017 (Theme wiring) |
| `skeletonizer` | Wrap any widget subtree to render as a shimmering skeleton. Removes need for hand-built per-list skeleton widgets. | `AppLoadingState`, list views during initial load |
| `gap` *(optional)* | `Gap(16)` instead of `SizedBox(height: 16)`. Pure QoL. | Inside system widgets only — don't propagate to pages this overhaul |

**Not added:** `fl_chart`, `flutter_animate`, `auto_size_text`, extra icon packs. Each is a separate future decision.

---

## Codebase Scan Findings (informs API choices)

The codebase audit (Nov 2025) found these recurring patterns. Each justifies a primitive:

| Pattern | Recurrence | Primitive |
|---|---|---|
| `Container` + `BoxDecoration` card | 30+ | `AppCard` |
| `showModalBottomSheet` + drag handle + header | 19 files | `AppBottomSheet` |
| `ListTile` wrapped in styled `Container` | 28+ files | `AppListTile` |
| Tap-scale animation (GestureDetector + ScaleTransition 0.92, 150ms) | 10+ | `AppPressable` |
| Status chip with color-coded fill + border | 23 files | `AppStatPill` / `AppBadge` |
| Filled buttons full-width 48-52px | 32 files | `AppPrimaryButton` |
| `TextField` with filled bg + radius 12-14 | 22 files | `AppTextField` |
| Large bold number (timer / kcal / amount) | 15+ files | `AppNumberDisplay` |
| Circular progress + centered icon (Stack) | quests | `AppCircularProgress` |
| Custom partial ring with glow | fasting | `AppRingProgress` |
| Linear progress bar wrapped with label | 8+ | `AppLinearProgress` |
| `Dismissible` swipe-to-delete on rows | 6+ | `AppListTile.onDelete` |
| Empty / loading screens (centered icon + text) | 8+ | `AppEmptyState`, `AppLoadingState` |
| Section header (title + optional hint/action) | 12 | `AppSection` |
| `Scaffold` + flat AppBar + padded body | every screen | `AppPageScaffold` |
| 44×44 rounded-square icon container (tonal fill) | hub, lists | `AppIconBadge` |
| Day-of-week chip row (custom layout) | nutrition | `AppDayChipRow` |
| Long-press → custom bottom sheet menu (action list) | quests, treasury, fasting history | `AppActionSheet` (HIG) |
| Settings-style grouped list (not present yet, but settings overhaul wants it) | settings (017h) | `AppGroupedList` + `AppListTile.insetGrouped` (HIG) |
| Top-level destination needs strong page identity | hub, stats, settings | `AppPageScaffold.large()` (HIG) |

**Inconsistencies the library will fix:**
- TextField padding (currently 14–16, 10–12) → standardize 16, 12
- ListTile contentPadding (14,6 vs 16,8) → 16, 8
- Surface radius (12 vs 16) → 16 default, 12 for inputs
- Button height (48 vs 52 full-width) → 52
- Chip padding (6,2 vs 8,3) → 6,2 small / 10,4 medium / 14,6 pill

---

## Library Layout

```
lib/views/widgets/system/
├── system.dart                 # barrel — re-exports everything
├── foundation/
│   ├── app_pressable.dart
│   ├── app_page_scaffold.dart  # standard + .large() factory (HIG large title)
│   ├── app_section.dart
│   └── app_card.dart
├── overlays/
│   ├── app_bottom_sheet.dart
│   ├── app_action_sheet.dart   # HIG action sheet — list of choices
│   ├── app_dialog.dart
│   ├── app_confirm_dialog.dart
│   └── app_toast.dart
├── lists/
│   ├── app_list_tile.dart      # standard + insetGrouped variant
│   ├── app_grouped_list.dart   # HIG inset grouped container (sections + tiles)
│   ├── app_selectable_tile.dart
│   ├── app_empty_state.dart
│   ├── app_error_state.dart
│   └── app_loading_state.dart
├── indicators/
│   ├── app_linear_progress.dart
│   ├── app_circular_progress.dart
│   ├── app_ring_progress.dart
│   ├── app_number_display.dart
│   ├── app_stat_pill.dart
│   ├── app_badge.dart
│   └── app_icon_badge.dart
└── inputs/
    ├── app_primary_button.dart
    ├── app_secondary_button.dart
    ├── app_destructive_button.dart
    ├── app_icon_button.dart
    ├── app_text_field.dart
    ├── app_segmented_control.dart
    └── app_day_chip_row.dart
```

Total: 26 primitives, organized in 5 folders.

---

## Phase 1 — Foundation Primitives

### `AppPressable`
> Wraps a tappable widget with the app-wide tap-scale animation (replaces 10+ ad-hoc GestureDetector + AnimationController setups).

```dart
AppPressable({
  required Widget child,
  VoidCallback? onTap,
  VoidCallback? onLongPress,
  double pressedScale = 0.97,
  Duration duration = AppMotion.micro, // 150ms
  bool haptic = true, // light haptic on tap
})
```

**Notes:** Uses `AnimatedScale` internally — no controller boilerplate. `haptic` calls `HapticFeedback.lightImpact()` on tap.

---

### `AppPageScaffold`
> Standard page chrome — `Scaffold` + flat `AppBar` + padded body + safe area + optional pull-to-refresh. `.large()` factory provides the HIG collapsing-large-title pattern.

```dart
AppPageScaffold({
  String? title,
  Widget? titleWidget,           // overrides title
  List<Widget> actions = const [],
  Widget? leading,                // null = auto back if canPop
  required Widget body,
  Widget? floatingActionButton,
  Widget? bottomNavigationBar,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: AppSpacing.md),
  Future<void> Function()? onRefresh, // wraps body with RefreshIndicator
  Color? backgroundColor,        // null = theme default
  bool showAppBar = true,
})

// HIG large-title variant — title grows on scroll-up, collapses on scroll-down
AppPageScaffold.large({
  required String title,
  String? subtitle,              // small line under title
  List<Widget> actions = const [],
  Widget? leading,
  required List<Widget> slivers, // body must be sliver-aware (use SliverList, SliverToBoxAdapter)
  Widget? floatingActionButton,
  Widget? bottomNavigationBar,
  Future<void> Function()? onRefresh,
  Color? backgroundColor,
})
```

**Notes:**
- Standard form uses `AppBar`; `.large()` uses `SliverAppBar.large` inside a `CustomScrollView` so the title transitions smoothly. Title font size grows from `titleLarge` (collapsed) to `headlineMedium` (expanded).
- `.large()` is the HIG default for top-level destinations (Hub, Stats, Settings, Treasury home). Standard form is used for all other screens.
- `AppBar` reads from `theme.appBarTheme` (set by `flex_color_scheme`). `RefreshIndicator` color follows theme automatically.

---

### `AppSection`
> Section block — title + optional hint or trailing action, then body. Standard `lg` top margin.

```dart
AppSection({
  required String title,
  String? hint,                  // small italic line below title
  Widget? trailing,              // typically TextButton "See all"
  required Widget child,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
})
```

**Notes:** Title uses `titleMedium` (sentence case enforced by convention, not code). Hint uses `bodySmall` low-emphasis.

---

### `AppCard`
> M3 `Card` with optional header/footer slots and built-in `AppPressable` for tap support.

```dart
AppCard({
  Widget? header,
  required Widget child,
  Widget? footer,
  AppCardVariant variant = AppCardVariant.elevated, // elevated | filled | outlined | tonal
  EdgeInsetsGeometry padding = const EdgeInsets.all(AppSpacing.md),
  VoidCallback? onTap,
  VoidCallback? onLongPress,
  BorderRadius? borderRadius,    // null = AppRadii.lg (16px)
  Color? color,                  // override surface
})
```

**Notes:** Wraps `Card` (which already does elevation/tint via theme). Header/footer separated by an `AppSpacing.sm` gap inside the card. If `onTap` set, child is wrapped in `AppPressable`.

---

## Phase 2 — Overlays (Sheets, Dialogs, Toasts)

### `AppBottomSheet`
> Standard bottom sheet structure — drag handle, header (title + optional close), scrollable body, action row.

```dart
class AppBottomSheet {
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    Widget? trailing,           // e.g. info icon, toggle
    required Widget body,
    Widget? primaryAction,      // typically AppPrimaryButton
    Widget? secondaryAction,    // typically AppSecondaryButton or AppDestructiveButton
    bool isScrollControlled = true,
    bool isDismissible = true,
    bool useDraggableScrollableSheet = false,
    double? initialChildSize,    // for draggable variant
  });
}
```

**Notes:**
- Drag handle: 40×4px, `AppRadii.sm`, `colorScheme.outlineVariant`
- Header: title `titleLarge` + close `IconButton` if `isDismissible`
- Action row: pinned bottom, separated by `AppSpacing.sm` gap, full-width buttons
- Top radius: 20px (theme default)
- Replaces all `showModalBottomSheet` calls and `DraggableScrollableSheet` ad-hoc wrappers

---

### `AppActionSheet`
> HIG-style action sheet — a list of discrete choices, presented from the bottom. Distinct from `AppBottomSheet` (which holds content/forms). Used wherever a long-press or "more" tap reveals a list of actions: edit / duplicate / archive / delete.

```dart
class AppActionSheet {
  static Future<T?> show<T>({
    required BuildContext context,
    String? title,                // optional context line at top
    String? message,              // optional one-liner under title
    required List<AppActionSheetItem<T>> actions,
    AppActionSheetItem<T>? cancel, // defaults to a "Cancel" tile
  });
}

class AppActionSheetItem<T> {
  final String label;
  final IconData? icon;
  final T value;
  final bool isDestructive;       // renders in error color
  final bool isPrimary;           // optional emphasis (semibold)
  final bool enabled;
}
```

**Notes:**
- Presented via `showModalBottomSheet` with rounded top, drag handle, and a small max-width on tablets (centered).
- Each item is an `AppListTile` with leading icon, label, and `onTap` returning `value`. Destructive items render label in `colorScheme.error`.
- Cancel item is visually separated (a small gap above) — HIG convention.
- Returns the selected `value` (or `null` if dismissed via cancel/scrim).
- **Replaces** the long-press → custom bottom sheet menus in quests, treasury, fasting history.

---

### `AppDialog`
> M3 dialog wrapper.

```dart
class AppDialog {
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget body,
    List<Widget> actions = const [],
    bool barrierDismissible = true,
  });
}
```

---

### `AppConfirmDialog`
> One-shot confirmation flow — common in delete actions.

```dart
class AppConfirmDialog {
  static Future<bool> confirm({
    required BuildContext context,
    required String title,
    required String body,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool isDestructive = false,
  });
}
```

**Notes:** Returns `true` if confirmed, `false` otherwise. If `isDestructive`, confirm button uses `AppDestructiveButton`.

---

### `AppToast`
> SnackBar wrapper — three variants.

```dart
class AppToast {
  static void show(BuildContext c, String message);
  static void success(BuildContext c, String message);
  static void error(BuildContext c, String message);
  static void action(BuildContext c, {required String message, required String actionLabel, required VoidCallback onAction});
}
```

**Notes:** Uses `ScaffoldMessenger.of(context).showSnackBar` with theme defaults (set via `flex_color_scheme` to floating behavior, 12px radius). Variants set the `backgroundColor` and leading icon.

---

## Phase 3 — Lists & States

### `AppListTile`
> M3 `ListTile` wrapper with consistent padding + optional swipe-to-delete.

```dart
AppListTile({
  Widget? leading,
  required Widget title,         // Text or rich content
  Widget? subtitle,
  Widget? trailing,
  VoidCallback? onTap,
  VoidCallback? onLongPress,
  Future<bool> Function()? onDelete, // enables Dismissible; return false to cancel
  String deleteConfirmLabel = 'Delete',
  bool dense = false,
  bool selected = false,
  bool insetGrouped = false,     // HIG inset grouped style — used inside AppGroupedList
  EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
})
```

**Notes:**
- `onDelete` wraps in `Dismissible` with red background + delete icon. The Future return controls actual deletion (caller can show `AppConfirmDialog` first).
- `selected: true` applies a tonal highlight via theme `selectedTileColor`.
- Subtitle wraps multi-line by default; cap at 2 lines.
- `insetGrouped: true` removes corner radius (the wrapping `AppGroupedList` provides a single rounded surface) and tightens contentPadding. Used only inside `AppGroupedList`.

---

### `AppGroupedList`
> HIG inset grouped list container — wraps a list of `AppListTile`s in a single rounded surface with thin separators between rows. Multiple groups can be stacked, each with an optional title and footer hint. The canonical HIG settings/preferences layout.

```dart
AppGroupedList({
  required List<AppGroupedListSection> sections,
  EdgeInsetsGeometry margin = const EdgeInsets.symmetric(horizontal: AppSpacing.md),
})

class AppGroupedListSection {
  final String? title;            // small ALL-CAPS label above group (or sentence — caller's choice)
  final String? footer;           // small low-emphasis hint below group
  final List<Widget> children;    // typically AppListTile(insetGrouped: true)
}
```

**Notes:**
- Container background: `colorScheme.surfaceContainerLow` (filled, not elevated)
- Corner radius: `AppRadii.lg` (16) on the group
- Separator: 1px `colorScheme.outlineVariant` between tiles, **inset** to start after the leading icon (HIG convention)
- Section title: `labelMedium` low-emphasis, `mdGenerous` top spacing
- Section footer: `bodySmall` low-emphasis, `sm` top spacing
- Used by Settings (017h) and any "preferences" surface

---

### `AppSelectableTile`
> Selection variant — checkbox or radio leading slot.

```dart
AppSelectableTile({
  required Widget title,
  Widget? subtitle,
  Widget? trailing,              // e.g. value text
  required bool selected,
  required VoidCallback onTap,
  AppSelectableMode mode = AppSelectableMode.checkbox, // checkbox | radio | none
  Widget? leading,                // additional leading widget alongside selection indicator
})
```

---

### `AppEmptyState`
> Centered icon + title + body + optional action. Used wherever a list is empty.

```dart
AppEmptyState({
  required IconData icon,
  required String title,
  String? body,
  String? actionLabel,
  VoidCallback? onAction,
  double iconSize = 64,
})
```

---

### `AppErrorState`
> For I/O failures.

```dart
AppErrorState({
  required String message,
  String retryLabel = 'Retry',
  required VoidCallback onRetry,
  IconData icon = Icons.error_outline,
})
```

---

### `AppLoadingState`
> Centered spinner + label OR a `Skeletonizer` wrap of provided child.

```dart
AppLoadingState({
  String? message,                // when used in spinner mode
})

AppLoadingState.skeleton({
  required Widget child,         // any widget tree to skeletonize
  bool enabled = true,           // toggle to swap real content
})
```

**Notes:** Skeleton variant uses `package:skeletonizer/skeletonizer.dart`.

---

## Phase 4 — Indicators

### `AppNumberDisplay`
> Large numeric value with optional label. DM Mono with `tabularFigures` enabled.

```dart
AppNumberDisplay({
  required String value,
  String? label,                 // small caption above or below
  String? prefix,                // e.g. currency "$"
  String? suffix,                // e.g. "kcal", "kg"
  AppNumberSize size = AppNumberSize.title, // display | headline | title | body
  AppNumberLabelPosition labelPosition = AppNumberLabelPosition.below,
  Color? color,
  TextAlign textAlign = TextAlign.center,
})
```

**Notes:**
- Sizes map to `displayMedium / headlineLarge / titleLarge / bodyLarge`
- DM Mono font + `FontFeature.tabularFigures()` always on — prevents digit jitter
- Prefix/suffix render in current text style with reduced size and low-emphasis color
- Replaces ~15 hardcoded large-number `Text` widgets across timer, calorie summary, treasury totals, step counter

---

### `AppLinearProgress`
> M3 `LinearProgressIndicator` with optional label + value text on the same row.

```dart
AppLinearProgress({
  required double value,         // 0.0–1.0
  String? label,                 // left of bar
  String? valueText,             // right of bar (e.g. "230 / 400")
  Color? color,                  // null = theme primary
  Color? backgroundColor,
  double height = 8,
  bool clipped = true,           // ClipRRect with AppRadii.sm
})
```

---

### `AppCircularProgress`
> Circular indicator with optional centered child (typically `Icon`).

```dart
AppCircularProgress({
  required double value,         // null/-1 = indeterminate
  Widget? centerChild,           // typically Icon at AppSpacing.lg size
  double size = 40,
  double strokeWidth = 3,
  Color? color,
  Color? backgroundColor,
})
```

**Notes:** Used for stat icons in quests (centered icon variant), generic loading spots (no centerChild).

---

### `AppRingProgress`
> Wraps `PartialRingPainter`. Theme-aware colors. Replaces ad-hoc `CustomPaint` + painter setups in `timer_tab.dart` and `activity_screen.dart`.

```dart
AppRingProgress({
  required double value,         // 0.0–1.0
  Widget? center,                // AppNumberDisplay or other
  double size = 220,
  double strokeWidth = 14,
  double glowOpacity = 0.12,     // soft glow ≤ 15% per design
  Color? primaryColor,           // null = theme primary
  Color? trackColor,             // null = theme outlineVariant
  bool reversed = false,         // for "fed" phase
  double gapDegrees = 80,        // current ~80° opening
})
```

**Notes:** Painter accepts color params (Phase 4 of 017 already enforces this). This widget passes theme colors in by default.

---

### `AppStatPill`
> Compact label + value chip. E.g. "HP 87/100", "+25 XP", "1,840 kcal".

```dart
AppStatPill({
  String? label,                 // e.g. "HP" — optional
  required String value,         // e.g. "87/100"
  IconData? icon,                // optional leading icon
  AppStatColor color = AppStatColor.neutral, // neutral | primary | success | warning | error
  AppStatSize size = AppStatSize.medium,     // small | medium
})
```

**Notes:**
- Background: `color.withValues(alpha: 0.15)`, border `color.withValues(alpha: 0.4)`
- Sizes: small `(6,2)` padding, medium `(10,4)` padding
- Replaces 23 ad-hoc colored container chips

---

### `AppBadge`
> Tiny pill — text or count only.

```dart
AppBadge({
  required String text,
  AppBadgeVariant variant = AppBadgeVariant.tonal, // tonal | filled | outlined
  Color? color,                  // null = theme primary
  AppBadgeSize size = AppBadgeSize.small,           // small (10pt text) | medium (12pt)
})

AppBadge.count({
  required int count,
  Color? color,
  int max = 99, // displays "99+" above this
})
```

---

### `AppIconBadge`
> 44×44 (or sized) rounded-square tonal icon container — used in module cards, list leadings, hub.

```dart
AppIconBadge({
  required IconData icon,
  Color? color,                  // null = theme primary
  double size = 44,              // 32 / 40 / 44 / 56 common
  double iconSize = 22,
  double radius = AppRadii.md,   // 12px
  bool filled = true,            // false = outlined variant
})
```

**Notes:** Background = `color.withValues(alpha: 0.12)`. Used 6+ places already (module cards, quest tile leadings, settings rows).

---

## Phase 5 — Inputs & Actions

### `AppPrimaryButton`
> M3 `FilledButton` wrapper — full-width by default, fixed 52px height, **loading state included** (the codebase has none today).

```dart
AppPrimaryButton({
  required String label,
  VoidCallback? onPressed,        // null = disabled
  IconData? leading,
  bool isLoading = false,         // shows spinner, disables button
  bool fullWidth = true,
  double height = 52,
})
```

**Notes:**
- `isLoading: true` swaps label for `AppCircularProgress` (size 20). Button stays at fixed height — no layout jump.
- `tooltip` uses `Tooltip` wrapper (not added to API to keep surface small — wrap externally if needed).

---

### `AppSecondaryButton`
> M3 `OutlinedButton` wrapper. Same API as primary.

```dart
AppSecondaryButton({
  required String label,
  VoidCallback? onPressed,
  IconData? leading,
  bool isLoading = false,
  bool fullWidth = true,
  double height = 52,
})
```

---

### `AppDestructiveButton`
> Filled with `theme.colorScheme.error`. Same API.

```dart
AppDestructiveButton({
  required String label,
  VoidCallback? onPressed,
  IconData? leading,
  bool isLoading = false,
  bool fullWidth = true,
  double height = 52,
})
```

---

### `AppIconButton`
> M3 `IconButton` with optional badge overlay.

```dart
AppIconButton({
  required IconData icon,
  required VoidCallback onPressed,
  String? tooltip,
  Widget? badge,                 // typically AppBadge.count or a tiny dot
  AppIconButtonVariant variant = AppIconButtonVariant.standard, // standard | filled | tonal | outlined
})
```

---

### `AppTextField`
> `TextField` wrapper with consistent padding, **error/helper text built in**, and optional trailing/leading.

```dart
AppTextField({
  TextEditingController? controller,
  String? label,                 // floating label
  String? hint,
  String? helperText,
  String? errorText,
  Widget? prefix,
  Widget? suffix,
  IconData? prefixIcon,
  IconData? suffixIcon,
  VoidCallback? onSuffixIconTap,
  bool obscureText = false,
  TextInputType? keyboardType,
  TextInputAction? textInputAction,
  int? maxLines = 1,
  int? minLines,
  int? maxLength,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
  String? Function(String?)? validator,
  bool enabled = true,
  EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
  TextStyle? textStyle,
})
```

**Notes:**
- Reads from `theme.inputDecorationTheme` for fill, border, focus colors
- `errorText` and `validator` added — codebase scan showed no validation UI exists today; this fixes that gap
- `obscureText` with auto reveal suffix when needed (caller wires `onSuffixIconTap`)

---

### `AppSegmentedControl`
> M3 `SegmentedButton` wrapper with simpler API.

```dart
AppSegmentedControl<T>({
  required List<({T value, String label, IconData? icon})> segments,
  required T selected,
  required ValueChanged<T> onChanged,
  bool showSelectedIcon = false,
})
```

---

### `AppDayChipRow`
> Selectable day-of-week chip row (Mon–Sun). Used by nutrition's day picker — extracted because the pattern is specific enough to standardize.

```dart
AppDayChipRow({
  required DateTime selectedDate,
  required DateTime weekStart,    // Monday of the week being shown
  required ValueChanged<DateTime> onSelected,
  bool highlightToday = true,
})
```

**Notes:** Uses `AppPressable` chips. Today gets a subtle accent border. Selected gets filled primary.

---

## Phase 6 — Migration of Existing Widgets

> This phase replaces `lib/views/widgets/` internals with system-primitive composition. Behavior is preserved — pages keep working without changes. Page-level redesigns happen in 017a–017h.

| File | Migration |
|---|---|
| `lib/views/widgets/module_card.dart` | Compose `AppCard` + `AppIconBadge` + optional `AppBadge` for status |
| `lib/views/widgets/protocol_card.dart` | Compose `AppCard` (filled variant) + `AppStatPill` for tier label |
| `lib/views/widgets/ai_chat_sheet.dart` | Wrap with `AppBottomSheet`; download button → `AppPrimaryButton`; send button → `AppIconButton`; input → `AppTextField` |
| `lib/views/widgets/fast_completion_modal.dart` | Wrap with `AppDialog` or `AppBottomSheet` (decide in 017b); stats → `AppStatPill`; note input → `AppTextField`; button → `AppPrimaryButton` |
| `lib/views/widgets/refeeding_warning_sheet.dart` | Wrap with `AppBottomSheet` |
| `lib/views/widgets/level_up_overlay.dart` | Keep as one-off but use `AppNumberDisplay` for level number, `AppPrimaryButton` for continue; audit motion ≤ 400ms |
| `lib/views/widgets/partial_ring_painter.dart` | Accept `primaryColor`, `trackColor`, `glowOpacity` constructor params (already in 017 Phase 4) |
| `lib/views/widgets/stat_radar_chart.dart` | Accept color params (`fillColor`, `borderColor`, `gridColor`, `labelColor`) |
| `lib/views/quests/widgets/quest_mission_tile.dart` | Compose `AppListTile` + `AppCircularProgress` + `AppBadge` (XP) + `AppPressable` |
| `lib/views/quests/widgets/streak_badge.dart` | Use `AppCircularProgress` + custom centered child; theme-aware colors |
| `lib/views/treasury/bills/bill_list_tile.dart` | Compose `AppListTile` with `onDelete` (replaces ad-hoc `Dismissible`); `AppBadge` for type |
| `lib/views/treasury/bills/installment_list_tile.dart` | Same pattern |
| `lib/views/treasury/bills/receivable_list_tile.dart` | Same pattern |
| `lib/views/treasury/bills/budgeted_expense_tile.dart` | Same pattern |
| `lib/views/treasury/ledger/transaction_list_tile.dart` | Compose `AppListTile` + amount via `AppNumberDisplay` (DM Mono) |
| `lib/views/treasury/budget/category_budget_tile.dart` | `AppCard` + `AppLinearProgress` |

**Goal of Phase 6:** zero visual regressions on hub, fasting, stats, nutrition, quests, activity, treasury, settings after merge. The page redesigns (017a–017h) then replace layouts on top of the migrated primitives.

---

## Acceptance Criteria

- [ ] All 26 primitives implemented in `lib/views/widgets/system/` per the layout above
- [ ] `system.dart` barrel re-exports every primitive
- [ ] Every primitive renders correctly in **both** dark and light themes
- [ ] No primitive contains hardcoded colors, radii, spacings, or durations — all from tokens / `Theme.of(context)`
- [ ] `flex_color_scheme` and `skeletonizer` added to `pubspec.yaml`
- [ ] Every widget in `lib/views/widgets/` (existing) migrated per Phase 6 table — no behavior change
- [ ] `AppPageScaffold.large()` smoke-tested with a sliver body — title collapses on scroll without jank
- [ ] `AppActionSheet` returns the selected value; cancel returns null
- [ ] `AppGroupedList` renders with proper inset separators (separator starts after leading icon, not page edge)
- [ ] Smoke test: hub, fasting timer, stats, nutrition, quests, activity, treasury, settings all open and look unchanged after the migration
- [ ] No regressions in existing tests
- [ ] Public API of each primitive documented inline (one-paragraph dartdoc on the class)

---

## Out of Scope

- Adding `fl_chart` or any chart library (custom painters stay)
- Page-level redesigns (covered by 017a–017h)
- New widgets beyond the 23 listed
- Internationalization wrapping (ICU plurals etc.) — strings are still raw
- Test scaffolding for the widgets themselves — covered by existing widget tests + 011

---

## Risks

| Risk | Mitigation |
|---|---|
| `flex_color_scheme` opinions clash with our color palette | We feed it our existing `AppColors` as `colorScheme.fromSeed`-equivalent; keep manual override on any sub-theme it gets wrong |
| Library API churns once page plans start consuming it | Treat 017W's API as **v1**; minor additions OK, breaking renames need a follow-up plan |
| Skeletonizer + complex widget trees can mis-skeletonize | Apply only to leaf-list rows, not full pages |
| Migration changes existing widget visuals subtly | Phase 6 is behavior-preserving — manual smoke before merge |
| 23 primitives is a lot to land in one PR | Land per-folder: foundation → overlays → lists → indicators → inputs → migration |

---

## Open Decisions

- **`gap` package**: include or skip? Lean toward skip — minor benefit, one more dep. Use `SizedBox(height: AppSpacing.md)` consistently.
- **`AppFab` wrapper?** M3 `FloatingActionButton` is already well-themed; adding a wrapper is overhead. **Decision: skip**, use M3 directly with theme defaults.
- **`AppDivider`?** `Divider` already reads from theme. Skip.
- **`AppSlider`?** No sliders found in the codebase. Skip.
- **`AppSwitch`?** Found in settings paths only. Theme-default `Switch` suffices. Skip.

---

*Plan 017W — ready for approval. Lands after 017 (tokens + theme), blocks 017a–017h.*
