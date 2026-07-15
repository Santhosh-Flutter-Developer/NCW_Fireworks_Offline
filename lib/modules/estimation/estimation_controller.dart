import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/session_service.dart';
import '../../data/models/billing_item_model.dart';
import '../../data/models/estimate/estimate_product_list_response_model.dart';
import '../../data/models/estimate/id_name.dart';
import '../../data/models/estimation_model.dart';
import '../../data/models/party_model.dart';
import '../../data/respositories/estimate_repository.dart';
import '../quotation/quotation_controller.dart';

/// The 3 tabs shown above the Estimate list on the web app.
///
/// Each tab maps to `estimate.php`'s `drafted`/`cancelled` filters on
/// `estimate_listing`: Active is `drafted=0, cancelled=0`, Draft is
/// `drafted=1, cancelled=0`, Cancel is `drafted=0, cancelled=1`.
enum EstimationTab { active, draft, cancel }

extension EstimationTabX on EstimationTab {
  String get label {
    switch (this) {
      case EstimationTab.active:
        return 'Active';
      case EstimationTab.draft:
        return 'Draft';
      case EstimationTab.cancel:
        return 'Cancel';
    }
  }
}

class EstimationController extends GetxController {
  EstimationController({
    EstimateRepository? estimateRepository,
    SessionService? sessionService,
  })  : _estimateRepository = estimateRepository ?? EstimateRepository(),
        _sessionService = sessionService ?? Get.find<SessionService>();

  final EstimateRepository _estimateRepository;
  final SessionService _sessionService;

  static final DateFormat _apiDateFormat = DateFormat('dd-MM-yyyy');
  static final DateFormat _serverStoredDateFormat = DateFormat('yyyy-MM-dd');

  // ---- Shared dropdown data (populated by loadEstimates + the form's
  // init call — both come from the same endpoint's `head`, so either one
  // keeps these current). --------------------------------------------------
  final pricelistOptions = <IdName>[].obs;
  final agentOptions = <IdName>[].obs;
  final parties = <PartyModel>[].obs;
  final otherChargesOptions = <IdName>[].obs;
  final productOptions = <EstimateProductOption>[].obs;
  final isLoadingProducts = false.obs;

  List<String> get pricelistNames => pricelistOptions.map((e) => e.name).toList();
  List<String> get agents => agentOptions.map((e) => e.name).toList();

  /// Stock as of the last time each product was looked up via
  /// `selected_product_id`. `product_pricelist_id` (used to list
  /// products) doesn't return stock, so this is only known once a
  /// product's rate/unit has actually been fetched.
  final _stockCache = <String, int>{};
  int stockFor(String productId) => _stockCache[productId] ?? 0;

  // ---- List screen state -------------------------------------------------
  final estimations = <EstimationModel>[].obs;
  final searchQuery = ''.obs;
  final activeTab = EstimationTab.active.obs;
  final isTableView = false.obs;
  final Rx<DateTime?> filterFrom = Rx<DateTime?>(null);
  final Rx<DateTime?> filterTo = Rx<DateTime?>(null);
  final Rx<String?> filterAgent = Rx<String?>(null); // agent *name*
  final Rx<String?> filterParty = Rx<String?>(null); // party *name*
  final pageSize = 10.obs;
  final currentPage = 1.obs;
  final isLoadingList = false.obs;

  /// The API doesn't return a total row/page count for `estimate_listing`
  /// — inferred the same way `PartyController` does: trust a full page
  /// means there's probably another one, and self-correct once the user
  /// reaches the real last page.
  final totalPagesRx = 1.obs;
  int get totalPages => totalPagesRx.value;

  Timer? _searchDebounce;

  // ---- Form state ---------------------------------------------------------
  EstimationModel? editingEstimation;

  /// Set while the Add Estimate form is bootstrapped from an active
  /// quotation (see [startConvertFromQuotation]). Sent back to the server
  /// as `convert_quotation_id` on save, so the new estimate is linked to
  /// its source quotation — which in turn hides that quotation's Convert/
  /// Edit/Delete actions once the list reloads.
  String? _convertQuotationId;
  bool get isConvertingFromQuotation =>
      _convertQuotationId != null && _convertQuotationId!.isNotEmpty;
  final Rx<PartyModel?> selectedParty = Rx<PartyModel?>(null);
  final Rx<String?> selectedAgent = Rx<String?>(null); // agent *name*
  final Rx<String?> selectedAgentId = Rx<String?>(null);
  final Rx<String?> selectedPricelist = Rx<String?>(null); // pricelist *name*
  final Rx<String?> selectedPricelistId = Rx<String?>(null);
  final Rx<DateTime> estimationDate = Rx<DateTime>(DateTime.now());
  final formItems = <BillingItemModel>[].obs;
  final section1Add = 0.0.obs;
  final section1Discount = 0.0.obs;
  final section2Add = 0.0.obs;
  final section2Discount = 0.0.obs;
  final charges = <ChargeLine>[].obs;
  final Rx<String?> selectedChargeId = Rx<String?>(null);
  final roundOff = 0.0.obs;
  final isLoadingForm = false.obs;
  final isSaving = false.obs;

