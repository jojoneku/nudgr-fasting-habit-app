import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

class AddInstallmentSheet extends StatefulWidget {
  final InstallmentPresenter presenter;
  final Installment? existing;

  const AddInstallmentSheet(
      {super.key, required this.presenter, this.existing});

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
  int _totalMonths = 12;
  String _startMonth = toMonthKey(DateTime.now());
  bool _monthlyManuallyEdited = false;
  bool _saving = false;

  static const _presetMonths = [3, 6, 12, 24];

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
      _totalMonths = e.totalMonths;
      _startMonth = e.startMonth;
      _monthlyManuallyEdited = true;
    } else if (widget.presenter.accounts.isNotEmpty) {
      _accountId = widget.presenter.accounts.first.id;
    }
    _totalCtrl.addListener(_onTotalChanged);
  }

  void _onTotalChanged() {
    if (_monthlyManuallyEdited) return;
    final total = double.tryParse(_totalCtrl.text);
    if (total != null && _totalMonths > 0) {
      _monthlyCtrl.text = (total / _totalMonths).toStringAsFixed(2);
    }
  }

  void _onMonthsChanged(int months) {
    setState(() {
      _totalMonths = months;
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
    if (_accountId == null) return;
    setState(() => _saving = true);

    final total = double.parse(_totalCtrl.text);
    final monthly = double.parse(_monthlyCtrl.text);
    final e = widget.existing;

    final installment = Installment(
      id: e?.id ??
          '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
      name: _nameCtrl.text.trim(),
      accountId: _accountId!,
      totalAmount: total,
      monthlyAmount: monthly,
      totalMonths: _totalMonths,
      startMonth: _startMonth,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      isActive: e?.isActive ?? true,
    );

    if (e != null) {
      await widget.presenter.updateInstallment(installment);
    } else {
      await widget.presenter.addInstallment(installment);
    }
    if (mounted) Navigator.pop(context);
  }

  void _adjustStartMonth(int delta) {
    final date = DateTime.parse('$_startMonth-01');
    final next = DateTime(date.year, date.month + delta);
    setState(() => _startMonth = toMonthKey(next));
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Form(
            key: _formKey,
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
                      color: AppColors.textSecondary.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  isEdit ? 'Edit Installment' : 'New Installment',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),

                // ── Name ──────────────────────────────────────────────────────
                _FieldLabel('Name'),
                TextFormField(
                  controller: _nameCtrl,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: _inputDecor('e.g. MacBook Pro, Braces'),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                // ── Account ───────────────────────────────────────────────────
                _FieldLabel('Account (Credit / BNPL)'),
                DropdownButtonFormField<String>(
                  value: _accountId,
                  dropdownColor: AppColors.surface,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: _inputDecor('Select account'),
                  items: widget.presenter.accounts.map((a) {
                    return DropdownMenuItem(value: a.id, child: Text(a.name));
                  }).toList(),
                  onChanged: (v) => setState(() => _accountId = v),
                  validator: (v) => v == null ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                // ── Total Amount ──────────────────────────────────────────────
                _FieldLabel('Total Amount'),
                TextFormField(
                  controller: _totalCtrl,
                  style: GoogleFonts.jetBrainsMono(
                    textStyle: TextStyle(color: AppColors.textPrimary),
                  ),
                  decoration: _inputDecor('0.00'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                  ],
                  validator: (v) {
                    if (v == null || double.tryParse(v) == null) {
                      return 'Enter a valid amount';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ── Number of months ──────────────────────────────────────────
                _FieldLabel('Number of Months'),
                _MonthsSelector(
                  selected: _totalMonths,
                  onChanged: _onMonthsChanged,
                ),
                const SizedBox(height: 16),

                // ── Monthly Amount ────────────────────────────────────────────
                _FieldLabel('Monthly Payment (auto-computed, editable)'),
                TextFormField(
                  controller: _monthlyCtrl,
                  style: GoogleFonts.jetBrainsMono(
                    textStyle: TextStyle(color: AppColors.textPrimary),
                  ),
                  decoration: _inputDecor('0.00'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                  ],
                  onChanged: (_) =>
                      setState(() => _monthlyManuallyEdited = true),
                  validator: (v) {
                    if (v == null || double.tryParse(v) == null) {
                      return 'Enter a valid amount';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ── Start Month ───────────────────────────────────────────────
                _FieldLabel('Start Month'),
                _StartMonthSelector(
                  selectedMonth: _startMonth,
                  onAdjust: _adjustStartMonth,
                ),
                const SizedBox(height: 16),

                // ── Note ─────────────────────────────────────────────────────
                _FieldLabel('Note (optional)'),
                TextFormField(
                  controller: _noteCtrl,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: _inputDecor('e.g. 0% interest, 12 months'),
                  maxLines: 2,
                ),
                const SizedBox(height: 28),

                // ── Save button ───────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.background,
                            ),
                          )
                        : Text(
                            isEdit ? 'Save Changes' : 'Add Installment',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecor(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.textSecondary.withOpacity(0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.textSecondary.withOpacity(0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withOpacity(0.15)
              : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppColors.accent
                : AppColors.textSecondary.withOpacity(0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.accent : AppColors.textSecondary,
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
    return SizedBox(
      width: 72,
      child: TextFormField(
        controller: _ctrl,
        style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Custom',
          hintStyle: TextStyle(
              color: AppColors.textSecondary.withOpacity(0.5), fontSize: 12),
          filled: true,
          fillColor: AppColors.background,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                BorderSide(color: AppColors.textSecondary.withOpacity(0.2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                BorderSide(color: AppColors.textSecondary.withOpacity(0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.accent),
          ),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.textSecondary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: Icon(Icons.chevron_left, color: AppColors.textSecondary),
              onPressed: () => onAdjust(-1),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                monthLabel(selectedMonth),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: Icon(Icons.chevron_right, color: AppColors.textSecondary),
              onPressed: () => onAdjust(1),
            ),
          ),
        ],
      ),
    );
  }
}
