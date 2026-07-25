import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:ncw_fireworks/modules/quotation/quotation_product_picker_view.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/party_model.dart';
import '../../data/models/quotation/id_name.dart';
import '../../routes/app_routes.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/searchable_picker_sheet.dart';
import '../party/party_controller.dart';
import 'quotation_controller.dart';

class QuotationFormView extends GetView<QuotationController> {
  const QuotationFormView({super.key});

  static final _df = DateFormat('dd MMM yyyy');

  Future<void> _confirmBack() async {
    final confirmed = await confirmDialog(
      title: 'Go back?',
      message: 'Are you sure you want to go back? '
          'Any unsaved changes to this quotation will be lost.',
    );
    if (confirmed) Get.back();
  }

  Future<void> _confirmClear() async {
    final confirmed = await confirmDialog(
      title: 'Clear form?',
      message: 'Are you sure you want to clear this quotation? '
          'All items and details entered will be removed.',
      confirmText: 'Clear',
      danger: true,
    );
    if (confirmed) controller.clearForm();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = controller.editingQuotation != null;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _confirmBack();
      },
      child: Scaffold(
      backgroundColor: AppColors.midnight,
      appBar: AppBar(
        title: Text(isEditing
            ? 'Edit Quotation - ${controller.editingQuotation!.quotationNo}'
            : 'Add Quotation'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
              child: SafeArea(
                child: Obx(() {
                  if (controller.isLoadingForm.value) {
                    return  Center(
                      child: CircularProgressIndicator(color: AppColors.gold),
                    );
                  }
                  return _formBody(context);
                }),
              ),
            ),
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _confirmClear,
                        child: const Text('Clear'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _showPreview(context),
                        child: const Text('Preview'),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Obx(() => Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.magenta),
                        onPressed: controller.isSaving.value
                            ? null
                            : () => controller.save(asDraft: true),
                        child: const Text('Draft'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success),
                        onPressed: controller.isSaving.value
                            ? null
                            : () => controller.save(asDraft: false),
                        child: controller.isSaving.value
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Confirm'),
                      ),
                    ),
                  ],
                )),
              ),
            ],
          )
        ],
      ),
      /*bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => controller.clearForm(),
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _showPreview(context),
                  child: const Text('Preview'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success),
                  onPressed: () => controller.save(asDraft: false),
                  child: const Text('Confirm'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style:
                      ElevatedButton.styleFrom(backgroundColor: AppColors.magenta),
                  onPressed: () => controller.save(asDraft: true),
                  child: const Text('Draft'),
                ),
              ),
            ],
          ),
        ),
      ),*/
      ),
    );
  }

  // ---- Section of items -----------------------------------------------

  Widget _formBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 160),
      children: [
        Obx(() => _GrandTotalBanner(total: controller.formTotal)),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _dateTile(
                context,
                label: 'Bill Date *',
                date: controller.quotationDate.value,
                onTap: () => _pickDate(context, controller.quotationDate),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Obx(() => _pickerTile(
                    label: 'Pricelist *',
                    value: controller.selectedPricelist.value,
                    onTap: () => _openPricelistPicker(context),
                  )),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Obx(() => _pickerTile(
                    label: 'Party *',
                    value: controller.selectedParty.value?.name,
                    onTap: () => _openPartyPicker(context),
                  )),
            ),
            const SizedBox(width: 8),
            _addPartyButton(context),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Items', style: AppTextStyles.h3),
            TextButton.icon(
              onPressed: () => _openProductPicker(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Item'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Obx(() {
          if (controller.formItems.isEmpty) {
            return const EmptyState(
              icon: Icons.shopping_basket_outlined,
              title: 'No items added',
              subtitle: 'Tap "Add Item" to add products to this quotation.',
            );
          }
          return Column(
            children: [
              _sectionBlock(section: 1, label: 'Section 1'),
              const SizedBox(height: 14),
              _sectionBlock(section: 2, label: 'Section 2'),
            ],
          );
        }),
        const SizedBox(height: 14),
        Obx(() => _totalsCard()),
      ],
    );
  }

  Widget _sectionBlock({required int section, required String label}) {
    return Obx(() {
      final indices = List.generate(controller.formItems.length, (i) => i)
          .where((i) => controller.formItems[i].section == section)
          .toList();
      final total = section == 1
          ? controller.formSection1Total
          : controller.formSection2Total;
      if (indices.isEmpty && section == 2) {
        // Keep Section 2 out of the way until it's actually used.
        return const SizedBox.shrink();
      }
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: AppTextStyles.bodyStrong),
                Text('₹${total.toStringAsFixed(2)}',
                    style: AppTextStyles.bodyStrong
                        .copyWith(color: AppColors.gold)),
              ],
            ),
            if (indices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text('No items in this section',
                    style: AppTextStyles.caption),
              )
            else
              ...indices.map((i) => _itemRow(i)),
          ],
        ),
      );
    });
  }

  Future<void> _confirmRemoveItem(int i, String productName) async {
    final confirmed = await confirmDialog(
      title: 'Remove item?',
      message: 'Are you sure you want to remove "$productName" from this quotation?',
      confirmText: 'Remove',
      danger: true,
    );
    if (confirmed) controller.removeItem(i);
  }

  Widget _itemRow(int i) {
    final item = controller.formItems[i];
    return Container(
      key: ValueKey('item_${item.productId}_${item.section}'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.productName, style: AppTextStyles.bodyStrong),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () =>
                    controller.moveToSection(i, item.section == 1 ? 2 : 1),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Move to S${item.section == 1 ? 2 : 1}',
                      style: AppTextStyles.caption),
                ),
              ),
              IconButton(
                onPressed: () => _confirmRemoveItem(i, item.productName),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded,
                    size: 18, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
              'Rate: ₹${item.rate.toStringAsFixed(2)} / ${item.unit}',
              style: AppTextStyles.caption),
          const SizedBox(height: 6),
          Row(
            children: [
              _QtyStepperField(
                key: ValueKey('qty_${item.productId}_${item.section}'),
                qty: item.quantity,
                unit: item.unit,
                onChanged: (qty) => controller.updateQuantity(i, qty),
              ),
              const SizedBox(width: 10),
              Spacer(),
              // Expanded(
              //   child: Text(
              //       'Rate: ₹${item.rate.toStringAsFixed(2)} / ${item.unit}',
              //       style: AppTextStyles.caption),
              // ),
              Text(
                '₹${item.amount.toStringAsFixed(2)}',
                style: AppTextStyles.bodyStrong,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- Totals card -------------------------------------------------------

  Widget _totalsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _adjustRow(
            label: 'Section 1',
            total: controller.formSection1Total,
            addValue: controller.section1Add,
            addCtrl: controller.section1AddCtrl,
            discountValue: controller.section1Discount,
            discountCtrl: controller.section1DiscountCtrl,
            onDiscountChanged: controller.setSection1DiscountInput,
          ),
          const Divider(height: 24),
          _adjustRow(
            label: 'Section 2',
            total: controller.formSection2Total,
            addValue: controller.section2Add,
            addCtrl: controller.section2AddCtrl,
            discountValue: controller.section2Discount,
            discountCtrl: controller.section2DiscountCtrl,
            onDiscountChanged: controller.setSection2DiscountInput,
          ),
          const Divider(height: 24),
          _summaryRow('Subtotal', controller.formSubTotal),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Round Off', style: AppTextStyles.body),
              Text(
                '${controller.roundOff >= 0 ? '+' : '-'}₹${controller.roundOff.abs().toStringAsFixed(2)}',
                style: AppTextStyles.body,
              ),
            ],
          ),
          const Divider(height: 24),
          _summaryRow('Overall Total', controller.formTotal, isBold: true),
        ],
      ),
    );
  }

  Widget _adjustRow({
    required String label,
    required double total,
    required RxDouble addValue,
    required TextEditingController addCtrl,
    required RxDouble discountValue,
    required TextEditingController discountCtrl,
    required ValueChanged<String> onDiscountChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$label Total', style: AppTextStyles.bodyStrong),
            Text('₹${total.toStringAsFixed(2)}',
                style: AppTextStyles.bodyStrong),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _valueField(label: 'Add', rx: addValue, ctrl: addCtrl),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _valueField(
                label: 'Discount',
                rx: discountValue,
                ctrl: discountCtrl,
                allowPercent: true,
                onChanged: onDiscountChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _valueField({
    required String label,
    required RxDouble rx,
    required TextEditingController ctrl,
    bool allowPercent = false,
    ValueChanged<String>? onChanged,
  }) {
    return Row(
      children: [
        Text('$label: ', style: AppTextStyles.caption),
        Expanded(
          child: TextField(
            textAlign: TextAlign.end,
            // Plain numeric keyboard can't type '%', so switch to text
            // when a percentage entry ("10%") should be allowed.
            keyboardType: allowPercent
                ? TextInputType.text
                : const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                  allowPercent ? RegExp(r'[0-9.%]') : RegExp(r'[0-9.]')),
            ],
            controller: ctrl,
            decoration: InputDecoration(
                hintText: allowPercent ? 'Value or %' : 'Value'),
            onChanged: onChanged ?? (v) => rx.value = double.tryParse(v) ?? 0,
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, double value, {bool isBold = false}) {
    final style = isBold
        ? AppTextStyles.h3.copyWith(color: AppColors.gold)
        : AppTextStyles.bodyStrong;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text('₹${value.toStringAsFixed(2)}', style: style),
      ],
    );
  }

  // ---- Header field tiles --------------------------------------------------

  Widget _dateTile(
    BuildContext context, {
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today_rounded,
                    size: 14, color: AppColors.gold),
                const SizedBox(width: 6),
                Text(_df.format(date), style: AppTextStyles.bodyStrong),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickerTile({
    required String label,
    required String? value,
    String placeholder = 'Select',
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value ?? placeholder,
                    style: AppTextStyles.bodyStrong.copyWith(
                      color: value != null
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textMuted, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- Pickers ---------------------------------------------------------

  Future<void> _pickDate(BuildContext context, Rx<DateTime> target) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: target.value,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null) target.value = picked;
  }

  void _openPricelistPicker(BuildContext context) {
    showSearchablePickerSheet<IdName>(
      title: 'Select Pricelist',
      searchHint: 'Search pricelist',
      itemsGetter: () => controller.pricelistOptions,
      labelOf: (idn) => idn.name,
      itemBuilder: (context, idn) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(idn.name, style: AppTextStyles.bodyStrong),
      ),
      onSelected: (idn) => controller.selectPricelist(idn),
    );
  }

  void _openPartyPicker(BuildContext context) {
    showSearchablePickerSheet<PartyModel>(
      title: 'Select Party',
      searchHint: 'Search party name or phone',
      itemsGetter: () => controller.parties,
      labelOf: (p) => '${p.name} ${p.phone}',
      itemBuilder: (context, p) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: AppColors.surfaceHigh,
          child: Text(p.initials,
              style:
                  AppTextStyles.caption.copyWith(color: AppColors.textPrimary)),
        ),
        title: Text(p.name, style: AppTextStyles.bodyStrong),
        subtitle:
            p.phone.isEmpty ? null : Text(p.phone, style: AppTextStyles.caption),
      ),
      onSelected: (p) => controller.selectedParty.value = p,
    );
  }

  /// A compact "+" button sitting next to the Party field, matching the
  /// height of the picker tile beside it. Opens the Party form fresh
  /// (Add Party) and, once saved — Draft or Submit, online or off —
  /// selects whatever party it created straight into this quotation.
  Widget _addPartyButton(BuildContext context) {
    return SizedBox(
      height: 58,
      width: 48,
      child: Material(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openAddParty(context),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Icon(Icons.add_rounded, color: AppColors.gold),
          ),
        ),
      ),
    );
  }

  Future<void> _openAddParty(BuildContext context) async {
    final partyController = Get.isRegistered<PartyController>()
        ? Get.find<PartyController>()
        : Get.put(PartyController());
    partyController.startCreate();
    final result = await Get.toNamed(AppRoutes.partyForm);
    if (result is PartyModel) {
      controller.addAndSelectParty(result);
    }
  }

  void _openProductPicker(BuildContext context) {
    if (controller.selectedPricelistId.value == null ||
        controller.selectedPricelistId.value!.isEmpty) {
      Get.snackbar('Select a pricelist first',
          'Products depend on the pricelist chosen above.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    Get.to(() => const QuotationProductPickerView());
    /*showSearchablePickerSheet<QuotationProductOption>(
      title: 'Select Product',
      subtitle: 'The section (1 or 2) is set automatically from the pricelist.',
      searchHint: 'Search product',
      isLoadingGetter: () => controller.isLoadingProducts.value,
      itemsGetter: () => controller.productOptions,
      labelOf: (p) => p.productName,
      emptyText: 'No products found for this pricelist',
      itemBuilder: (context, p) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: AppColors.tealGradient,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.celebration_rounded,
              color: Colors.white, size: 18),
        ),
        title: Text(p.productName, style: AppTextStyles.bodyStrong),
      ),
      onSelected: (p) async {
        await controller.addProductById(
          productId: p.productId,
          productName: p.productName,
        );
      },
    );*/
  }

  void _showPreview(BuildContext context) {
    Get.dialog(
      AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Preview', style: AppTextStyles.h3),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: Obx(() => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                        'Party: ${controller.selectedParty.value?.name ?? '-'}',
                        style: AppTextStyles.body),
                    Text('Date: ${_df.format(controller.quotationDate.value)}',
                        style: AppTextStyles.body),
                    const Divider(height: 20),
                    ...controller.formItems.map((i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                    '${i.productName} x${i.quantity} ${i.unit}',
                                    style: AppTextStyles.caption),
                              ),
                              Text('₹${i.amount.toStringAsFixed(2)}',
                                  style: AppTextStyles.caption),
                            ],
                          ),
                        )),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Overall Total', style: AppTextStyles.bodyStrong),
                        Text('₹${controller.formTotal.toStringAsFixed(2)}',
                            style: AppTextStyles.bodyStrong
                                .copyWith(color: AppColors.gold)),
                      ],
                    ),
                  ],
                )),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _GrandTotalBanner extends StatelessWidget {
  final double total;
  const _GrandTotalBanner({required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Grand Total',
              style: AppTextStyles.body.copyWith(color: AppColors.textOnGold)),
          Text('₹ ${total.toStringAsFixed(2)}',
              style: AppTextStyles.h3.copyWith(color: AppColors.textOnGold)),
        ],
      ),
    );
  }
}

