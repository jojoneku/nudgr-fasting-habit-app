import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/treasury/ledger/ledger_view.dart';
import '../../widgets/web_widgets.dart';
import 'web_ledger_dialogs.dart';
import 'web_ledger_filters.dart';
import 'web_ledger_table.dart';

/// The two view modes the page header toggles between (Plan 050-B).
enum LedgerViewMode { table, chat }

/// Web Ledger page (Plan 050-B). KEEPS the chat-based logging (embedded
/// [LedgerView]) and ADDS a sheet-style tabular view, switchable via a
/// segmented control in the page header. Table is the default on web.
class WebLedgerPage extends StatefulWidget {
  final LedgerPresenter presenter;
  const WebLedgerPage({super.key, required this.presenter});

  @override
  State<WebLedgerPage> createState() => _WebLedgerPageState();
}

class _WebLedgerPageState extends State<WebLedgerPage> {
  LedgerPresenter get presenter => widget.presenter;
  LedgerViewMode _mode = LedgerViewMode.table;

  void _addTransaction() {
    showLedgerTransactionDialog(context: context, presenter: presenter);
  }

  void _editTransaction(TransactionRecord txn) {
    showLedgerTransactionDialog(
      context: context,
      presenter: presenter,
      existing: txn,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(WebInsets.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WebSectionHeader(
              title: 'Ledger',
              subtitle: 'Every transaction — chat-logged or typed.',
              trailing: _ModeToggle(
                mode: _mode,
                onChanged: (m) => setState(() => _mode = m),
              ),
            ),
            if (_mode == LedgerViewMode.table)
              _TableMode(
                presenter: presenter,
                onAdd: _addTransaction,
                onEditRow: _editTransaction,
              )
            else
              _ChatMode(presenter: presenter),
          ],
        ),
      ),
    );
  }
}

// ── Mode toggle ───────────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  final LedgerViewMode mode;
  final ValueChanged<LedgerViewMode> onChanged;
  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<LedgerViewMode>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: LedgerViewMode.table,
          icon: Icon(Icons.table_rows_outlined, size: 18),
          label: Text('Table'),
        ),
        ButtonSegment(
          value: LedgerViewMode.chat,
          icon: Icon(Icons.chat_bubble_outline, size: 18),
          label: Text('Chat'),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

// ── Table mode ──────────────────────────────────────────────────────────────

class _TableMode extends StatelessWidget {
  final LedgerPresenter presenter;
  final VoidCallback onAdd;
  final void Function(TransactionRecord txn) onEditRow;
  const _TableMode({
    required this.presenter,
    required this.onAdd,
    required this.onEditRow,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerFilterBar(presenter: presenter, onAdd: onAdd),
        const SizedBox(height: WebInsets.lg),
        WebCard(
          padding: EdgeInsets.zero,
          child: LedgerDataTable(presenter: presenter, onRowTap: onEditRow),
        ),
      ],
    );
  }
}

// ── Chat mode (embeds the existing mobile chat view) ─────────────────────────

class _ChatMode extends StatelessWidget {
  final LedgerPresenter presenter;
  const _ChatMode({required this.presenter});

  @override
  Widget build(BuildContext context) {
    // LedgerView is a full Scaffold (its own input bar lives at the bottom).
    // Give it a bounded height so it lays out inside the scrolling web page
    // instead of trying to fill an unbounded column.
    final height = MediaQuery.sizeOf(context).height - 220;
    return WebCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: height.clamp(420.0, 900.0),
          child: LedgerView(presenter: presenter),
        ),
      ),
    );
  }
}
