import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/grocery_cart_presenter.dart';
import '../../widgets/web_widgets.dart';

/// Web Cart page (Plan 050-F). STUB — replaced by the Cart agent.
class WebCartPage extends StatelessWidget {
  final GroceryCartPresenter presenter;
  const WebCartPage({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(WebInsets.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const WebSectionHeader(
              title: 'Grocery Cart',
              subtitle: 'Running total before you reach the till.',
            ),
            const WebCard(
              child: Text('Cart redesign in progress — Plan 050-F.'),
            ),
          ],
        ),
      ),
    );
  }
}
