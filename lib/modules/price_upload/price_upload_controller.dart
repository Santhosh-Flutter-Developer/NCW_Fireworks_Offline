import 'package:get/get.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/excel_exporter.dart';
import '../../data/models/product_price_list_model.dart';
import '../../data/respositories/product_price_repository.dart';

class PriceUploadController extends GetxController {
  PriceUploadController({ProductPriceRepository? repository})
      : _repository = repository ?? ProductPriceRepository();

  final ProductPriceRepository _repository;

  static const List<int> pageSizeOptions = [10, 25, 50, 100];

  // ---- List screen state ---------------------------------------------------
  final rows = <ProductPriceRow>[].obs;
  final pricelistOptions = <PricelistOption>[].obs;
  final productOptions = <ProductOption>[].obs;

  final RxnString filterPricelistId = RxnString();
  final RxnString filterProductId = RxnString();
  final isTableView = true.obs;
  final pageLimit = 10.obs;
  final pageNumber = 1.obs;

  // Pagination total. Preferably the exact count of cached (synced) rows
  // matching the current filters (see
  // ProductPriceRepository._cachedTotalCount) — stays fixed while paging
  // instead of growing by one every time Next is tapped. Only falls back
  // to inferring from "was this page full" when nothing's been synced
  // yet to count against.
  final totalPagesRx = 1.obs;
  int get totalPages => totalPagesRx.value;

  final isLoading = false.obs;
  final RxnString errorText = RxnString();
  final isExporting = false.obs;

  /// Bumped on every `fetchPriceList()` call; a response is only applied
  /// if it's still the most recent request when it comes back. Without
  /// this, rapid page/filter taps can fire overlapping requests whose
  /// responses arrive out of order and clobber the current page with
  /// stale data.
  int _requestId = 0;

  /// Large enough to pull every row matching the current filters in one
  /// call — export should cover the whole filtered list, not just the
  /// current page.
  static const int _exportPageLimit = 100000;

  @override
  void onInit() {
    super.onInit();
    fetchPriceList();
  }

  /// The API paginates but doesn't return a total row count, so "is there
  /// a next page" is inferred from whether this page came back full —
  /// same heuristic as [totalPagesRx] below.
  bool get hasNextPage => pageNumber.value < totalPages;

  bool get hasPrevPage => pageNumber.value > 1;

  Future<void> fetchPriceList() async {
    final requestId = ++_requestId;
    isLoading.value = true;
    errorText.value = null;
    try {
      final result = await _repository.fetchPriceList(
        pricelistId: filterPricelistId.value ?? '',
        productId: filterProductId.value ?? '',
        pageNumber: pageNumber.value,
        pageLimit: pageLimit.value,
      );
      if (requestId != _requestId) return; // A newer request has since started.
      rows.assignAll(result.rows);
      // The master dropdown lists come back on every call — only refresh
      // them when populated, so a filtered/edge-case response can't wipe
      // out dropdown options the person is actively using.
      if (result.pricelists.isNotEmpty) {
        pricelistOptions.assignAll(result.pricelists);
      }
      if (result.products.isNotEmpty) {
        productOptions.assignAll(result.products);
      }

      // Prefer the known total row count derived from the last sync (see
      // ProductPriceRepository._cachedTotalCount) — this stays fixed
      // while paging instead of growing by one every time Next is
      // tapped. Only falls back to inferring from "was this page full"
      // when nothing's been synced yet to count against.
      final totalRecords = result.totalRecords;
      totalPagesRx.value = totalRecords != null
          ? (totalRecords <= 0
              ? 1
              : (totalRecords / pageLimit.value).ceil())
          : (result.rows.length < pageLimit.value
              ? pageNumber.value
              : pageNumber.value + 1);
    } on ApiException catch (e) {
      if (requestId != _requestId) return;
      errorText.value = e.message;
      rows.clear();
      totalPagesRx.value = 1;
    } catch (_) {
      if (requestId != _requestId) return;
      errorText.value = 'Something went wrong. Please try again.';
      rows.clear();
      totalPagesRx.value = 1;
    } finally {
      if (requestId == _requestId) isLoading.value = false;
    }
  }

