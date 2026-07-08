import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../data/dummy/dummy_data.dart';
import '../../data/models/billing_item_model.dart';
import '../../data/models/party_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/quotation_model.dart';

/// The 3 tabs shown above the Quotation list on the web app.
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
  final quotations = <QuotationModel>[].obs;
  final parties = DummyData.parties();
  final products = DummyData.products();
  final agents = DummyData.agents;

  // ---- List screen state -------------------------------------------------
  final searchQuery = ''.obs;
  final activeTab = QuotationTab.active.obs;
  final isTableView = false.obs;
  final Rx<DateTime?> filterFrom = Rx<DateTime?>(null);
  final Rx<DateTime?> filterTo = Rx<DateTime?>(null);
  final Rx<String?> filterAgent = Rx<String?>(null);
  final Rx<String?> filterParty = Rx<String?>(null);
  final pageSize = 10.obs;
  final currentPage = 1.obs;

  List<String> get pricelistNames {
    final names = <String>{};
    for (final p in products) {
      for (final entry in p.prices) {
        names.add(entry.pricelistName);
      }
    }
    return names.toList()..sort();
  }

  // ---- Form state ---------------------------------------------------------
  QuotationModel? editingQuotation;
  final Rx<PartyModel?> selectedParty = Rx<PartyModel?>(null);
  final Rx<String?> selectedAgent = Rx<String?>(null);
  final Rx<String?> selectedPricelist = Rx<String?>(null);
  final Rx<DateTime> quotationDate = Rx<DateTime>(DateTime.now());
  final Rx<DateTime> validTill =
      Rx<DateTime>(DateTime.now().add(const Duration(days: 14)));
  final formItems = <BillingItemModel>[].obs;
  final section1Add = 0.0.obs;
  final section1Discount = 0.0.obs;
  final section2Add = 0.0.obs;
  final section2Discount = 0.0.obs;
  final roundOff = 0.0.obs;

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
    quotations.assignAll(DummyData.quotations());
  }

  @override
  void onClose() {
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

  // ---- List filtering / pagination ----------------------------------------

  DocStatus get _tabStatus {
    switch (activeTab.value) {
      case QuotationTab.active:
        return DocStatus.active;
      case QuotationTab.draft:
        return DocStatus.draft;
      case QuotationTab.cancel:
        return DocStatus.cancelled;
    }
  }

  List<QuotationModel> get filtered {
    final list = quotations.where((q) {
      final matchesTab = q.status == _tabStatus;
      final matchesQuery = searchQuery.value.isEmpty ||
          q.quotationNo.toLowerCase().contains(searchQuery.value.toLowerCase());
      final matchesAgent =
          filterAgent.value == null || q.agentName == filterAgent.value;
      final matchesParty =
          filterParty.value == null || q.partyName == filterParty.value;
      final matchesFrom = filterFrom.value == null ||
          !q.date.isBefore(DateTime(filterFrom.value!.year,
              filterFrom.value!.month, filterFrom.value!.day));
      final matchesTo = filterTo.value == null ||
          !q.date.isAfter(DateTime(filterTo.value!.year, filterTo.value!.month,
              filterTo.value!.day, 23, 59, 59));
      return matchesTab &&
          matchesQuery &&
          matchesAgent &&
          matchesParty &&
          matchesFrom &&
          matchesTo;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  /// The current page slice of [filtered], matching the "entries per page"
  /// selector + pager on the web app's Quotation list.
  List<QuotationModel> get pagedFiltered {
    final list = filtered;
    if (currentPage.value > totalPages(list.length)) {
      currentPage.value = 1;
    }
    final start = (currentPage.value - 1) * pageSize.value;
    if (start >= list.length) return [];
    final end = (start + pageSize.value).clamp(0, list.length);
    return list.sublist(start, end);
  }

  int totalPages(int count) =>
      count == 0 ? 1 : (count / pageSize.value).ceil();

  void setSearch(String value) {
    searchQuery.value = value;
    currentPage.value = 1;
  }

  void setTab(QuotationTab tab) {
    activeTab.value = tab;
    currentPage.value = 1;
  }

  void setDateFrom(DateTime? date) {
    filterFrom.value = date;
    currentPage.value = 1;
  }

  void setDateTo(DateTime? date) {
    filterTo.value = date;
    currentPage.value = 1;
  }

  void setAgentFilter(String? agent) {
    filterAgent.value = agent;
    currentPage.value = 1;
  }

  void setPartyFilter(String? party) {
    filterParty.value = party;
    currentPage.value = 1;
  }

  void setPageSize(int size) {
    pageSize.value = size;
    currentPage.value = 1;
  }

  void goToPage(int page) {
    currentPage.value = page.clamp(1, totalPages(filtered.length));
  }

  void toggleViewMode(bool table) => isTableView.value = table;

  void cancelQuotation(QuotationModel quotation) {
    quotation.status = DocStatus.cancelled;
    quotations.refresh();
    Get.snackbar('Cancelled', '${quotation.quotationNo} was cancelled',
        snackPosition: SnackPosition.BOTTOM);
  }

  // ---- Form ----------------------------------------------------------------

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

  void startCreate() {
    editingQuotation = null;
    selectedParty.value = null;
    selectedAgent.value = null;
    selectedPricelist.value =
        pricelistNames.isNotEmpty ? pricelistNames.first : null;
    quotationDate.value = DateTime.now();
    validTill.value = DateTime.now().add(const Duration(days: 14));
    formItems.clear();
    section1Add.value = 0;
    section1Discount.value = 0;
    section2Add.value = 0;
    section2Discount.value = 0;
    roundOff.value = 0;
    _syncMoneyControllers();
  }

  void startEdit(QuotationModel quotation) {
    editingQuotation = quotation;
    selectedParty.value = parties.firstWhereOrNull(
      (p) => p.id == quotation.partyId,
    );
    selectedAgent.value =
        quotation.agentName.isEmpty ? null : quotation.agentName;
    selectedPricelist.value = quotation.pricelistName.isEmpty
        ? (pricelistNames.isNotEmpty ? pricelistNames.first : null)
        : quotation.pricelistName;
    quotationDate.value = quotation.date;
    validTill.value = quotation.validTill;
    formItems.assignAll(quotation.items
        .map((i) => BillingItemModel(
              productId: i.productId,
              productName: i.productName,
              quantity: i.quantity,
              rate: i.rate,
              discountPercent: i.discountPercent,
              unit: i.unit,
              section: i.section,
            ))
        .toList());
    section1Add.value = quotation.section1Add;
    section1Discount.value = quotation.section1Discount;
    section2Add.value = quotation.section2Add;
    section2Discount.value = quotation.section2Discount;
    roundOff.value = quotation.roundOff;
    _syncMoneyControllers();
  }

  void addProductToForm(ProductModel product, {int qty = 1, int section = 1}) {
    final existingIndex = formItems
        .indexWhere((i) => i.productId == product.id && i.section == section);
    if (existingIndex >= 0) {
      formItems[existingIndex].quantity += qty;
      formItems.refresh();
    } else {
      final rate = selectedPricelist.value != null
          ? (product.prices
                  .firstWhereOrNull(
                      (p) => p.pricelistName == selectedPricelist.value)
                  ?.price ??
              product.price)
          : product.price;
      formItems.add(BillingItemModel(
        productId: product.id,
        productName: product.name,
        quantity: qty,
        rate: rate,
        unit: product.unit,
        section: section,
      ));
    }
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
    section1Add.value = 0;
    section1Discount.value = 0;
    section2Add.value = 0;
    section2Discount.value = 0;
    roundOff.value = 0;
    _syncMoneyControllers();
  }

  bool save({required bool asDraft}) {
    if (!asDraft && selectedParty.value == null) {
      Get.snackbar('Missing party', 'Please select a party',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }
    if (formItems.isEmpty) {
      Get.snackbar('No items', 'Add at least one product',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }

    final status = asDraft ? DocStatus.draft : DocStatus.active;

    if (editingQuotation != null) {
      editingQuotation!
        ..partyId = selectedParty.value?.id ?? editingQuotation!.partyId
        ..partyName = selectedParty.value?.name ?? editingQuotation!.partyName
        ..agentName = selectedAgent.value ?? 'Direct'
        ..pricelistName = selectedPricelist.value ?? ''
        ..date = quotationDate.value
        ..validTill = validTill.value
        ..items = formItems.toList()
        ..status = status
        ..section1Add = section1Add.value
        ..section1Discount = section1Discount.value
        ..section2Add = section2Add.value
        ..section2Discount = section2Discount.value
        ..roundOff = roundOff.value;
      quotations.refresh();
    } else {
      quotations.insert(
        0,
        QuotationModel(
          id: 'Q${(quotations.length + 1).toString().padLeft(3, '0')}',
          quotationNo:
              'QUT${(quotations.length + 5).toString().padLeft(3, '0')}/26-27',
          partyId: selectedParty.value?.id ?? '',
          partyName: selectedParty.value?.name ?? 'Direct',
          agentName: selectedAgent.value ?? 'Direct',
          pricelistName: selectedPricelist.value ?? '',
          date: quotationDate.value,
          validTill: validTill.value,
          items: formItems.toList(),
          status: status,
          section1Add: section1Add.value,
          section1Discount: section1Discount.value,
          section2Add: section2Add.value,
          section2Discount: section2Discount.value,
          roundOff: roundOff.value,
        ),
      );
    }
    Get.back();
    Get.snackbar(
      asDraft ? 'Saved as draft' : 'Confirmed',
      asDraft
          ? 'Quotation saved as a draft'
          : 'Quotation confirmed successfully',
      snackPosition: SnackPosition.BOTTOM,
    );
    return true;
  }

  void deleteQuotation(QuotationModel quotation) {
    quotations.remove(quotation);
    Get.snackbar('Deleted', '${quotation.quotationNo} was removed',
        snackPosition: SnackPosition.BOTTOM);
  }
}
