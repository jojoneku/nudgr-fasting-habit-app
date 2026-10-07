import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/amount_input_formatter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/category_chips.dart';
import 'package:intermittent_fasting/views/treasury/shared/sheet_fields.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import 'package:intl/intl.dart';

class AddInstallmentSheet extends StatefulWidget {
  final InstallmentPresenter presenter;
  final Installment? existing;

  /// Embedded inside `NewEntrySheet` — render only the form + Save (see
  /// [AddBillSheet.embedded]).
  final bool embedded;

  const AddInstallmentSheet(
      {super.key,
      required this.presenter,
      this.existing,
      this.embedded = false});

  @override
  State<AddInstallmentSheet> createState() => _AddInstallmentSheetState();
}

class _AddInstallmentSheetState extends State<AddInstallmentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();
  final _monthlyCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  String? _accountId;
  String? _categoryId;
  int _totalMonths = 12;
  String _startMonth = toMonthKey(DateTime.now());
  DateTime _purchaseDate = DateTime.now();
  int _deferralMonths = 0;
  double _interestRate = 0.0;
  bool _monthlyManuallyEdited = false;

  /// True once the start-month stepper was used in THIS session. Until then
  /// the start month follows account / purchase date / deferral — on edit
  /// too, so changing the deferral saves the month the hint shows.
  bool _startMonthTouched = false;
  bool _saving = false;
  bool _accountError = false;

  List<FinancialAccount> get _availableAccounts {
    final credit = widget.presenter.creditAccounts;
    if (_accountId != null && !credit.any((a) => a.id == _accountId)) {
      final fallback = widget.presenter.accounts
          .where((a) => a.id == _accountId)
          .firstOrNull;
      if (fallback != null) return [fallback, ...credit];
    }
    return credit;
  }

  FinancialAccount? get _selectedAccount {
    for (final a in _availableAccounts) {
      if (a.id == _accountId) return a;
    }
    return null;
  }

  void _recalculateStartMonth() {
    if (_startMonthTouched) return;
    final computed = widget.presenter.suggestedStartMonth(
      accountId: _accountId,
      purchaseDate: _purchaseDate,
      deferralMonths: _deferralMonths,
    );
    setState(() => _startMonth = computed);
  }

  Future<void> _pickAccount() async {
    final choice = await showAccountPicker(
      context,
      accounts: _availableAccounts,
      selectedId: _accountId,
    );
    if (choice != null) {
      setState(() {
        _accountId = choice.id;
        _accountError = false;
        _recalculateStartMonth();
      });
    }
  }

  Future<void> _pickPurchaseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _purchaseDate = picked;
        _recalculateStartMonth();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _totalCtrl.text = e.totalAmount.toStringAsFixed(2);
      _monthlyCtrl.text = e.monthlyAmount.toStringAsFixed(2);
      _noteCtrl.text = e.note ?? '';
      _accountId = e.accountId;
      _categoryId = e.categoryId;
      _totalMonths = e.totalMonths;
      _startMonth = e.startMonth;
      _purchaseDate = e.purchaseDate ??
          DateTime.tryParse('${e.startMonth}-01') ??
          DateTime.now();
      _deferralMonths = e.deferralMonths;
      _interestRate = e.interestRate;
      _monthlyManuallyEdited = true;
    } else {
      _purchaseDate = DateTime.now();
      _deferralMonths = 0;
      _interestRate = 0.0;
      if (widget.presenter.creditAccounts.isNotEmpty) {
        _accountId = widget.presenter.creditAccounts.first.id;
      }
      _recalculateStartMonth();
    }
    _totalCtrl.addListener(_onTotalChanged);
  }

  void _onTotalChanged() {
    // Rebuild either way: the interest preview reads the total.
    setState(() {
      if (_monthlyManuallyEdited) return;
      final total = double.tryParse(_totalCtrl.text);
      if (total != null && _totalMonths > 0) {
        final monthly = Installment.computeMonthlyAmount(
          principal: total,
          months: _totalMonths,
          monthlyRate: _interestRate,
        );
        _monthlyCtrl.text = monthly.toStringAsFixed(2);
      }
    });
  }

  InstallmentInterestPreview? get _interestPreview =>
      widget.presenter.interestPreview(
        principal: double.tryParse(_totalCtrl.text),
        months: _totalMonths,
        rate: _interestRate,
        monthlyAmount: double.tryParse(_monthlyCtrl.text),
      );

  void _onMonthsChanged(int months) {
    setState(() {
      _totalMonths = months;
      _monthlyManuallyEdited = false;
    });
    _onTotalChanged();
  }

  void _onInterestRateChanged(double rate) {
    setState(() {
      _interestRate = rate;
      _monthlyManuallyEdited = false;
    });
    _onTotalChanged();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _totalCtrl.dispose();
    _monthlyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) {
      setState(() => _accountError = true);
      return;
    }
    setState(() => _saving = true);

    final e = widget.existing;
    final installment = widget.presenter.buildInstallment(
      existing: e,
      name: _nameCtrl.text,
      accountId: _accountId!,
      totalAmount: double.parse(_totalCtrl.text),
      monthlyAmount: double.parse(_monthlyCtrl.text),
      totalMonths: _totalMonths,
      startMonth: _startMonth,
      purchaseDate: _purchaseDate,
      deferralMonths: _deferralMonths,
      interestRate: _interestRate,
      note: _noteCtrl.text,
      categoryId: _categoryId,
    );
    await widget.presenter.saveInstallment(installment, isEdit: e != null);
    if (mounted) Navigator.pop(context);
  }

  void _adjustStartMonth(int delta) {
    final date = DateTime.parse('$_startMonth-01');
    final next = DateTime(date.year, date.month + delta);
    setState(() {
      _startMonth = toMonthKey(next);
      _startMonthTouched = true;
    });
  }

  Widget _buildCycleHint(BuildContext context) {
    final explanation = widget.presenter.cycleHint(
      accountId: _accountId,
      purchaseDate: _purchaseDate,
      deferralMonths: _deferralMonths,
    );
    if (explanation == null) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                explanation,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInterestSummary(
      BuildContext context, InstallmentInterestPreview preview) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.percent, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              preview.label,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final interestPreview = _interestPreview;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name
          const _FieldLabel('Name'),
          TextFormField(
            controller: _nameCtrl,
            decoration:
                sheetFieldDecoration(context, hint: 'e.g. MacBook Pro, Braces'),
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 16),

          // Account (required)
          const _FieldLabel('Account (Credit / BNPL)'),
          SheetAccountField(
            account: _selectedAccount,
            placeholder: 'Select account',
            onTap: _pickAccount,
          ),
          if (_accountError)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Text('Required',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12)),
            )
          else if (_availableAccounts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Text(
                'No credit accounts found. Add a credit card, credit line, or BNPL account first.',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error, fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),

          // Category (optional)
          const _FieldLabel('Category (optional)'),
          CategoryPickerField(
            categories: widget.presenter.categories,
            selectedId: _categoryId,
            onChanged: (val) => setState(() => _categoryId = val),
          ),
          const SizedBox(height: 16),

          // Purchase Date
          const _FieldLabel('Purchase Date'),
          SheetPickerBox(
            onTap: _pickPurchaseDate,
            trailingIcon: Icons.calendar_today_outlined,
            child: Text(
              DateFormat('MMMM d, yyyy').format(_purchaseDate),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
              ),
            ),
          ),
          _buildCycleHint(context),
          const SizedBox(height: 16),

          // First payment deferral (optional)
          const _FieldLabel('Deferred First Payment (optional)'),
          _DeferralSelector(
            selected: _deferralMonths,
            onChanged: (val) {
              setState(() {
                _deferralMonths = val;
                _recalculateStartMonth();
              });
            },
          ),
          const SizedBox(height: 16),

          // Total Amount
          const _FieldLabel('Total Amount'),
          TextFormField(
            controller: _totalCtrl,
            decoration: sheetFieldDecoration(context,
                hint: '0.00', prefixText: '₱ ', emphasize: true),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: amountInputFormatters,
            textInputAction: TextInputAction.next,
            validator: (v) {
              final p = double.tryParse(v ?? '');
              if (p == null || p <= 0) return 'Must be > 0';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Number of months
          const _FieldLabel('Number of Months'),
          _MonthsSelector(
            selected: _totalMonths,
            onChanged: _onMonthsChanged,
          ),
          const SizedBox(height: 16),

          // Monthly Interest Rate (optional)
          const _FieldLabel('Monthly Interest Rate (optional)'),
          _InterestRateSelector(
            selected: _interestRate,
            onChanged: _onInterestRateChanged,
          ),
          if (interestPreview != null) ...[
            const SizedBox(height: 8),
            _buildInterestSummary(context, interestPreview),
          ],
          const SizedBox(height: 16),

          // Monthly payment (auto-computed, editable) + start month, side by side.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _FieldLabel('Monthly Payment'),
                    TextFormField(
                      controller: _monthlyCtrl,
                      decoration: sheetFieldDecoration(context,
                          hint: '0.00', prefixText: '₱ '),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: amountInputFormatters,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) =>
                          setState(() => _monthlyManuallyEdited = true),
                      validator: (v) {
                        final p = double.tryParse(v ?? '');
                        if (p == null || p <= 0) return 'Must be > 0';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _FieldLabel('Start Month'),
                    _StartMonthSelector(
                      selectedMonth: _startMonth,
                      onAdjust: _adjustStartMonth,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Note — outline field box like the rest of the form.
          const _FieldLabel('Note (optional)'),
          TextFormField(
            controller: _noteCtrl,
            decoration: sheetFieldDecoration(context,
                hint: 'e.g. 0% interest, 12 months'),
            textInputAction: TextInputAction.done,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEdit = widget.existing != null;

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildForm(context),
          const SizedBox(height: 28),
          AppPrimaryButton(
            label: isEdit ? 'Save Changes' : 'Add Installment',
            onPressed: _saving ? null : _save,
            isLoading: _saving,
          ),
          const SizedBox(height: 8),
        ],
      );
    }

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                isEdit ? 'Edit Installment' : 'New Installment',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              _buildForm(context),
              const SizedBox(height: 28),
              AppPrimaryButton(
                label: isEdit ? 'Save Changes' : 'Add Installment',
                onPressed: _saving ? null : _save,
                isLoading: _saving,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin wrapper over the shared [SheetFieldLabel] so existing `_FieldLabel(...)`
/// call sites in this sheet pick up the reference uppercase-label styling.
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => SheetFieldLabel(text);
}

class _MonthsSelector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _MonthsSelector({required this.selected, required this.onChanged});

  static const _presets = [3, 6, 12, 24];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        ..._presets.map((m) => _MonthChip(
              label: '${m}mo',
              selected: selected == m,
              onTap: () => onChanged(m),
            )),
        _CustomMonthsField(
          selected: !_presets.contains(selected) ? selected : null,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _MonthChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MonthChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.15)
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _CustomMonthsField extends StatefulWidget {
  final int? selected;
  final ValueChanged<int> onChanged;

  const _CustomMonthsField({this.selected, required this.onChanged});

  @override
  State<_CustomMonthsField> createState() => _CustomMonthsFieldState();
}

class _CustomMonthsFieldState extends State<_CustomMonthsField> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.selected != null) _ctrl.text = '${widget.selected}';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = widget.selected != null;
    // Chip-shaped box so it lines up with the preset month chips beside it.
    return Container(
      width: 76,
      decoration: BoxDecoration(
        color: active
            ? cs.primary.withValues(alpha: 0.15)
            : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? cs.primary : cs.outlineVariant),
      ),
      child: TextField(
        controller: _ctrl,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3),
        ],
        style: TextStyle(
          color: active ? cs.primary : cs.onSurface,
          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          fontSize: 13,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          border: InputBorder.none,
          hintText: 'Custom',
          hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
        onChanged: (v) {
          final parsed = int.tryParse(v);
          if (parsed != null && parsed > 0) widget.onChanged(parsed);
        },
      ),
    );
  }
}

