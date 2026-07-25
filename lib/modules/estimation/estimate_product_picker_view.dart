import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/estimate/estimate_product_list_response_model.dart';
import '../../data/models/estimate/id_name.dart';
import '../../routes/app_routes.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/custom_product_form_sheet.dart';
import 'estimation_controller.dart';

/// A product picked on this screen, kept alongside the exact pricelist
/// option (rate/unit/section) it was picked under — see
/// [EstimationController.addProductSelections].
class _SelectedLine {
  final EstimateProductOption option;
  int qty;
  _SelectedLine({required this.option, required this.qty});
}

/// Full-screen (never a bottom sheet) product picker for the Add/Edit
/// Estimate form.
///
/// Pricelists are shown as a tab bar across the top; switching tabs
/// reloads the product list for that pricelist. Products can be picked
/// across as many tabs as needed before committing them all to the
/// estimate in one "Add to Estimate" tap.
///
/// When [isEntryPoint] is true (the "Add" button on the Estimate list),
/// this screen *is* the first step of creating an estimate: confirming
/// here hands off straight to the Add Estimate form instead of just
/// popping back to it.
class EstimateProductPickerView extends StatefulWidget {
  final bool isEntryPoint;
  const EstimateProductPickerView({super.key, this.isEntryPoint = false});

  @override
  State<EstimateProductPickerView> createState() =>
      _EstimateProductPickerViewState();
}

class _EstimateProductPickerViewState extends State<EstimateProductPickerView> {
  final controller = Get.find<EstimationController>();

  /// productId -> selection picked on this screen (possibly spanning
  /// several pricelist tabs). Nothing is written to the estimate until
  /// "Add to Estimate" is tapped.
  final Map<String, _SelectedLine> _selections = {};
  String _query = '';
  bool _isGrid = true;

  @override
  void initState() {
    super.initState();
    // Pre-fill with products already on the estimate (from any
    // pricelist) so reopening the picker to top up shows current counts.
    for (final item in controller.formItems) {
      _selections[item.productId] = _SelectedLine(
        option: EstimateProductOption(
          productId: item.productId,
          productName: item.productName,
          unitId: item.unitId,
          unitName: item.unit,
          rate: item.rate,
          productDiscount: item.section == 1,
          currentStock: controller.stockFor(item.productId),
        ),
        qty: item.quantity,
      );
    }
  }

  int get _totalItemsSelected =>
      _selections.values.fold(0, (a, l) => a + l.qty);

  double get _totalAmountSelected =>
      _selections.values.fold(0.0, (sum, l) => sum + (l.qty * l.option.rate));

  List<EstimateProductOption> get _filtered {
    final all = controller.productOptions;
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((p) => p.productName.toLowerCase().contains(q)).toList();
  }

  void _setQty(EstimateProductOption option, int qty) {
    setState(() {
      if (qty <= 0) {
        _selections.remove(option.productId);
      } else {
        _selections[option.productId] = _SelectedLine(option: option, qty: qty);
      }
    });
  }

  void _selectPricelistTab(IdName pricelist) {
    controller.selectPricelist(pricelist);
  }

  void _addCustomProduct() {
    showAddCustomProductSheet(
      context: context,
      categories: controller.customCategories,
      units: controller.customUnits,
      onSubmit: ({
        required categoryId,
        required categoryName,
        required productName,
        required unitId,
        required unitName,
        required price,
      }) =>
          controller.addCustomProduct(
        categoryId: categoryId,
        categoryName: categoryName,
        productName: productName,
        unitId: unitId,
        unitName: unitName,
        price: price,
      ),
    );
  }