/// -/+ stepper for an item row with an editable quantity field in the
/// middle, so a large amount (50, 100, ...) can be typed directly instead
/// of tapping + one at a time. Quantity can never go below 1 here — to
/// remove an item entirely the row has its own "x" button.
class _QtyStepperField extends StatefulWidget {
  final int qty;
  final String unit;
  final ValueChanged<int> onChanged;
  const _QtyStepperField(
      {super.key, required this.qty, required this.unit, required this.onChanged});

  @override
  State<_QtyStepperField> createState() => _QtyStepperFieldState();
}

class _QtyStepperFieldState extends State<_QtyStepperField> {
  late final TextEditingController _ctrl =
      TextEditingController(text: '${widget.qty}');
  late final FocusNode _focusNode = FocusNode()
    ..addListener(() {
      if (!_focusNode.hasFocus) _commit();
    });

  @override
  void didUpdateWidget(covariant _QtyStepperField old) {
    super.didUpdateWidget(old);
    // Keep the field in sync with external changes (+/- taps) — but
    // never fight the user while they're actively typing in it.
    if (!_focusNode.hasFocus && widget.qty != old.qty) {
      _ctrl.text = '${widget.qty}';
    }
  }

  void _commit() {
    final parsed = int.tryParse(_ctrl.text.trim());
    final qty = (parsed == null || parsed < 1) ? 1 : parsed;
    _ctrl.text = '$qty';
    if (qty != widget.qty) widget.onChanged(qty);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () =>
                widget.onChanged(widget.qty > 1 ? widget.qty - 1 : 1),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_rounded, size: 16),
          ),
          SizedBox(
            width: 44,
            child: TextField(
              controller: _ctrl,
              focusNode: _focusNode,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: AppTextStyles.bodyStrong,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
              ),
              onSubmitted: (_) => _commit(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(widget.unit, style: AppTextStyles.bodyStrong),
          ),
          IconButton(
            onPressed: () => widget.onChanged(widget.qty + 1),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_rounded, size: 16),
          ),
        ],
      ),
    );
  }
}