import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:ncw_fireworks/core/utils/pdf_downloader.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/session_service.dart';
import '../../data/models/billing_item_model.dart';
import '../../data/models/party_model.dart';
import '../../data/models/quotation/id_name.dart';
import '../../data/models/quotation/quotation_product_list_response_model.dart';
import '../../data/models/quotation_model.dart';
import '../../data/respositories/quotation_repository.dart';
import '../../routes/app_routes.dart';
import '../estimation/estimation_controller.dart';

/// The 3 tabs shown above the Quotation list on the web app.
///
/// Each tab maps to `quotation.php`'s `drafted`/`cancelled` filters on
/// `quotation_listing`: Active is `drafted=0, cancelled=0`, Draft is
/// `drafted=1, cancelled=0`, Cancel is `drafted=0, cancelled=1`.
enum QuotationTab { active, draft, cancel }

extension QuotationTabX on QuotationTab {
  String get label {
    switch (this) {
      case QuotationTab.active:
        return 'Active';
      case QuotationTab.draft:
        return 'Draft';
      case QuotationTab.cancel:
        return 'Cancel';
    }
  }
}

class QuotationController extends GetxController {
  QuotationController({
    QuotationRepository? quotationRepository,
    SessionService? sessionService,
  })  : _quotationRepository = quotationRepository ?? QuotationRepository(),
        _sessionService = sessionService ?? Get.find<SessionService>();

  final QuotationRepository _quotationRepository;
  final SessionService _sessionService;

  static final DateFormat _apiDateFormat = DateFormat('dd-MM-yyyy');
  static final DateFormat _serverStoredDateFormat = DateFormat('yyyy-MM-dd');

  // ---- Shared dropdown data (populated by loadQuotations + the form's
  // init call — both come from the same endpoint's `head`, so either one
  // keeps these current). --------------------------------------------------
  final pricelistOptions = <IdName>[].obs;
  final parties = <PartyModel>[].obs;
  final productOptions = <QuotationProductOption>[].obs;
  final isLoadingProducts = false.obs;

  List<String> get pricelistNames =>
      pricelistOptions.map((e) => e.name).toList();

  // ---- List screen state -------------------------------------------------
  final quotations = <QuotationModel>[].obs;
  final searchQuery = ''.obs;
  final activeTab = QuotationTab.active.obs;
  final isTableView = false.obs;
  final Rx<DateTime?> filterFrom = Rx<DateTime?>(null);
  final Rx<DateTime?> filterTo = Rx<DateTime?>(null);
  final Rx<String?> filterParty = Rx<String?>(null); // party *name*
  final pageSize = 10.obs;
  final currentPage = 1.obs;
  final isLoadingList = false.obs;

  /// The API doesn't return a total row/page count for `quotation_listing`
  /// — inferred the same way `EstimationController` does: trust a full
  /// page means there's probably another one, and self-correct once the
  /// user reaches the real last page.
  final totalPagesRx = 1.obs;
  int get totalPages => totalPagesRx.value;

  Timer? _searchDebounce;

  // ---- Form state ---------------------------------------------------------
  QuotationModel? editingQuotation;
  final Rx<PartyModel?> selectedParty = Rx<PartyModel?>(null);
  final Rx<String?> selectedPricelist = Rx<String?>(null); // pricelist *name*
  final Rx<String?> selectedPricelistId = Rx<String?>(null);
  final Rx<DateTime> quotationDate = Rx<DateTime>(DateTime.now());
  final formItems = <BillingItemModel>[].obs;
  final section1Add = 0.0.obs;
  final section1Discount = 0.0.obs;
  final section2Add = 0.0.obs;
  final section2Discount = 0.0.obs;
  final roundOff = 0.0.obs;
  final isLoadingForm = false.obs;
  final isSaving = false.obs;

