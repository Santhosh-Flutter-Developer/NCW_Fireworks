import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/receipt/id_name.dart';
import 'receipt_controller.dart';

class ReceiptFormView extends GetView<ReceiptController> {
  const ReceiptFormView({super.key});

  static final _df = DateFormat('dd MMM yyyy');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.midnight,
      appBar: AppBar(title: const Text('Add Receipt')),
      body: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
              child: SafeArea(
                child: Obx(() {
                  if (controller.isLoadingForm.value) {
                    return Center(
                      child: CircularProgressIndicator(color: AppColors.gold),
                    );
                  }
                  return _formBody(context);
                }),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Obx(() => ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        minimumSize: const Size.fromHeight(48)),
                    onPressed: controller.isSaving.value
                        ? null
                        : () async {
                            final ok = await controller.submitReceipt();
                            if (ok) Get.back();
                          },
                    child: controller.isSaving.value
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Submit'),
                  )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
      children: [
        Obx(() => _dateTile(
              context,
              label: 'Receipt Date *',
              date: controller.receiptDate.value,
              onTap: () => _pickDate(context),
            )),
        const SizedBox(
          height: 10.0,
        ),
        _staticTile(
          label: 'Receipt Type *',
          value: 'Billwise Payment',
        ),
        const SizedBox(
          height: 10.0,
        ),
        const _BillNumberField(),
        const SizedBox(
          height: 10.0,
        ),
        _labelledField(
          label: 'Deduction',
          child: TextField(
            controller: controller.deductionCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(hintText: '0'),
            onChanged: controller.onDeductionChanged,
          ),
        ),
        const SizedBox(
          height: 10.0,
        ),
        _labelledField(
          label: 'Narration',
          hint: r'Max Char: 150(Except <>?{}!*^%$)',
          child: TextField(
            controller: controller.narrationCtrl,
            maxLength: 150,
            maxLines: 2,
            decoration: const InputDecoration(hintText: '', counterText: ''),
          ),
        ),
        const SizedBox(
          height: 20.0,
        ),
        /*Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Obx(() => _dateTile(
                    context,
                    label: 'Receipt Date *',
                    date: controller.receiptDate.value,
                    onTap: () => _pickDate(context),
                  )),
            ),
            const SizedBox(width: 12),
            Expanded(
              // `receipt.php` always saves `receipt_type = 1` (Billwise
              // Payment) regardless of what's sent — there's no second
              // mode to switch to, so this mirrors the web app's dropdown
              // look without pretending it's a real choice.
              child: _staticTile(
                label: 'Receipt Type *',
                value: 'Billwise Payment',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              flex: 2,
              child: _BillNumberField(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _labelledField(
                label: 'Deduction',
                child: TextField(
                  controller: controller.deductionCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: '0'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _labelledField(
          label: 'Narration',
          hint: r'Max Char: 150(Except <>?{}!*^%$)',
          child: TextField(
            controller: controller.narrationCtrl,
            maxLength: 150,
            maxLines: 2,
            decoration: const InputDecoration(hintText: '', counterText: ''),
          ),
        ),
        const SizedBox(height: 20),*/
        Obx(() {
          if (!controller.hasBillLoaded) return const SizedBox.shrink();
          return _BillSummaryCard(controller: controller);
        }),
        const SizedBox(height: 20),
        Obx(() {
          if (!controller.hasBillLoaded) return const SizedBox.shrink();
          return _AddToBillRow(controller: controller);
        }),
        const SizedBox(height: 16),
        Obx(() {
          if (controller.paymentLines.isEmpty) {
            return const SizedBox.shrink();
          }
          return _PaymentLinesTable(controller: controller);
        }),
      ],
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: controller.receiptDate.value,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) controller.receiptDate.value = picked;
  }

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

  Widget _staticTile({required String label, required String value}) {
    return Container(
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
          Text(value, style: AppTextStyles.bodyStrong),
        ],
      ),
    );
  }

  Widget _labelledField({
    required String label,
    String? hint,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption),
          child,
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(hint,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted)),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bill Number: free-text field that looks up the bill on submit, mirroring
// the web app triggering `payment_bill_number` on blur/enter rather than
// on every keystroke.
// ---------------------------------------------------------------------------

class _BillNumberField extends GetView<ReceiptController> {
  const _BillNumberField();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bill Number *', style: AppTextStyles.caption),
          Row(
            children: [
              Expanded(
                child: Obx(()=>TextField(
                  controller: controller.billNumberCtrl.value,
                  readOnly: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration:
                      const InputDecoration(hintText: 'e.g. EST021/26-27'),
                  onSubmitted: (_) => controller.lookupBillNumber(),
                  onChanged: (value) {
                    controller.lookupBillNumber();
                  },
                  onEditingComplete: controller.lookupBillNumber,
                ),)
              ),
              /*Obx(() => controller.isLookingUpBill.value
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.search_rounded, color: AppColors.gold),
                      onPressed: controller.lookupBillNumber,
                    )),*/
            ],
          ),
          Obx(() {
            final err = controller.billLookupError.value;
            if (err == null) return const SizedBox(height: 4);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(err,
                  style:
                      AppTextStyles.caption.copyWith(color: AppColors.danger)),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bill summary — Bill No / Party / Total Amount / (client-computed)
// Balance To Pay, shown once a bill number is successfully looked up.
// ---------------------------------------------------------------------------

class _BillSummaryCard extends StatelessWidget {
  final ReceiptController controller;
  const _BillSummaryCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('Bill No', controller.billFoundNumber.value),
            _kv('Party', controller.billParty.value),
            _kv('Total Amount',
                '₹${controller.billTotalAmount.value.toStringAsFixed(2)}'),
            if (controller.deduction > 0)
              _kv('Deduction',
                  '- ₹${controller.deduction.toStringAsFixed(2)}'),
            _kv('Balance To Pay',
                '₹${controller.remainingForBill.toStringAsFixed(2)}',
                emphasize: true),
          ],
        ),
      );
    });
  }

  Widget _kv(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.body),
          const SizedBox(
            width: 20,
          ),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                maxLines: 2,
                style: emphasize
                    ? AppTextStyles.bodyStrong.copyWith(color: AppColors.gold)
                    : AppTextStyles.bodyStrong),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "Add To Bill" row: Payment Mode / Bank (conditional) / Amount / button.
