import 'package:flutter/material.dart';
import '../../../../utils/app_spacing.dart';
import '../../../../utils/app_text_styles.dart';

/// Standard page chrome — Scaffold + flat AppBar + padded body.
/// Use [AppPageScaffold.large] for top-level destinations with a HIG
/// collapsing large title.
class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    super.key,
    this.title,
    this.titleWidget,
    this.actions = const [],
    this.leading,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    this.onRefresh,
    this.backgroundColor,
    this.showAppBar = true,
  });

  final String? title;
  final Widget? titleWidget;
  final List<Widget> actions;
  final Widget? leading;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final EdgeInsetsGeometry padding;
  final Future<void> Function()? onRefresh;
  final Color? backgroundColor;
  final bool showAppBar;

  /// HIG large-title variant — title expands on scroll-up, collapses on scroll-down.
  const factory AppPageScaffold.large({
    Key? key,
    required String title,
    String? subtitle,
    List<Widget> actions,
    Widget? leading,
    required List<Widget> slivers,
    Widget? floatingActionButton,
    Widget? bottomNavigationBar,
    Future<void> Function()? onRefresh,
    Color? backgroundColor,
  }) = _AppPageScaffoldLarge;

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(padding: padding, child: body);

    if (onRefresh != null) {
      content = RefreshIndicator(onRefresh: onRefresh!, child: content);
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: showAppBar
          ? AppBar(
              title: titleWidget ?? (title != null ? Text(title!) : null),
              actions: actions,
              leading: leading,
            )
          : null,
      body: content,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

class _AppPageScaffoldLarge extends AppPageScaffold {
  const _AppPageScaffoldLarge({
    super.key,
    required String title,
    this.subtitle,
    super.actions = const [],
    super.leading,
    required this.slivers,
    super.floatingActionButton,
    super.bottomNavigationBar,
    super.onRefresh,
    super.backgroundColor,
  }) : super(
          title: title,
          body: const SizedBox.shrink(),
          showAppBar: false,
        );

  final String? subtitle;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pageBackground = backgroundColor ?? theme.scaffoldBackgroundColor;

    final toolbarHeight = subtitle == null ? 56.0 : 64.0;

    final titleSliver = SliverAppBar(
      toolbarHeight: toolbarHeight,
      collapsedHeight: toolbarHeight,
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title!, style: AppTextStyles.headlineMedium),
          if (subtitle != null)
            Text(
              subtitle!,
              style: AppTextStyles.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      actions: actions,
      leading: leading,
      backgroundColor: pageBackground,
      surfaceTintColor: Colors.transparent,
      pinned: true,
    );

    List<Widget> allSlivers = [titleSliver, ...slivers];

    Widget scrollView = CustomScrollView(slivers: allSlivers);

    if (onRefresh != null) {
      scrollView = RefreshIndicator(
        onRefresh: onRefresh!,
        child: scrollView,
      );
    }

    return Scaffold(
      backgroundColor: pageBackground,
      body: scrollView,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}
