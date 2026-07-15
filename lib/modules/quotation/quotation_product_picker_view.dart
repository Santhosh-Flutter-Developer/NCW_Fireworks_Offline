import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/quotation/quotation_product_list_response_model.dart';
import '../../widgets/common_widgets.dart';
import 'quotation_controller.dart';

/// Full-screen (never a bottom sheet) product picker for the Add/Edit
/// Quotation form.
///
/// Shows every product for the currently selected pricelist with its
/// price and unit, lets the user bump quantities with +/- steppers,
/// select as many products as they like, and commit all of them to the
/// quotation in one "Add to Quotation" tap.
class QuotationProductPickerView extends StatefulWidget {
  const QuotationProductPickerView({super.key});

  @override
  State<QuotationProductPickerView> createState() =>
      _QuotationProductPickerViewState();
}

class _QuotationProductPickerViewState
    extends State<QuotationProductPickerView> {
  final controller = Get.find<QuotationController>();

  /// productId -> quantity picked on this screen. Nothing is written to
  /// the quotation until "Add to Quotation" is tapped.
  final Map<String, int> _selections = {};
  String _query = '';
  bool _isGrid = true;

  @override
  void initState() {
    super.initState();
    // Pre-fill with quantities already on the quotation so reopening the
    // picker to top up a product shows its current count, not zero.
    for (final option in controller.productOptions) {
      final existingQty = controller.quantityInFormFor(option.productId);
      if (existingQty > 0) _selections[option.productId] = existingQty;
    }
  }

  int get _totalItemsSelected => _selections.values.fold(0, (a, b) => a + b);

  double get _totalAmountSelected {
    double sum = 0;
    for (final option in controller.productOptions) {
      final qty = _selections[option.productId] ?? 0;
      if (qty > 0) sum += qty * option.rate;
    }
    return sum;
  }

  List<QuotationProductOption> get _filtered {
    final all = controller.productOptions;
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((p) => p.productName.toLowerCase().contains(q)).toList();
  }

  void _setQty(QuotationProductOption option, int qty) {
    setState(() {
      if (qty <= 0) {
        _selections.remove(option.productId);
      } else {
        _selections[option.productId] = qty;
      }
    });
  }

  void _confirm() {
    if (_selections.isEmpty) {
      Get.snackbar('No products selected', 'Pick at least one product first',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    controller.addProductsFromPicker(_selections);
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.midnight,
      appBar: AppBar(
        title: const Text('Select Products'),
        actions: [
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: SearchField(
                  hint: 'Search product',
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              Expanded(
                child: Obx(() {
                  if (controller.isLoadingProducts.value) {
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
                child: const Text('Add to Quotation'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gridView(List<QuotationProductOption> items) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemBuilder: (context, i) => _ProductCard(
        option: items[i],
        qty: _selections[items[i].productId] ?? 0,
        onChanged: (qty) => _setQty(items[i], qty),
      ),
    );
  }

  Widget _listView(List<QuotationProductOption> items) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _ProductListTile(
        option: items[i],
        qty: _selections[items[i].productId] ?? 0,
        onChanged: (qty) => _setQty(items[i], qty),
      ),
    );
  }
}

/// Shared "Add to Cart" button <-> quantity stepper, used by both the grid
/// card and the list tile. A product with qty 0 shows a single button; as
/// soon as it's tapped it turns into a -/+ stepper.
class _AddOrStepper extends StatelessWidget {
  final int qty;
  final ValueChanged<int> onChanged;
  const _AddOrStepper({required this.qty, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (qty <= 0) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => onChanged(1),
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
          _stepBtn(
              Icons.remove_rounded, AppColors.danger, () => onChanged(qty - 1)),
          Text('$qty', style: AppTextStyles.bodyStrong),
          _stepBtn(
              Icons.add_rounded, AppColors.success, () => onChanged(qty + 1)),
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
  final QuotationProductOption option;
  final int qty;
  final ValueChanged<int> onChanged;
  const _ProductCard(
      {required this.option, required this.qty, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final selected = qty > 0;
    return Container(
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
            Text('Stock: ${option.currentStock}', style: AppTextStyles.caption),
          ],
          const Spacer(),
          const SizedBox(height: 8),
          _AddOrStepper(qty: qty, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ProductListTile extends StatelessWidget {
  final QuotationProductOption option;
  final int qty;
  final ValueChanged<int> onChanged;
  const _ProductListTile(
      {required this.option, required this.qty, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final selected = qty > 0;
    return Container(
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
    );
  }
}
