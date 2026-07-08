import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/product_model.dart';
import '../../routes/app_routes.dart';
import '../../widgets/app_data_table.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/view_mode_toggle.dart';
import 'product_controller.dart';

class ProductListView extends GetView<ProductController> {
  const ProductListView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      routeName: AppRoutes.productList,
      title: 'Product',
      body: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: Responsive.horizontalPadding(context),
          vertical: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel(text: 'Category'),
            Obx(() => _categoryDropdown(context)),
            const SizedBox(height: 14),
            SearchField(
              hint: 'Name/Code Search',
              onChanged: controller.setSearch,
            ),
            const SizedBox(height: 14),
            // Row(
            //   children: [
            //     Expanded(
            //       child: _toolbarButton(
            //         icon: Icons.cloud_upload_rounded,
            //         label: 'Stock Upload',
            //         color: AppColors.skyBlue,
            //         onTap: () => _showComingSoon('Stock upload'),
            //       ),
            //     ),
            //     const SizedBox(
            //       width: 10.0,
            //     ),
            //     Expanded(
            //       child: _toolbarButton(
            //         icon: Icons.inventory_2_rounded,
            //         label: 'Product Upload',
            //         color: AppColors.skyBlue,
            //         onTap: () => _showComingSoon('Bulk product upload'),
            //       ),
            //     ),
            //   ],
            // ),
            // const SizedBox(
            //   height: 6.0,
            // ),
            Row(
              children: [
                // _actionIcon(
                //   icon: Icons.download_rounded,
                //   color: AppColors.success,
                //   tooltip: 'Download',
                //   onTap: () => _showComingSoon('Download'),
                // ),
                // const SizedBox(
                //   width: 10.0,
                // ),
                Obx(
                  () => ViewModeToggle(
                    isTableView: controller.isTableView.value,
                    onChanged: controller.toggleViewMode,
                  ),
                ),
                const Spacer(),
                // ElevatedButton.icon(
                //   onPressed: () {
                //     controller.startCreate();
                //     Get.toNamed(AppRoutes.productForm);
                //   },
                //   style: ElevatedButton.styleFrom(
                //     backgroundColor: AppColors.ember,
                //     foregroundColor: Colors.white,
                //     padding: const EdgeInsets.symmetric(horizontal: 16),
                //   ),
                //   icon: const Icon(Icons.add_circle_rounded, size: 18),
                //   label: const Text('Add'),
                // ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Obx(() {
                final list = controller.paginated;
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.inventory_2_rounded,
                    title: 'No products found',
                    subtitle: 'Try a different search or add a new product.',
                  );
                }
                final startIndex =
                    (controller.pageNo.value - 1) * controller.pageLimit.value;
                if (controller.isTableView.value) {
                  return SingleChildScrollView(
                    child: AppDataTable(
                      columns: const [
                        'S.No',
                        'Category',
                        'Code',
                        'Product Name',
                        'Stock Maintain',
                        'Negative Stock',
                        'Current Stock',
                        // 'Action',
                      ],
                      rows: List.generate(list.length, (i) {
                        final p = list[i];
                        return [
                          Text('${startIndex + i + 1}',
                              style: AppTextStyles.body),
                          Text(p.category, style: AppTextStyles.bodyStrong),
                          Text(p.code.isEmpty ? '-' : p.code,
                              style: AppTextStyles.body),
                          SizedBox(
                            width: 220,
                            child: Text(p.name,
                                style: AppTextStyles.bodyStrong,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ),
                          TablePill(
                            label: p.stockMaintain ? 'YES' : 'NO',
                            color: p.stockMaintain
                                ? AppColors.success
                                : AppColors.textMuted,
                          ),
                          TablePill(
                            label: p.negativeStock ? 'YES' : 'NO',
                            color: p.negativeStock
                                ? AppColors.success
                                : AppColors.textMuted,
                          ),
                          Text(
                            p.stockMaintain
                                ? '${p.currentStock} ${p.unit}'
                                : '—',
                            style: AppTextStyles.bodyStrong.copyWith(
                              color: p.currentStock < 0
                                  ? AppColors.danger
                                  : AppColors.textPrimary,
                            ),
                          ),
                          // _actionRow(p),
                        ];
                      }),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 16, left: 0.0),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final product = list[index];
                    return _ProductTile(
                      serial: startIndex + index + 1,
                      product: product,
                      onTap: () {
                        controller.startEdit(product);
                        Get.toNamed(AppRoutes.productForm);
                      },
                      onPrice: () => _openPriceSheet(context, product),
                      onDelete: () => controller.deleteProduct(product),
                    );
                  },
                );
              }),
            ),
            const SizedBox(height: 8),
            Obx(() => _paginationBar()),
          ],
        ),
      ),
    );
  }

  Widget _actionRow(ProductModel p) {
    return Builder(builder: (context) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // IconButton(
          //   tooltip: 'Prices',
          //   visualDensity: VisualDensity.compact,
          //   onPressed: () => _openPriceSheet(context, p),
          //   icon: Icon(Icons.sell_rounded, color: AppColors.skyBlue, size: 18),
          // ),
          IconButton(
            tooltip: 'Edit',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              controller.startEdit(p);
              Get.toNamed(AppRoutes.productForm);
            },
            icon: Icon(Icons.edit_rounded, color: AppColors.teal, size: 18),
          ),
          IconButton(
            tooltip: 'Delete',
            visualDensity: VisualDensity.compact,
            onPressed: () => controller.deleteProduct(p),
            icon: Icon(Icons.delete_outline_rounded,
                color: AppColors.danger, size: 18),
          ),
        ],
      );
    });
  }

  Widget _categoryDropdown(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openCategoryPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.category_rounded, color: AppColors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                controller.filterCategory.value ?? 'All Categories',
                style: AppTextStyles.body.copyWith(
                  color: controller.filterCategory.value != null
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  void _openCategoryPicker(BuildContext context) {
    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(18),
        constraints: BoxConstraints(maxHeight: Get.height * 0.6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Select Category', style: AppTextStyles.h3),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.clear_all_rounded),
                    title: const Text('All Categories'),
                    onTap: () {
                      controller.setCategoryFilter(null);
                      Get.back();
                    },
                  ),
                  ...controller.categoryOptions.map(
                    (c) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.label_outline_rounded),
                      title: Text(c),
                      onTap: () {
                        controller.setCategoryFilter(c);
                        Get.back();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbarButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      icon: Icon(icon, size: 14),
      label: Text(
        label,
        style: const TextStyle(fontSize: 14.0),
      ),
    );
  }

  Widget _actionIcon({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
      ),
    );
  }

  void _showComingSoon(String feature) {
    Get.snackbar(
      feature,
      '$feature will be available once the backend is connected.',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  Widget _paginationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Text('Page Limit', style: AppTextStyles.caption),
          const SizedBox(width: 8),
          _pageLimitDropdown(),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: controller.pageNo.value > 1
                ? () => controller.setPageNo(controller.pageNo.value - 1)
                : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Text('${controller.pageNo.value} / ${controller.totalPages}',
              style: AppTextStyles.bodyStrong),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: controller.pageNo.value < controller.totalPages
                ? () => controller.setPageNo(controller.pageNo.value + 1)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Widget _pageLimitDropdown() {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Get.bottomSheet(
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: ProductController.pageLimitOptions
                  .map(
                    (limit) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('$limit per page'),
                      onTap: () {
                        controller.setPageLimit(limit);
                        Get.back();
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${controller.pageLimit.value}',
                style: AppTextStyles.bodyStrong),
            const Icon(Icons.arrow_drop_down_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  void _openPriceSheet(BuildContext context, ProductModel product) {
    controller.startPricing(product);
    Get.bottomSheet(
      _ProductPriceSheet(product: product),
      isScrollControlled: true,
    );
  }
}

class _ProductTile extends StatelessWidget {
  final int serial;
  final ProductModel product;
  final VoidCallback onTap;
  final VoidCallback onPrice;
  final VoidCallback onDelete;

  const _ProductTile({
    required this.serial,
    required this.product,
    required this.onTap,
    required this.onPrice,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        // onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: product.needsAttention
                          ? AppColors.emberGradient
                          : AppColors.tealGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('$serial',
                        style: AppTextStyles.bodyStrong
                            .copyWith(color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.name,
                            style: AppTextStyles.bodyStrong,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        Text(product.category, style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                  // IconButton(
                  //   tooltip: 'Prices',
                  //   visualDensity: VisualDensity.compact,
                  //   onPressed: onPrice,
                  //   icon: Icon(Icons.sell_rounded,
                  //       color: AppColors.skyBlue, size: 18),
                  // ),
                  // IconButton(
                  //   tooltip: 'Delete',
                  //   visualDensity: VisualDensity.compact,
                  //   onPressed: onDelete,
                  //   icon: Icon(Icons.delete_outline_rounded,
                  //       color: AppColors.textMuted, size: 18),
                  // ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TablePill(
                    label: 'Stock ${product.stockMaintain ? "ON" : "OFF"}',
                    color: product.stockMaintain
                        ? AppColors.success
                        : AppColors.textMuted,
                  ),
                  TablePill(
                    label: 'Neg. Stock ${product.negativeStock ? "ON" : "OFF"}',
                    color: product.negativeStock
                        ? AppColors.success
                        : AppColors.textMuted,
                  ),
                  if (product.stockMaintain)
                    TablePill(
                      label: '${product.currentStock} ${product.unit}',
                      color: product.currentStock < 0
                          ? AppColors.danger
                          : AppColors.skyBlue,
                    ),
                  if (product.prices.isNotEmpty)
                    TablePill(
                      label: '₹${product.price.toStringAsFixed(0)}',
                      color: AppColors.gold,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductPriceSheet extends GetView<ProductController> {
  final ProductModel product;
  const _ProductPriceSheet({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: Get.height * 0.85),
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Product Price', style: AppTextStyles.h2),
                IconButton(
                  onPressed: Get.back,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Text('${product.name} - ${product.unit}',
                style: AppTextStyles.bodyStrong),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Obx(() => _dropdown(
                        value: controller.newPricelist.value,
                        options: controller.pricelistOptions,
                        onChanged: (v) => controller.newPricelist.value = v,
                      )),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: controller.newPriceCtrl,
                    keyboardType: TextInputType.number,
                    style: AppTextStyles.body
                        .copyWith(color: AppColors.textPrimary),
                    decoration: const InputDecoration(hintText: 'Price'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: controller.addPriceEntry,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.ember,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Obx(() {
              if (controller.priceEntries.isEmpty) {
                return const EmptyState(
                  icon: Icons.sell_outlined,
                  title: 'No prices added',
                  subtitle: 'Add a pricelist and price above.',
                );
              }
              return Column(
                children: List.generate(controller.priceEntries.length, (i) {
                  final entry = controller.priceEntries[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(entry.pricelistName,
                                  style: AppTextStyles.bodyStrong),
                            ),
                            SizedBox(
                              width: 90,
                              child: Text(
                                '₹${entry.price.toStringAsFixed(0)}',
                                textAlign: TextAlign.end,
                                style: AppTextStyles.bodyStrong
                                    .copyWith(color: AppColors.gold),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => controller.removePriceEntry(i),
                              icon: Icon(Icons.delete_outline_rounded,
                                  color: AppColors.danger, size: 18),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Text('Discount', style: AppTextStyles.caption),
                            Switch(
                              value: entry.discountEnabled,
                              onChanged: (_) => controller.toggleDiscount(i),
                              activeColor: AppColors.gold,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              );
            }),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: controller.savePrices,
                child: const Text('Submit'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown({
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          hint: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('Select',
                style: AppTextStyles.body.copyWith(color: AppColors.textMuted)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          dropdownColor: AppColors.surfaceElevated,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.textMuted),
          style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