  void setFilterPricelist(String? pricelistId) {
    filterPricelistId.value = pricelistId;
    pageNumber.value = 1;
    fetchPriceList();
  }

  void setFilterProduct(String? productId) {
    filterProductId.value = productId;
    pageNumber.value = 1;
    fetchPriceList();
  }

  void setPageLimit(int limit) {
    pageLimit.value = limit;
    pageNumber.value = 1;
    fetchPriceList();
  }

  /// Jumps to [page], clamped to the known valid range — mirrors
  /// `PartyController`/`QuotationController`/`EstimationController`'s
  /// `goToPage`. Ignored while a fetch is already in flight so rapid
  /// taps can't fire overlapping requests that land out of order.
  void goToPage(int page) {
    if (isLoading.value) return;
    final target = page.clamp(1, totalPages);
    if (target == pageNumber.value) return;
    pageNumber.value = target;
    fetchPriceList();
  }

  void nextPage() {
    if (!hasNextPage || isLoading.value) return;
    goToPage(pageNumber.value + 1);
  }

  void prevPage() {
    if (!hasPrevPage || isLoading.value) return;
    goToPage(pageNumber.value - 1);
  }

  void firstPage() {
    if (pageNumber.value == 1 || isLoading.value) return;
    goToPage(1);
  }

  void toggleViewMode(bool table) => isTableView.value = table;

  void retry() => fetchPriceList();

  /// Exports S.No, Product Name and Price for every row matching the
  /// current Pricelist/Product filters (not just the current page) to
  /// an .xlsx file, then hands it to the platform to save/download.
  /// Works on Web, Android, iOS, Windows, macOS and Linux.
  Future<void> exportToExcel() async {
    if (isExporting.value) return;
    isExporting.value = true;
    try {
      final result = await _repository.fetchPriceList(
        pricelistId: filterPricelistId.value ?? '',
        productId: filterProductId.value ?? '',
        pageNumber: 1,
        pageLimit: _exportPageLimit,
      );

      if (result.rows.isEmpty) {
        Get.snackbar('Nothing to export', 'There are no prices to export.',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }

      await ExcelExporter.export(
        fileName:
            'product_price_${DateTime.now().millisecondsSinceEpoch}',
        headers: const ['S.No', 'Product Name', 'Price'],
        rows: result.rows
            .map((row) => [row.sno, row.productName, row.price])
            .toList(),
      );

      Get.snackbar('Exported', 'Product price list exported successfully.',
          snackPosition: SnackPosition.BOTTOM);
    } on ApiException catch (e) {
      Get.snackbar('Export failed', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } catch (_) {
      Get.snackbar(
          'Export failed', 'Could not export the price list. Try again.',
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isExporting.value = false;
    }
  }

  /// Delete/Upload aren't backed by an API yet — surface that clearly
  /// instead of pretending to mutate server data that a refresh would
  /// just bring back.
  void deleteRow(ProductPriceRow row) {
    Get.snackbar(
      'Not available yet',
      'Deleting a price needs its own API endpoint from the backend team.',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  void submitUpload({
    required String? pricelistId,
    required String? productId,
    required double? price,
  }) {
    if (pricelistId == null) {
      Get.snackbar('Missing pricelist', 'Please select a pricelist',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (productId == null) {
      Get.snackbar('Missing product', 'Please select a product',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (price == null || price <= 0) {
      Get.snackbar('Invalid price', 'Enter a price greater than 0',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    Get.back();
    Get.snackbar(
      'Not available yet',
      'Uploading a price needs its own API endpoint from the backend team.',
      snackPosition: SnackPosition.BOTTOM,
    );
  }
}