// ---------------------------------------------------------------------------

class _AddToBillRow extends StatelessWidget {
  final ReceiptController controller;
  const _AddToBillRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Obx(() => _IdNameDropdown(
                      label: 'Payment Mode *',
                      value: controller.selectedPaymentMode.value,
                      items: controller.paymentModeOptions,
                      onChanged: controller.selectPaymentMode,
                    )),
              ),
              // const SizedBox(width: 10),
              // Obx(() {
              //   if (controller.bankOptions.isEmpty) {
              //     return const SizedBox.shrink();
              //   }
              //   return Expanded(
              //     child: _IdNameDropdown(
              //       label: 'Bank *',
              //       value: controller.selectedBank.value,
              //       items: controller.bankOptions,
              //       onChanged: controller.selectBank,
              //     ),
              //   );
              // }),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Expanded(
              //   child: Obx(() => _IdNameDropdown(
              //         label: 'Payment Mode *',
              //         value: controller.selectedPaymentMode.value,
              //         items: controller.paymentModeOptions,
              //         onChanged: controller.selectPaymentMode,
              //       )),
              // ),
              // const SizedBox(width: 10),
              Obx(() {
                if (controller.bankOptions.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Expanded(
                  child: _IdNameDropdown(
                    label: 'Bank *',
                    value: controller.selectedBank.value,
                    items: controller.bankOptions,
                    onChanged: controller.selectBank,
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: TextField(
                    controller: controller.amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        hintText: 'Amount *',
                        border: InputBorder.none),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.teal),
                onPressed: controller.addPaymentLine,
                child: const Text('Add To Bill'),
              ),
            ],
          ),
          Obx(() {
            if (controller.isLoadingBalance.value) {
              return const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            final balance = controller.accountBalance.value;
            if (balance == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Account Balance : ${balance.toStringAsFixed(2)}',
                style:
                    AppTextStyles.bodyStrong.copyWith(color: AppColors.danger),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _IdNameDropdown extends StatelessWidget {
  final String label;
  final IdName? value;
  final List<IdName> items;
  final ValueChanged<IdName?> onChanged;
  const _IdNameDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<IdName>(
          isExpanded: true,
          value: items.contains(value) ? value : null,
          hint: Text(label,
              style: AppTextStyles.body.copyWith(color: AppColors.textMuted)),
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.textMuted),
          style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
          dropdownColor: AppColors.surfaceElevated,
          items: items
              .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(e.name, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment lines table ("S.No / Payment Mode / Bank Name / Amount / Action")
// ---------------------------------------------------------------------------

class _PaymentLinesTable extends StatelessWidget {
  final ReceiptController controller;
  const _PaymentLinesTable({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final lines = controller.paymentLines;
      return Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              clipBehavior: Clip.antiAlias,
              width: 600,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  Container(
                    color: AppColors.surfaceElevated,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 16),
                    child: Row(
                      children: [
                        _headerCell('S.No', flex: 1),
                        _headerCell('Payment Mode', flex: 3),
                        _headerCell('Bank Name', flex: 4),
                        _headerCell('Amount', flex: 2),
                        _headerCell('', flex: 1),
                      ],
                    ),
                  ),
                  for (var i = 0; i < lines.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                              flex: 1,
                              child:
                                  Text('${i + 1}', style: AppTextStyles.body)),
                          Expanded(
                              flex: 3,
                              child: Text(lines[i].paymentModeName,
                                  style: AppTextStyles.body)),
                          Expanded(
                              flex: 4,
                              child: Text(
                                lines[i].bankName.isEmpty
                                    ? '-'
                                    : lines[i].bankName,
                                style: AppTextStyles.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              )),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              key: ValueKey('amount_$i'),
                              initialValue: lines[i].amount.toStringAsFixed(2),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(isDense: true),
                              onChanged: (v) =>
                                  controller.updatePaymentLineAmount(
                                      i, double.tryParse(v) ?? 0),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.delete_outline_rounded,
                                  color: AppColors.danger, size: 18),
                              onPressed: () => controller.removePaymentLine(i),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // const Divider(height: 1),
                  // Padding(
                  //   padding: const EdgeInsets.symmetric(
                  //       horizontal: 12, vertical: 16),
                  //   child: Row(
                  //     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  //     children: [
                  //       Text('Total Amount :', style: AppTextStyles.bodyStrong),
                  //       Text('₹${controller.addedTotal.toStringAsFixed(2)}',
                  //           style: AppTextStyles.bodyStrong
                  //               .copyWith(color: AppColors.gold)),
                  //     ],
                  //   ),
                  // ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Amount :', style: AppTextStyles.bodyStrong),
                Text('₹${controller.addedTotal.toStringAsFixed(2)}',
                    style: AppTextStyles.bodyStrong
                        .copyWith(color: AppColors.gold)),
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _headerCell(String label, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(label,
          style: AppTextStyles.caption.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          )),
    );
  }
}