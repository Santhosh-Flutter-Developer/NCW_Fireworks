import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../data/models/custom_product/custom_product_models.dart';
import 'common_widgets.dart';

/// Opens the Add Custom Product form as a bottom sheet. Only four fields,
/// per the feature spec: Category (searchable dropdown), Product Name,
/// Price, Unit (searchable dropdown) — no product code/image, unlike the
/// full web "Add Product" form this mirrors.
///
/// [onSubmit] is whichever controller's `addCustomProduct` (Quotation's
/// or Estimation's) — offline-only, always: it queues the product on
/// this device and only reaches the network on the next manual Sync.
/// Returns once the sheet is dismissed; the caller doesn't need the
/// result, [onSubmit]'s own snackbars/loading state cover feedback.
Future<void> showAddCustomProductSheet({
  required BuildContext context,
  required List<CustomProductOption> categories,
  required List<CustomProductOption> units,
  required Future<bool> Function({
    required String categoryId,
    required String categoryName,
    required String productName,
    required String unitId,
    required String unitName,
    required double price,
  }) onSubmit,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _AddCustomProductSheet(
      categories: categories,
      units: units,
      onSubmit: onSubmit,
    ),
  );
}

class _AddCustomProductSheet extends StatefulWidget {
  final List<CustomProductOption> categories;
  final List<CustomProductOption> units;
  final Future<bool> Function({
    required String categoryId,
    required String categoryName,
    required String productName,
    required String unitId,
    required String unitName,
    required double price,
  }) onSubmit;

  const _AddCustomProductSheet({
    required this.categories,
    required this.units,
    required this.onSubmit,
  });

  @override
  State<_AddCustomProductSheet> createState() =>
      _AddCustomProductSheetState();
}

class _AddCustomProductSheetState extends State<_AddCustomProductSheet> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  CustomProductOption? _category;
  CustomProductOption? _unit;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickOption({
    required String title,
    required List<CustomProductOption> options,
    required CustomProductOption? selected,
    required ValueChanged<CustomProductOption> onSelected,
  }) async {
    final picked = await showModalBottomSheet<CustomProductOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _SearchableOptionSheet(
        title: title,
        options: options,
        selected: selected,
      ),
    );
    if (picked != null) onSelected(picked);
  }

  Widget _pickerField({
    required String label,
    required String hint,
    required CustomProductOption? value,
    required List<CustomProductOption> options,
    required ValueChanged<CustomProductOption> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.caption),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: options.isEmpty
              ? null
              : () => _pickOption(
                    title: label,
                    options: options,
                    selected: value,
                    onSelected: onSelected,
                  ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value?.name ??
                        (options.isEmpty ? 'None available' : hint),
                    style: AppTextStyles.body.copyWith(
                      color: value == null
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_category == null) {
      setState(() => _error = 'Please select a category');
      return;
    }
    if (_unit == null) {
      setState(() => _error = 'Please select a unit');
      return;
    }
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a product name');
      return;
    }
    final price = double.tryParse(_priceCtrl.text.trim());
    if (price == null || price <= 0) {
      setState(() => _error = 'Please enter a valid price');
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });
    final ok = await widget.onSubmit(
      categoryId: _category!.id,
      categoryName: _category!.name,
      productName: name,
      unitId: _unit!.id,
      unitName: _unit!.name,
      price: price,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Add Custom Product',
                        style: AppTextStyles.h3),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: AppColors.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _pickerField(
                label: 'Category',
                hint: 'Select category',
                value: _category,
                options: widget.categories,
                onSelected: (v) => setState(() => _category = v),
              ),
              const SizedBox(height: 14),
              Text('Product Name', style: AppTextStyles.caption),
              const SizedBox(height: 6),
              TextField(
                controller: _nameCtrl,
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  hintText: 'Enter product name',
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppColors.divider),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Price', style: AppTextStyles.caption),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d{0,2}')),
                          ],
                          style: AppTextStyles.body,
                          decoration: InputDecoration(
                            hintText: '0.00',
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: AppColors.divider),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _pickerField(
                      label: 'Unit',
                      hint: 'Select unit',
                      value: _unit,
                      options: widget.units,
                      onSelected: (v) => setState(() => _unit = v),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Add Product'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Search + list content for picking a category/unit — a generic version
/// of the id/name searchable picker already used by the Party form, but
/// keyed here on [CustomProductOption] instead of a plain name string.
class _SearchableOptionSheet extends StatefulWidget {
  final String title;
  final List<CustomProductOption> options;
  final CustomProductOption? selected;

  const _SearchableOptionSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  @override
  State<_SearchableOptionSheet> createState() =>
      _SearchableOptionSheetState();
}

class _SearchableOptionSheetState extends State<_SearchableOptionSheet> {
  late List<CustomProductOption> _filtered = widget.options;

  void _onSearchChanged(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.options
          : widget.options
              .where((o) => o.name.toLowerCase().contains(q))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title,
                        style: AppTextStyles.body
                            .copyWith(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: AppColors.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SearchField(
                hint: 'Search $_lowerTitle',
                onChanged: _onSearchChanged,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _filtered.isEmpty
                  ? EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No matches',
                      subtitle: 'Try a different search',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) {
                        final option = _filtered[i];
                        final selected = option.id == widget.selected?.id;
                        return ListTile(
                          title: Text(option.name, style: AppTextStyles.body),
                          trailing: selected
                              ? Icon(Icons.check_rounded,
                                  color: AppColors.gold)
                              : null,
                          onTap: () => Navigator.of(context).pop(option),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String get _lowerTitle => widget.title.toLowerCase();
}
