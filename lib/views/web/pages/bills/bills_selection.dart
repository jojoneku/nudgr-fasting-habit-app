/// Local UI selection state for the web Bills & Receivables two-pane layout.
/// Identifies which item the right-hand detail pane should render. Selection is
/// view-only state (not presenter state), so it lives here.
sealed class BillsSelection {
  const BillsSelection();
}

class BillSelection extends BillsSelection {
  final String id;
  const BillSelection(this.id);

  @override
  bool operator ==(Object other) => other is BillSelection && other.id == id;
  @override
  int get hashCode => Object.hash('bill', id);
}

class ReceivableSelection extends BillsSelection {
  final String id;
  const ReceivableSelection(this.id);

  @override
  bool operator ==(Object other) =>
      other is ReceivableSelection && other.id == id;
  @override
  int get hashCode => Object.hash('receivable', id);
}

class InstallmentSelection extends BillsSelection {
  final String id;
  const InstallmentSelection(this.id);

  @override
  bool operator ==(Object other) =>
      other is InstallmentSelection && other.id == id;
  @override
  int get hashCode => Object.hash('installment', id);
}