class _StartMonthSelector extends StatelessWidget {
  final String selectedMonth;
  final ValueChanged<int> onAdjust;

  const _StartMonthSelector(
      {required this.selectedMonth, required this.onAdjust});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            height: 46,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon:
                  Icon(Icons.chevron_left, color: colorScheme.onSurfaceVariant),
              onPressed: () => onAdjust(-1),
            ),
          ),
          Expanded(
            child: Text(
              monthLabel(selectedMonth),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            width: 34,
            height: 46,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant),
              onPressed: () => onAdjust(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeferralSelector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  static const _presets = [0, 1, 2, 3];

  const _DeferralSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final m in _presets)
          _MonthChip(
            label: m == 0 ? 'None' : '${m}mo',
            selected: selected == m,
            onTap: () => onChanged(m),
          ),
      ],
    );
  }
}

class _InterestRateSelector extends StatelessWidget {
  final double selected;
  final ValueChanged<double> onChanged;

  const _InterestRateSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final r in InstallmentPresenter.ratePresets) ...[
            _MonthChip(
              label: InstallmentPresenter.ratePresetLabel(r),
              selected: selected == r,
              onTap: () => onChanged(r),
            ),
            const SizedBox(width: 8),
          ],
          _CustomRateField(
            rate: selected,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// The free-text "Custom %" box beside the rate chips. [rate] is the form's
/// current rate wherever it came from.
///
/// It only rewrites its own text when the rate changed from OUTSIDE (a chip):
/// a value it just emitted is left alone, so backspacing "2.5" to "2." (which
/// parses as the 2% preset) doesn't wipe the field mid-typing.
class _CustomRateField extends StatefulWidget {
  final double rate;
  final ValueChanged<double> onChanged;

  const _CustomRateField({required this.rate, required this.onChanged});

  @override
  State<_CustomRateField> createState() => _CustomRateFieldState();
}

class _CustomRateFieldState extends State<_CustomRateField> {
  final _ctrl = TextEditingController();

  /// The last rate this field sent up, or null when it holds no value.
  double? _emitted;

  bool get _active => !InstallmentPresenter.isPresetRate(widget.rate);

  @override
  void initState() {
    super.initState();
    _syncFrom(widget.rate);
  }

  @override
  void didUpdateWidget(_CustomRateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rate != _emitted) _syncFrom(widget.rate);
  }

  /// Shows [rate] when it's a custom value, clears the box for a preset.
  void _syncFrom(double rate) {
    final custom = !InstallmentPresenter.isPresetRate(rate);
    _ctrl.text = custom ? InstallmentPresenter.rateText(rate) : '';
    _emitted = custom ? rate : null;
  }

  void _onTyped(String v) {
    final parsed = double.tryParse(v);
    if (parsed == null || parsed < 0) return;
    _emitted = parsed;
    widget.onChanged(parsed);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = _active;
    return Container(
      width: 88,
      decoration: BoxDecoration(
        color: active
            ? cs.primary.withValues(alpha: 0.15)
            : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? cs.primary : cs.outlineVariant),
      ),
      child: TextField(
        controller: _ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: active ? cs.primary : cs.onSurface,
          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          fontSize: 13,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          border: InputBorder.none,
          hintText: 'Custom %',
          hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
        onChanged: _onTyped,
      ),
    );
  }
}
