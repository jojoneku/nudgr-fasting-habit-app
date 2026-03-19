# Flutter Widget Patterns — Quick Reference

## Card Patterns

### Basic Card
```dart
Card(
  elevation: 4,
  margin: EdgeInsets.all(16),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  child: Padding(
    padding: EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Title', style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: 8),
        Text('Description'),
      ],
    ),
  ),
)
```

## List Patterns

### Lazy Loading List
```dart
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) {
    final item = items[index];
    return ListTile(
      leading: CircleAvatar(child: Text(item.initial)),
      title: Text(item.title),
      trailing: Icon(Icons.chevron_right),
      onTap: () => Navigator.push(context, route),
    );
  },
)
```

## Dialog Patterns

### Alert Dialog
```dart
Future<bool?> showConfirmDialog(BuildContext context, String message) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Confirm'),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text('Confirm')),
      ],
    ),
  );
}
```

## Loading / Empty / Error States

```dart
// Loading
Widget buildLoading() => const Center(child: CircularProgressIndicator());

// Empty state
Widget buildEmptyState({required IconData icon, required String message, String? actionLabel, VoidCallback? onAction}) {
  return Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 64, color: Colors.grey),
      SizedBox(height: 16),
      Text(message, style: TextStyle(fontSize: 18, color: Colors.grey), textAlign: TextAlign.center),
      if (actionLabel != null && onAction != null) ...[
        SizedBox(height: 16),
        ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    ]),
  );
}

// Error state
Widget buildErrorState({required String message, VoidCallback? onRetry}) {
  return Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.error_outline, size: 64, color: Colors.red),
        SizedBox(height: 16),
        Text(message, style: TextStyle(fontSize: 16), textAlign: TextAlign.center),
        if (onRetry != null) ...[
          SizedBox(height: 16),
          ElevatedButton.icon(icon: Icon(Icons.refresh), label: Text('Retry'), onPressed: onRetry),
        ],
      ]),
    ),
  );
}
```

## Material 3 Widgets

### NavigationBar (replaces BottomNavigationBar)
```dart
Scaffold(
  bottomNavigationBar: NavigationBar(
    selectedIndex: _currentIndex,
    onDestinationSelected: (index) => setState(() => _currentIndex = index),
    destinations: const [
      NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
      NavigationDestination(icon: Icon(Icons.person_outlined), selectedIcon: Icon(Icons.person), label: 'Profile'),
    ],
  ),
  body: _screens[_currentIndex],
)
```

### SegmentedButton
```dart
SegmentedButton<String>(
  segments: const [
    ButtonSegment(value: 'day', label: Text('Day')),
    ButtonSegment(value: 'week', label: Text('Week')),
  ],
  selected: {_selectedView},
  onSelectionChanged: (Set<String> newSelection) => setState(() => _selectedView = newSelection.first),
)
```

### FilledButton hierarchy
```dart
FilledButton(onPressed: () {}, child: const Text('Primary Action'))       // Primary
FilledButton.tonal(onPressed: () {}, child: const Text('Secondary'))      // Secondary
OutlinedButton(onPressed: () {}, child: const Text('Tertiary'))           // Tertiary
TextButton(onPressed: () {}, child: const Text('Low Emphasis'))           // Low emphasis
```

## Responsive Layout (Material 3 breakpoints)
```dart
class ResponsiveLayout extends StatelessWidget {
  final Widget compact;   // < 600dp (phones)
  final Widget? medium;   // 600-839dp (tablets portrait)
  final Widget? expanded; // 840dp+ (tablets landscape)

  const ResponsiveLayout({required this.compact, this.medium, this.expanded});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 840) return expanded ?? medium ?? compact;
      if (constraints.maxWidth >= 600) return medium ?? compact;
      return compact;
    });
  }
}
```
