import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import '../../widgets/web_widgets.dart';

/// Web Ledger page (Plan 050-B). STUB — replaced by the Ledger agent, which
/// adds a Chat ⇆ Table view-mode toggle (chat logging is KEPT, table is ADDED).
class WebLedgerPage extends StatelessWidget {
  final LedgerPresenter presenter;
  const WebLedgerPage({super.key, required this.presenter});

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
              title: 'Ledger',
              subtitle: 'Every transaction, chat-logged or typed.',
            ),
            const WebCard(
              child: Text('Ledger redesign in progress — Plan 050-B.'),
            ),
          ],
        ),
      ),
    );
  }
}