  // Persistent controllers so typing doesn't lose focus/cursor position
  // when the totals card rebuilds on every keystroke.
  final section1AddCtrl = TextEditingController();
  final section1DiscountCtrl = TextEditingController();
  final section2AddCtrl = TextEditingController();
  final section2DiscountCtrl = TextEditingController();
  final roundOffCtrl = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    loadQuotations();
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    section1AddCtrl.dispose();
    section1DiscountCtrl.dispose();
    section2AddCtrl.dispose();
    section2DiscountCtrl.dispose();
    roundOffCtrl.dispose();
    super.onClose();
  }

  /// Pushes the current rx money values into their text controllers.
  /// Called only when the form is reset/loaded — never on every keystroke —
  /// so typing doesn't fight the controller or lose cursor position.
  void _syncMoneyControllers() {
    String fmt(double v) => v == 0 ? '' : v.toStringAsFixed(2);
    section1AddCtrl.text = fmt(section1Add.value);
    section1DiscountCtrl.text = fmt(section1Discount.value);
    section2AddCtrl.text = fmt(section2Add.value);
    section2DiscountCtrl.text = fmt(section2Discount.value);
    roundOffCtrl.text = fmt(roundOff.value);
  }

  // ---- List loading / filtering / pagination ------------------------------

  String? _partyIdForName(String? name) {
    if (name == null) return null;
    return parties.firstWhereOrNull((p) => p.name == name)?.serverPartyId;
  }

  Future<void> loadQuotations() async {
    isLoadingList.value = true;
    try {
      final result = await _quotationRepository.listQuotations(
        filterFromDate: filterFrom.value != null
            ? _apiDateFormat.format(filterFrom.value!)
            : '',
        filterToDate: filterTo.value != null
            ? _apiDateFormat.format(filterTo.value!)
            : '',
        searchText: searchQuery.value.trim(),
        filterPartyId: _partyIdForName(filterParty.value) ?? '',
        pageNumber: currentPage.value,
        pageLimit: pageSize.value,
        drafted: activeTab.value == QuotationTab.draft ? '1' : '0',
        cancelled: activeTab.value == QuotationTab.cancel ? '1' : '0',
      );

      final rowStatus = switch (activeTab.value) {
        QuotationTab.active => DocStatus.active,
        QuotationTab.draft => DocStatus.draft,
        QuotationTab.cancel => DocStatus.cancelled,
      };

      if (result.partyList.isNotEmpty) {
        parties.assignAll(result.partyList.map((p) => PartyModel(
              id: p.id,
              serverPartyId: p.id,
              name: p.name.isEmpty ? 'Untitled Party' : p.name,
              hasFullDetails: false,
            )));
      }

      quotations.assignAll(result.items.map((item) {
        DateTime date;
        try {
          date = _serverStoredDateFormat.parse(item.quotationDate);
        } catch (_) {
          date = DateTime.now();
        }
        final party = item.partyNameMobileCity.trim();
        return QuotationModel(
          id: item.quotationId,
          quotationNo: item.quotationNumber,
          serverQuotationId: item.quotationId,
          partyId: '',
          partyName: party.isEmpty ? 'Direct' : party,
          date: date,
          items: const [],
          status: rowStatus,
          serverGrandTotal: item.grandTotal,
          serverQtyLabel: item.totalQuantity,
          estimateId: item.estimateId,
        );
      }));

      // No total-row/page count comes back from this endpoint — infer
      // from whether this page was full, same heuristic as PartyController.
      totalPagesRx.value = result.items.length < pageSize.value
          ? currentPage.value
          : currentPage.value + 1;
    } on ApiRequestException catch (e) {
      final looksLikeEmptyResult = e.message.toLowerCase().contains('no') &&
          (e.message.toLowerCase().contains('record') ||
              e.message.toLowerCase().contains('quotation') ||
              e.message.toLowerCase().contains('data'));
      quotations.clear();
      totalPagesRx.value = 1;
      if (!looksLikeEmptyResult) {
        Get.snackbar('Could not load quotations', e.message,
            snackPosition: SnackPosition.BOTTOM);
      }
    } on ApiException catch (e) {
      quotations.clear();
      totalPagesRx.value = 1;
      Get.snackbar('Could not load quotations', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoadingList.value = false;
    }
  }

  /// The current page's rows, as returned by the server — the list view
  /// still calls this `pagedFiltered` to match its existing layout code.
  List<QuotationModel> get pagedFiltered => quotations;

  void setSearch(String value) {
    searchQuery.value = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      currentPage.value = 1;
      loadQuotations();
    });
  }

  void setTab(QuotationTab tab) {
    activeTab.value = tab;
    currentPage.value = 1;
    loadQuotations();
  }

  void setDateFrom(DateTime? date) {
    filterFrom.value = date;
    currentPage.value = 1;
    loadQuotations();
  }

  void setDateTo(DateTime? date) {
    filterTo.value = date;
    currentPage.value = 1;
    loadQuotations();
  }

  void setPartyFilter(String? party) {
    filterParty.value = party;
    currentPage.value = 1;
    loadQuotations();
  }

  void setPageSize(int size) {
    pageSize.value = size;
    currentPage.value = 1;
    loadQuotations();
  }

  void setPageNo(int page) {
    currentPage.value = page;
    loadQuotations();
  }

  void goToPage(int page) => setPageNo(page.clamp(1, totalPages));

  void toggleViewMode(bool table) => isTableView.value = table;

  /// Cancels an active quotation (server sets `cancelled = 1`) or, for a
  /// draft row, permanently deletes it (server sets `deleted = 1`) — the
  /// same `delete_quotation_id` call does either, decided server-side by
  /// the quotation's own `drafted` flag.
  Future<void> deleteQuotation(QuotationModel quotation) async {
    final id = quotation.serverQuotationId ?? quotation.id;
    if (id.isEmpty) {
      quotations.remove(quotation);
      return;
    }
    final isDraft = quotation.status == DocStatus.draft;
    try {
      final result =
          await _quotationRepository.deleteQuotation(quotationId: id);
      Get.snackbar(
        isDraft ? 'Draft deleted' : 'Quotation cancelled',
        result.message,
        snackPosition: SnackPosition.BOTTOM,
      );
      await loadQuotations();
    } on ApiRequestException catch (e) {
      Get.snackbar('Could not delete', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } on ApiException catch (e) {
      Get.snackbar('Could not delete', e.message,
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  // ---- Print / download report PDF ----------------------------------------

  /// Opens the A4 quotation report PDF in the device's browser/PDF viewer.
  /// Print and download both point at the same report — the viewer's own
  /// print/save controls handle each action from there.
  Future<void> _openQuotationReport(QuotationModel quotation) async {
    final id = quotation.serverQuotationId ?? quotation.id;
    if (id.isEmpty) {
      Get.snackbar('Not available', 'This quotation has no report yet',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final uri = ApiEndpoints.quotationReport(id);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      Get.snackbar('Could not open', 'Unable to open the quotation report',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> printQuotation(QuotationModel quotation) =>
      _openQuotationReport(quotation);

  Future<void> downloadQuotation(QuotationModel quotation) async {
  final id = quotation.serverQuotationId ?? quotation.id;
  if (id.isEmpty) {
    Get.snackbar('Not available', 'This quotation has no report yet',
        snackPosition: SnackPosition.BOTTOM);
    return;
  }
  try {
    await PdfDownloader.download(
      uri: ApiEndpoints.quotationReport(id),
      fileName: quotation.quotationNo,
    );
    Get.snackbar('Downloaded', 'Quotation report saved',
        snackPosition: SnackPosition.BOTTOM);
  } catch (e) {
    Get.snackbar('Could not download', 'Unable to download the quotation report',
        snackPosition: SnackPosition.BOTTOM);
  }
}

  // ---- Convert to Estimate --------------------------------------------------

  /// Opens the Add Estimate form pre-filled from [quotation]'s own party/
  /// pricelist/products — the Convert action on an active, not-yet-
  /// converted quotation row. Saving that form links the new estimate
  /// back to this quotation, which then hides its Convert/Edit/Delete
  /// actions once the list reloads.
  void convertToEstimate(QuotationModel quotation) {
    final id = quotation.serverQuotationId ?? quotation.id;
    if (id.isEmpty) return;
    // EstimationController is normally registered lazily the first time
    // the Estimate module's own binding runs — put it directly here too,
    // in case Convert is tapped before the user ever opens Estimate.
    final estimationController = Get.isRegistered<EstimationController>()
        ? Get.find<EstimationController>()
        : Get.put(EstimationController());
    estimationController.startConvertFromQuotation(id);
    Get.toNamed(AppRoutes.estimationForm);
  }

  // ---- Form: totals ---------------------------------------------------------

  double get formSection1Total => formItems
      .where((i) => i.section == 1)
      .fold(0.0, (sum, i) => sum + i.amount);
  double get formSection2Total => formItems
      .where((i) => i.section == 2)
      .fold(0.0, (sum, i) => sum + i.amount);
  double get formSubTotal => formSection1Total + formSection2Total;
  double get formAdjustments =>
      (section1Add.value - section1Discount.value) +
      (section2Add.value - section2Discount.value);
  double get formTotal => formSubTotal + formAdjustments + roundOff.value;

  // ---- Form: pricelist selection ------------------------------------------

  void selectPricelist(IdName pricelist) {
    if (selectedPricelistId.value == pricelist.id) return;
    selectedPricelistId.value = pricelist.id;
    selectedPricelist.value = pricelist.name;
    loadProductsForSelectedPricelist();
  }

  Future<void> loadProductsForSelectedPricelist() async {
    final pricelistId = selectedPricelistId.value;
    if (pricelistId == null || pricelistId.isEmpty) {
      productOptions.clear();
      return;
    }
    isLoadingProducts.value = true;
    try {
      final result =
          await _quotationRepository.getProductsForPricelist(pricelistId);
      productOptions.assignAll(result.products);
    } on ApiException catch (e) {
      productOptions.clear();
      Get.snackbar('Could not load products', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoadingProducts.value = false;
    }
  }

  // ---- Form: create / edit bootstrap ------------------------------------

  void _resetFormFields() {
    selectedParty.value = null;
    selectedPricelist.value = null;
    selectedPricelistId.value = null;
    quotationDate.value = DateTime.now();
    formItems.clear();
    section1Add.value = 0;
    section1Discount.value = 0;
    section2Add.value = 0;
    section2Discount.value = 0;
    roundOff.value = 0;
    productOptions.clear();
    _syncMoneyControllers();
  }

  void startCreate() {
    editingQuotation = null;
    _resetFormFields();
    isLoadingForm.value = true;
    _loadFormInit(showQuotationId: '');
  }

  void startEdit(QuotationModel quotation) {
    editingQuotation = quotation;
    _resetFormFields();
    quotationDate.value = quotation.date;
    isLoadingForm.value = true;
    _loadFormInit(
        showQuotationId: quotation.serverQuotationId ?? quotation.id);
  }

  DateTime? _tryParseServerDate(String raw) {
    if (raw.isEmpty) return null;
    try {
      return _apiDateFormat.parseStrict(raw);
    } catch (_) {
      return null;
    }
  }

  /// Bootstraps the Add/Edit Quotation form via `show_quotation_id`:
  /// dropdown data always, plus the existing quotation's own fields when
  /// [showQuotationId] resolves to a real record.
  Future<void> _loadFormInit({required String showQuotationId}) async {
    try {
      final result = await _quotationRepository.getFormInitData(
          showQuotationId: showQuotationId);

      pricelistOptions.assignAll(result.pricelist);
      parties.assignAll(result.partyList.map((p) => PartyModel(
            id: p.id,
            serverPartyId: p.id,
            name: p.name.isEmpty ? 'Untitled Party' : p.name,
            hasFullDetails: false,
          )));

      final detail = result.detail;
      if (detail != null) {
        if (detail.pricelistId.isNotEmpty) {
          final pl = pricelistOptions
              .firstWhereOrNull((p) => p.id == detail.pricelistId);
          selectedPricelistId.value = detail.pricelistId;
          selectedPricelist.value = pl?.name;
        }
        if (detail.partyId.isNotEmpty) {
          selectedParty.value = parties
              .firstWhereOrNull((p) => p.serverPartyId == detail.partyId);
        }
        final parsedDate = _tryParseServerDate(detail.quotationDate);
        if (parsedDate != null) quotationDate.value = parsedDate;

        formItems.assignAll(detail.products.map((row) {
          final section = row.productDiscount == '1' ? 1 : 2;
          return BillingItemModel(
            productId: row.productId,
            productName: row.productName,
            quantity: int.tryParse(row.quantity) ?? 1,
            rate: double.tryParse(row.rate) ?? 0,
            unit: row.unitName,
            unitId: row.unitId,
            section: section,
          );
        }));

        section1Add.value = double.tryParse(detail.section1AddValue) ?? 0;
        section1Discount.value =
            double.tryParse(detail.section1Discount) ?? 0;
        section2Add.value = double.tryParse(detail.section2AddValue) ?? 0;
        section2Discount.value =
            double.tryParse(detail.section2Discount) ?? 0;
      } else if (pricelistOptions.isNotEmpty) {
        // New quotation — default to the first pricelist, matching the
        // web app's Add Quotation screen.
        selectedPricelistId.value = pricelistOptions.first.id;
        selectedPricelist.value = pricelistOptions.first.name;
      }

      _syncMoneyControllers();

      if (selectedPricelistId.value != null &&
          selectedPricelistId.value!.isNotEmpty) {
        await loadProductsForSelectedPricelist();
      }
    } on ApiRequestException catch (e) {
      Get.snackbar('Could not load quotation', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } on ApiException catch (e) {
      Get.snackbar('Could not load quotation', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoadingForm.value = false;
    }
  }

  // ---- Form: line items ---------------------------------------------------

  /// Adds [productId] to the form. Looks up its rate/unit/section for the
  /// currently selected pricelist via `selected_product_id` —
  /// `product_pricelist_id` (used to list products) only returns id+name.
  Future<void> addProductById({
    required String productId,
    required String productName,
    int qty = 1,
  }) async {
    final pricelistId = selectedPricelistId.value;
    if (pricelistId == null || pricelistId.isEmpty) {
      Get.snackbar('Select a pricelist',
          'Choose a pricelist before adding products',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    try {
      final detail = await _quotationRepository.getSelectedProductDetail(
        productId: productId,
        pricelistId: pricelistId,
      );

      // Matches the server's own rule for which totals section a line
      // lands in once saved (see quotation.php's `product_discount` check).
      final section = detail.productDiscount ? 1 : 2;

      final existingIndex = formItems.indexWhere(
          (i) => i.productId == productId && i.section == section);
      if (existingIndex >= 0) {
        formItems[existingIndex].quantity += qty;
        formItems.refresh();
      } else {
        formItems.add(BillingItemModel(
          productId: productId,
          productName: productName,
          quantity: qty,
          rate: detail.rate,
          unit: detail.unitName.isEmpty ? 'Pcs' : detail.unitName,
          unitId: detail.unitId,
          section: section,
        ));
      }
    } on ApiRequestException catch (e) {
      Get.snackbar('Could not add product', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } on ApiException catch (e) {
      Get.snackbar('Could not add product', e.message,
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  void updateQuantity(int index, int qty) {
    if (qty < 1) return;
    formItems[index].quantity = qty;
    formItems.refresh();
  }

  /// Adds/updates many products at once from the full-screen product
  /// picker. Unlike [addProductById], this never calls the network —
  /// `product_pricelist_id` (already loaded into [productOptions]) returns
  /// rate/unit/discount-flag for every product, so a multi-select "Add to
  /// Quotation" can apply all of them in one shot.
  ///
  /// [selections] maps `productId` -> desired quantity. A quantity of 0
  /// or a product missing from [productOptions] is skipped.
  void addProductsFromPicker(Map<String, int> selections) {
    for (final entry in selections.entries) {
      final qty = entry.value;
      if (qty <= 0) continue;
      final option =
          productOptions.firstWhereOrNull((p) => p.productId == entry.key);
      if (option == null) continue;

      final section = option.productDiscount ? 1 : 2;

      final existingIndex = formItems.indexWhere(
          (i) => i.productId == option.productId && i.section == section);
      if (existingIndex >= 0) {
        formItems[existingIndex].quantity = qty;
      } else {
        formItems.add(BillingItemModel(
          productId: option.productId,
          productName: option.productName,
          quantity: qty,
          rate: option.rate,
          unit: option.unitName.isEmpty ? 'Pcs' : option.unitName,
          unitId: option.unitId,
          section: section,
        ));
      }
    }
    formItems.refresh();
  }

  /// Current quantity already on the form for [productId] (any section) —
  /// used to pre-fill the stepper when the product picker is reopened.
  int quantityInFormFor(String productId) {
    final match = formItems.firstWhereOrNull((i) => i.productId == productId);
    return match?.quantity ?? 0;
  }

  void updateRate(int index, double rate) {
    if (rate < 0) return;
    formItems[index].rate = rate;
    formItems.refresh();
  }

  void moveToSection(int index, int section) {
    formItems[index].section = section;
    formItems.refresh();
  }

  void removeItem(int index) {
    formItems.removeAt(index);
  }

  void clearForm() {
    formItems.clear();
    selectedParty.value = null;
    section1Add.value = 0;
    section1Discount.value = 0;
    section2Add.value = 0;
    section2Discount.value = 0;
    roundOff.value = 0;
    _syncMoneyControllers();
  }

  // ---- Form: save -----------------------------------------------------------

  Future<bool> save({required bool asDraft}) async {
    if (isSaving.value) return false;

    // The server relaxes its own validation for drafts (empty party/
    // pricelist/items are fine) — only require them for a real submit.
    if (!asDraft) {
      if (selectedParty.value == null) {
        Get.snackbar('Missing party', 'Please select a party',
            snackPosition: SnackPosition.BOTTOM);
        return false;
      }
      if (selectedPricelistId.value == null ||
          selectedPricelistId.value!.isEmpty) {
        Get.snackbar('Missing pricelist', 'Please select a pricelist',
            snackPosition: SnackPosition.BOTTOM);
        return false;
      }
      if (formItems.isEmpty) {
        Get.snackbar('No items', 'Add at least one product',
            snackPosition: SnackPosition.BOTTOM);
        return false;
      }
    }

    final session = _sessionService.currentSession.value;
    if (session == null) {
      Get.snackbar('Session expired', 'Please log in again',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }

    isSaving.value = true;
    try {
      final result = await _quotationRepository.saveQuotation(
        creator: session.userId,
        editId: editingQuotation?.serverQuotationId ?? '',
        drafted: asDraft ? '1' : '0',
        quotationDate: _apiDateFormat.format(quotationDate.value),
        pricelistId: selectedPricelistId.value ?? '',
        partyId: selectedParty.value?.serverPartyId ??
            selectedParty.value?.id ??
            '',
        products: formItems
            .map((i) => QuotationProductLine(
                  productId: i.productId,
                  quantity: i.quantity.toString(),
                  rate: i.rate.toString(),
                ))
            .toList(),
        section1AddValue:
            section1Add.value == 0 ? '' : section1Add.value.toString(),
        section1Discount: section1Discount.value == 0
            ? ''
            : section1Discount.value.toString(),
        section2AddValue:
            section2Add.value == 0 ? '' : section2Add.value.toString(),
        section2Discount: section2Discount.value == 0
            ? ''
            : section2Discount.value.toString(),
      );

      final wasCreate = editingQuotation == null;
      Get.back();
      Get.snackbar('Saved', result.message,
          snackPosition: SnackPosition.BOTTOM);
      if (wasCreate) currentPage.value = 1;
      activeTab.value = asDraft ? QuotationTab.draft : QuotationTab.active;
      await loadQuotations();
      return true;
    } on ApiRequestException catch (e) {
      Get.snackbar('Could not save', e.message,
          snackPosition: SnackPosition.BOTTOM);
      return false;
    } on ApiException catch (e) {
      Get.snackbar('Could not save', e.message,
          snackPosition: SnackPosition.BOTTOM);
      return false;
    } finally {
      isSaving.value = false;
    }
  }
}