  // Persistent controllers so typing doesn't lose focus/cursor position
  // when the totals card rebuilds on every keystroke.
  final section1AddCtrl = TextEditingController();
  final section1DiscountCtrl = TextEditingController();
  final section2AddCtrl = TextEditingController();
  final section2DiscountCtrl = TextEditingController();
  final chargeValueCtrl = TextEditingController();
  final roundOffCtrl = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    loadEstimates();
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    section1AddCtrl.dispose();
    section1DiscountCtrl.dispose();
    section2AddCtrl.dispose();
    section2DiscountCtrl.dispose();
    chargeValueCtrl.dispose();
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

  String? _agentIdForName(String? name) {
    if (name == null) return null;
    return agentOptions.firstWhereOrNull((a) => a.name == name)?.id;
  }

  String? _partyIdForName(String? name) {
    if (name == null) return null;
    return parties.firstWhereOrNull((p) => p.name == name)?.serverPartyId;
  }

  /// Strips the odd bit of HTML the server sends for a `Direct` agent
  /// (`<span class="text-primary">Direct</span>`) down to plain text.
  String _stripHtml(String raw) => raw.replaceAll(RegExp(r'<[^>]*>'), '');

  Future<void> loadEstimates() async {
    isLoadingList.value = true;
    try {
      final result = await _estimateRepository.listEstimates(
        filterFromDate: filterFrom.value != null
            ? _apiDateFormat.format(filterFrom.value!)
            : '',
        filterToDate: filterTo.value != null
            ? _apiDateFormat.format(filterTo.value!)
            : '',
        searchText: searchQuery.value.trim(),
        filterAgentId: _agentIdForName(filterAgent.value) ?? '',
        filterPartyId: _partyIdForName(filterParty.value) ?? '',
        pageNumber: currentPage.value,
        pageLimit: pageSize.value,
        drafted: activeTab.value == EstimationTab.draft ? '1' : '0',
        cancelled: activeTab.value == EstimationTab.cancel ? '1' : '0',
      );

      final rowStatus = switch (activeTab.value) {
        EstimationTab.active => DocStatus.active,
        EstimationTab.draft => DocStatus.draft,
        EstimationTab.cancel => DocStatus.cancelled,
      };

      if (result.agentList.isNotEmpty) {
        agentOptions.assignAll(result.agentList);
      }
      if (result.partyList.isNotEmpty) {
        parties.assignAll(result.partyList.map((p) => PartyModel(
              id: p.id,
              serverPartyId: p.id,
              name: p.name.isEmpty ? 'Untitled Party' : p.name,
              hasFullDetails: false,
            )));
      }

      estimations.assignAll(result.items.map((item) {
        DateTime date;
        try {
          date = _serverStoredDateFormat.parse(item.estimateDate);
        } catch (_) {
          date = DateTime.now();
        }
        final party = _stripHtml(item.partyNameMobileCity).trim();
        final agent = _stripHtml(item.agentNameMobileCity).trim();
        return EstimationModel(
          id: item.estimateId,
          estimationNo: item.estimateNumber,
          serverEstimateId: item.estimateId,
          partyId: '',
          partyName: party.isEmpty ? 'Direct' : party,
          agentName: agent.isEmpty ? 'Direct' : agent,
          date: date,
          items: const [],
          status: rowStatus,
          serverGrandTotal: item.grandTotal,
          serverQtyLabel: item.totalQuantity,
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
              e.message.toLowerCase().contains('estimate') ||
              e.message.toLowerCase().contains('data'));
      estimations.clear();
      totalPagesRx.value = 1;
      if (!looksLikeEmptyResult) {
        Get.snackbar('Could not load estimates', e.message,
            snackPosition: SnackPosition.BOTTOM);
      }
    } on ApiException catch (e) {
      estimations.clear();
      totalPagesRx.value = 1;
      Get.snackbar('Could not load estimates', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoadingList.value = false;
    }
  }

  /// The current page's rows, as returned by the server — the list view
  /// still calls this `pagedFiltered` to match its existing layout code.
  List<EstimationModel> get pagedFiltered => estimations;

  void setSearch(String value) {
    searchQuery.value = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      currentPage.value = 1;
      loadEstimates();
    });
  }

  void setTab(EstimationTab tab) {
    activeTab.value = tab;
    // See the class doc comment on [EstimationTab] — the server doesn't
    // expose a status to filter by, so this just re-fetches page 1.
    currentPage.value = 1;
    loadEstimates();
  }

  void setDateFrom(DateTime? date) {
    filterFrom.value = date;
    currentPage.value = 1;
    loadEstimates();
  }

  void setDateTo(DateTime? date) {
    filterTo.value = date;
    currentPage.value = 1;
    loadEstimates();
  }

  void setAgentFilter(String? agent) {
    filterAgent.value = agent;
    currentPage.value = 1;
    loadEstimates();
  }

  void setPartyFilter(String? party) {
    filterParty.value = party;
    currentPage.value = 1;
    loadEstimates();
  }

  void setPageSize(int size) {
    pageSize.value = size;
    currentPage.value = 1;
    loadEstimates();
  }

  void setPageNo(int page) {
    currentPage.value = page;
    loadEstimates();
  }

  void goToPage(int page) => setPageNo(page.clamp(1, totalPages));

  void toggleViewMode(bool table) => isTableView.value = table;

  /// Cancels an active estimate (server sets `cancelled = 1`) or, for a
  /// draft row, permanently deletes it (server sets `deleted = 1`) — the
  /// same `delete_estimate_id` call does either, decided server-side by
  /// the estimate's own `drafted` flag.
  Future<void> deleteEstimation(EstimationModel estimation) async {
    final id = estimation.serverEstimateId ?? estimation.id;
    if (id.isEmpty) {
      estimations.remove(estimation);
      return;
    }
    final isDraft = estimation.status == DocStatus.draft;
    try {
      final result = await _estimateRepository.deleteEstimate(estimateId: id);
      Get.snackbar(
        isDraft ? 'Draft deleted' : 'Estimate cancelled',
        result.message,
        snackPosition: SnackPosition.BOTTOM,
      );
      await loadEstimates();
    } on ApiRequestException catch (e) {
      Get.snackbar('Could not delete', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } on ApiException catch (e) {
      Get.snackbar('Could not delete', e.message,
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  // ---- Print / download report PDF ----------------------------------------

  /// Opens the A4 estimate report PDF in the device's browser/PDF viewer.
  /// Print and download both point at the same report — the viewer's own
  /// print/save controls handle each action from there.
  Future<void> _openEstimateReport(EstimationModel estimation) async {
    final id = estimation.serverEstimateId ?? estimation.id;
    if (id.isEmpty) {
      Get.snackbar('Not available', 'This estimate has no report yet',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final uri = ApiEndpoints.estimateReport(id);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      Get.snackbar('Could not open', 'Unable to open the estimate report',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> printEstimate(EstimationModel estimation) =>
      _openEstimateReport(estimation);

  Future<void> downloadEstimate(EstimationModel estimation) =>
      _openEstimateReport(estimation);

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
  double get formChargesTotal =>
      charges.fold(0.0, (sum, c) => sum + c.value);
  double get formTotal =>
      formSubTotal + formAdjustments + formChargesTotal + roundOff.value;

  // ---- Form: charges --------------------------------------------------------

  /// Looks up whether the chosen other-charge is added or deducted (via
  /// `type_other_charges_id`), then adds it with the server-determined
  /// sign — mirrors the "Charges: Select / Value / +" row on the web app.
  Future<void> addCharge(double rawValue) async {
    final chargeId = selectedChargeId.value;
    if (chargeId == null || rawValue == 0) {
      Get.snackbar('Select a charge', 'Choose a charge type and value',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final option = otherChargesOptions.firstWhereOrNull((c) => c.id == chargeId);
    if (option == null) return;

    try {
      final typeResult = await _estimateRepository.getChargeType(chargeId);
      final signedValue =
          typeResult.chargesType == 'Minus' ? -rawValue.abs() : rawValue.abs();
      charges.add(ChargeLine(
        name: option.name,
        value: signedValue,
        chargeId: chargeId,
        type: typeResult.chargesType,
      ));
      selectedChargeId.value = null;
      chargeValueCtrl.clear();
    } on ApiRequestException catch (e) {
      Get.snackbar('Could not add charge', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } on ApiException catch (e) {
      Get.snackbar('Could not add charge', e.message,
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  void removeCharge(int index) => charges.removeAt(index);

  // ---- Form: pricelist / agent selection -------------------------------

  void selectPricelist(IdName pricelist) {
    if (selectedPricelistId.value == pricelist.id) return;
    selectedPricelistId.value = pricelist.id;
    selectedPricelist.value = pricelist.name;
    loadProductsForSelectedPricelist();
  }

  void selectAgent(IdName? agent) {
    selectedAgentId.value = agent?.id;
    selectedAgent.value = agent?.name;
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
          await _estimateRepository.getProductsForPricelist(pricelistId);
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
    selectedAgent.value = null;
    selectedAgentId.value = null;
    selectedPricelist.value = null;
    selectedPricelistId.value = null;
    estimationDate.value = DateTime.now();
    formItems.clear();
    section1Add.value = 0;
    section1Discount.value = 0;
    section2Add.value = 0;
    section2Discount.value = 0;
    charges.clear();
    selectedChargeId.value = null;
    roundOff.value = 0;
    productOptions.clear();
    _syncMoneyControllers();
  }

  void startCreate() {
    editingEstimation = null;
    _convertQuotationId = null;
    _resetFormFields();
    isLoadingForm.value = true;
    _loadFormInit(showEstimateId: '');
  }

  void startEdit(EstimationModel estimation) {
    editingEstimation = estimation;
    _convertQuotationId = null;
    _resetFormFields();
    estimationDate.value = estimation.date;
    isLoadingForm.value = true;
    _loadFormInit(showEstimateId: estimation.serverEstimateId ?? estimation.id);
  }

  /// Bootstraps a brand-new Add Estimate form pre-filled from an active
  /// quotation's own party/pricelist/agent/products — the "Convert to
  /// Estimate" action on the Quotation list. [quotationId] is kept and
  /// sent back as `convert_quotation_id` when the form is saved.
  void startConvertFromQuotation(String quotationId) {
    editingEstimation = null;
    _convertQuotationId = quotationId;
    _resetFormFields();
    isLoadingForm.value = true;
    _loadFormInit(showEstimateId: '', convertQuotationId: quotationId);
  }

  DateTime? _tryParseServerDate(String raw) {
    if (raw.isEmpty) return null;
    try {
      return _apiDateFormat.parseStrict(raw);
    } catch (_) {
      return null;
    }
  }

  /// Bootstraps the Add/Edit Estimate form via `show_estimate_id`:
  /// dropdown data always, plus the existing estimate's own fields when
  /// [showEstimateId] resolves to a real record, or a source quotation's
  /// fields when [convertQuotationId] is supplied instead.
  Future<void> _loadFormInit({
    required String showEstimateId,
    String convertQuotationId = '',
  }) async {
    try {
      final result = await _estimateRepository.getFormInitData(
        showEstimateId: showEstimateId,
        convertQuotationId: convertQuotationId,
      );

      pricelistOptions.assignAll(result.pricelist);
      agentOptions.assignAll(result.agentList);
      parties.assignAll(result.partyList.map((p) => PartyModel(
            id: p.id,
            serverPartyId: p.id,
            name: p.name.isEmpty ? 'Untitled Party' : p.name,
            hasFullDetails: false,
          )));
      otherChargesOptions.assignAll(result.otherCharges);

      final detail = result.detail;
      if (detail != null) {
        if (detail.pricelistId.isNotEmpty) {
          final pl = pricelistOptions
              .firstWhereOrNull((p) => p.id == detail.pricelistId);
          selectedPricelistId.value = detail.pricelistId;
          selectedPricelist.value = pl?.name;
        }
        if (detail.agentId.isNotEmpty) {
          final ag =
              agentOptions.firstWhereOrNull((a) => a.id == detail.agentId);
          selectedAgentId.value = detail.agentId;
          selectedAgent.value = ag?.name;
        }
        if (detail.partyId.isNotEmpty) {
          selectedParty.value = parties
              .firstWhereOrNull((p) => p.serverPartyId == detail.partyId);
        }
        final parsedDate = _tryParseServerDate(detail.estimateDate);
        if (parsedDate != null) estimationDate.value = parsedDate;

        formItems.assignAll(detail.products.map((row) {
          final section = row.productDiscount == '1' ? 1 : 2;
          _stockCache.remove(row.productId); // unknown until re-queried
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

        charges.assignAll(detail.charges.map((c) {
          final magnitude = double.tryParse(c.value) ?? 0;
          final signed =
              c.type == 'Minus' ? -magnitude.abs() : magnitude.abs();
          return ChargeLine(
            name: c.chargeName,
            value: signed,
            chargeId: c.chargeId,
            type: c.type.isEmpty ? 'Plus' : c.type,
          );
        }));
      } else if (pricelistOptions.isNotEmpty) {
        // New estimate — default to the first pricelist, matching the web
        // app's Add Estimate screen.
        selectedPricelistId.value = pricelistOptions.first.id;
        selectedPricelist.value = pricelistOptions.first.name;
      }

      _syncMoneyControllers();

      if (selectedPricelistId.value != null &&
          selectedPricelistId.value!.isNotEmpty) {
        await loadProductsForSelectedPricelist();
      }
    } on ApiRequestException catch (e) {
      Get.snackbar('Could not load estimate', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } on ApiException catch (e) {
      Get.snackbar('Could not load estimate', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoadingForm.value = false;
    }
  }

  // ---- Form: line items ---------------------------------------------------

  /// Adds [productId] to the form. Looks up its rate/unit/stock/section
  /// for the currently selected pricelist via `selected_product_id` —
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
      final detail = await _estimateRepository.getSelectedProductDetail(
        productId: productId,
        pricelistId: pricelistId,
      );
      _stockCache[productId] = detail.currentStock;

      // Matches the server's own rule for which totals section a line
      // lands in once saved (see estimate.php's `product_discount` check).
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

  /// Adds/updates many products at once from the full-screen product
  /// picker. Unlike [addProductById], this never calls the network —
  /// `product_pricelist_id` (already loaded into [productOptions]) returns
  /// rate/unit/discount-flag/stock for every product, so a multi-select
  /// "Add to Estimate" can apply all of them in one shot.
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

      _stockCache[option.productId] = option.currentStock;
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

  void updateQuantity(int index, int qty) {
    if (qty < 1) return;
    formItems[index].quantity = qty;
    formItems.refresh();
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
    selectedAgent.value = null;
    selectedAgentId.value = null;
    section1Add.value = 0;
    section1Discount.value = 0;
    section2Add.value = 0;
    section2Discount.value = 0;
    charges.clear();
    selectedChargeId.value = null;
    roundOff.value = 0;
    _syncMoneyControllers();
  }

  // ---- Form: save -----------------------------------------------------------

  Future<bool> save({required bool asDraft}) async {
    if (isSaving.value) return false;

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

    final session = _sessionService.currentSession.value;
    if (session == null) {
      Get.snackbar('Session expired', 'Please log in again',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }

    // estimate.php's `estimate_update` has no separate "draft" flag —
    // every call is a real create/update. [asDraft] is kept for parity
    // with the Draft/Confirm buttons on screen, but doesn't change the
    // payload sent to the server.
    isSaving.value = true;
    try {
      final result = await _estimateRepository.saveEstimate(
        creator: session.userId,
        editId: editingEstimation?.serverEstimateId ?? '',
        convertQuotationId: _convertQuotationId ?? '',
        estimateDate: _apiDateFormat.format(estimationDate.value),
        pricelistId: selectedPricelistId.value!,
        agentId: selectedAgentId.value ?? '',
        partyId:
            selectedParty.value!.serverPartyId ?? selectedParty.value!.id,
        products: formItems
            .map((i) => EstimateProductLine(
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
        charges: charges
            .map((c) => EstimateChargeLine(
                  chargeId: c.chargeId,
                  type: c.type,
                  value: c.value.abs().toString(),
                ))
            .toList(),
      );

      final wasCreate = editingEstimation == null;
      final convertedQuotationId = _convertQuotationId;
      _convertQuotationId = null;
      Get.back();
      Get.snackbar('Saved', result.message,
          snackPosition: SnackPosition.BOTTOM);
      if (wasCreate) currentPage.value = 1;
      await loadEstimates();
      // The quotation this estimate was converted from now has its own
      // `estimate_id` set server-side — refresh its list (if it's alive)
      // so the Convert/Edit/Delete actions on that row disappear.
      if (convertedQuotationId != null &&
          convertedQuotationId.isNotEmpty &&
          Get.isRegistered<QuotationController>()) {
        unawaited(Get.find<QuotationController>().loadQuotations());
      }
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