  void _confirm() {
    if (_selections.isEmpty) {
      Get.snackbar('No products selected', 'Pick at least one product first',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    controller.addProductSelections(
      _selections.values.map((l) => MapEntry(l.option, l.qty)).toList(),
    );
    if (widget.isEntryPoint) {
      Get.offNamed(AppRoutes.estimationForm);
    } else {
      Get.back();
    }
  }

  Future<void> _confirmBack() async {
    final confirmed = await confirmDialog(
      title: 'Go back?',
      message: 'Are you sure you want to go back? '
          'Any product selections made here will be lost.',
    );
    if (confirmed) Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _confirmBack();
      },
      child: Scaffold(
      backgroundColor: AppColors.midnight,
      appBar: AppBar(
        title: const Text('Select Products'),
        actions: [
          IconButton(
            tooltip: 'Add custom product',
            onPressed: _addCustomProduct,
            icon: const Icon(Icons.add_box_outlined),
          ),
          IconButton(
            tooltip: _isGrid ? 'List view' : 'Grid view',
            onPressed: () => setState(() => _isGrid = !_isGrid),
            icon: Icon(
                _isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded),
          ),
          const SizedBox(
            width: 8.0,
          ),
          /*Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.shopping_cart_outlined),
                ),
                if (_totalItemsSelected > 0)
                  Positioned(
                    right: 0,
                    top: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$_totalItemsSelected',
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),*/
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              Obx(() {
                if (controller.pricelistOptions.isEmpty) {
                  return const SizedBox.shrink();
                }
                return _PricelistTabBar(
                  pricelists: controller.pricelistOptions,
                  selectedId: controller.selectedPricelistId.value,
                  onSelected: _selectPricelistTab,
                );
              }),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: SearchField(
                  hint: 'Search product',
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              Expanded(
                child: Obx(() {
                  if (controller.pricelistOptions.isEmpty ||
                      controller.isLoadingProducts.value) {
                    return Center(
                        child:
                            CircularProgressIndicator(color: AppColors.gold));
                  }
                  final items = _filtered;
                  if (items.isEmpty) {
                    return EmptyState(
                      icon: Icons.celebration_outlined,
                      title: 'No products found',
                      subtitle: _query.isEmpty
                          ? 'No products found for this pricelist'
                          : 'No matches for "$_query"',
                    );
                  }
                  return _isGrid ? _gridView(items) : _listView(items);
                }),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$_totalItemsSelected item(s) selected',
                        style: AppTextStyles.caption),
                    Text('₹${_totalAmountSelected.toStringAsFixed(2)}',
                        style:
                            AppTextStyles.h3.copyWith(color: AppColors.gold)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                ),
                onPressed: _totalItemsSelected == 0 ? null : _confirm,
                child: const Text('Add to Estimate'),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _gridView(List<EstimateProductOption> items) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemBuilder: (context, i) => _ProductCard(
        option: items[i],
        qty: _selections[items[i].productId]?.qty ?? 0,
        onChanged: (qty) => _setQty(items[i], qty),
      ),
    );
  }

  Widget _listView(List<EstimateProductOption> items) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _ProductListTile(
        option: items[i],
        qty: _selections[items[i].productId]?.qty ?? 0,
        onChanged: (qty) => _setQty(items[i], qty),
      ),
    );
  }
}

/// Horizontally-scrollable pricelist tabs shown above the product list.
/// Switching tabs asks the controller to load that pricelist's products —
/// selections already made under other tabs are untouched.
class _PricelistTabBar extends StatelessWidget {
  final List<IdName> pricelists;
  final String? selectedId;
  final ValueChanged<IdName> onSelected;
  const _PricelistTabBar({
    required this.pricelists,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: pricelists.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final pricelist = pricelists[i];
          final selected = pricelist.id == selectedId;
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onSelected(pricelist),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              decoration: BoxDecoration(
                gradient: selected ? AppColors.goldGradient : null,
                color: selected ? null : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? Colors.transparent : AppColors.divider,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                pricelist.name,
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color:
                      selected ? AppColors.textOnGold : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Shared "Add to Cart" button <-> quantity control, used by both the grid
/// card and the list tile. A product with qty 0 shows a single button; as
/// soon as it's tapped it turns into a -/+ stepper with an editable
/// quantity field in the middle, so a large amount (50, 100, ...) can be
/// typed directly instead of tapping + one at a time.
class _AddOrStepper extends StatefulWidget {
  final int qty;
  final ValueChanged<int> onChanged;
  const _AddOrStepper({required this.qty, required this.onChanged});

  @override
  State<_AddOrStepper> createState() => _AddOrStepperState();
}

class _AddOrStepperState extends State<_AddOrStepper> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.qty > 0 ? '${widget.qty}' : '');
  late final FocusNode _focusNode = FocusNode()
    ..addListener(() {
      if (!_focusNode.hasFocus) _commit();
    });

  @override
  void didUpdateWidget(covariant _AddOrStepper old) {
    super.didUpdateWidget(old);
    // Keep the field in sync with external changes (+/- taps, another
    // tab's selection being reapplied, etc.) — but never fight the user
    // while they're actively typing in it.
    if (!_focusNode.hasFocus && widget.qty != old.qty) {
      _ctrl.text = widget.qty > 0 ? '${widget.qty}' : '';
    }
  }

  void _commit() {
    final parsed = int.tryParse(_ctrl.text.trim());
    final qty = (parsed == null || parsed < 0) ? 0 : parsed;
    _ctrl.text = qty > 0 ? '$qty' : '';
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
    if (widget.qty <= 0 && !_focusNode.hasFocus) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => widget.onChanged(1),
          child: const Text(
            'Add to Cart',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.0),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _stepBtn(Icons.remove_rounded, AppColors.danger,
              () => widget.onChanged(widget.qty > 0 ? widget.qty - 1 : 0)),
          Expanded(
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
          _stepBtn(Icons.add_rounded, AppColors.success,
              () => widget.onChanged(widget.qty + 1)),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final EstimateProductOption option;
  final int qty;
  final ValueChanged<int> onChanged;
  const _ProductCard(
      {required this.option, required this.qty, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final selected = qty > 0;
    return GestureDetector(
      onTap: () {
        if (qty <= 0) {
          onChanged(1);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.divider,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 62,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: AppColors.tealGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.celebration_rounded,
                  color: Colors.white, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              option.productName,
              style: AppTextStyles.bodyStrong,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '₹${option.rate.toStringAsFixed(2)} / ${option.unitName.isEmpty ? 'Pcs' : option.unitName}',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.gold, fontWeight: FontWeight.w700),
            ),
            if (option.currentStock > 0) ...[
              const SizedBox(height: 2),
              Text('Stock: ${option.currentStock}',
                  style: AppTextStyles.caption),
            ],
            const Spacer(),
            const SizedBox(height: 8),
            _AddOrStepper(qty: qty, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _ProductListTile extends StatelessWidget {
  final EstimateProductOption option;
  final int qty;
  final ValueChanged<int> onChanged;
  const _ProductListTile(
      {required this.option, required this.qty, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final selected = qty > 0;
    return GestureDetector(
      onTap: () {
        if (qty <= 0) {
          onChanged(1);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.divider,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                gradient: AppColors.tealGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.celebration_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.productName,
                    style: AppTextStyles.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '₹${option.rate.toStringAsFixed(2)} / ${option.unitName.isEmpty ? 'Pcs' : option.unitName}',
                    style: AppTextStyles.caption.copyWith(
                        color: AppColors.gold, fontWeight: FontWeight.w700),
                  ),
                  if (option.currentStock > 0)
                    Text('Stock: ${option.currentStock}',
                        style: AppTextStyles.caption),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 112,
              child: _AddOrStepper(qty: qty, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}
