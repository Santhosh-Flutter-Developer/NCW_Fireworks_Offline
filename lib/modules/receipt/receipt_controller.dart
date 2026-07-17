import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:ncw_fireworks/core/utils/pdf_downloader.dart';
import 'package:ncw_fireworks/modules/estimation/estimation_controller.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/session_service.dart';
import '../../data/models/billing_item_model.dart';
import '../../data/models/party_model.dart';
import '../../data/models/receipt/id_name.dart';
import '../../data/models/receipt_model.dart';
import '../../data/respositories/receipt_repository.dart';

/// The 2 tabs shown above the Receipt list on the web app — `receipt.php`'s
/// `cancelled` filter on `receipt_listing`: Active is `cancelled=0`, Cancel
/// is `cancelled=1`. Mirrors `QuotationTab` on the Quotation screen.
enum ReceiptTab { active, cancel }

extension ReceiptTabX on ReceiptTab {
  String get label {
    switch (this) {
      case ReceiptTab.active:
        return 'Active';
      case ReceiptTab.cancel:
        return 'Cancel';
    }
  }
}

class ReceiptController extends GetxController {
  ReceiptController({
    ReceiptRepository? receiptRepository,
    SessionService? sessionService,
  })  : _receiptRepository = receiptRepository ?? ReceiptRepository(),
        _sessionService = sessionService ?? Get.find<SessionService>();

  final ReceiptRepository _receiptRepository;
  final SessionService _sessionService;

  static final DateFormat _apiDateFormat = DateFormat('dd-MM-yyyy');
  static final DateFormat _serverStoredDateFormat = DateFormat('yyyy-MM-dd');

  // ---- List screen state ---------------------------------------------------
  final receipts = <ReceiptModel>[].obs;
  final searchQuery = ''.obs; // receipt number
  final Rx<DateTime?> filterFrom = Rx<DateTime?>(null);
  final Rx<DateTime?> filterTo = Rx<DateTime?>(null);

  /// Party dropdown options, populated from `receipt_listing`'s own
  /// `party_list` — same shape/source as `QuotationController.parties`.
  final parties = <PartyModel>[].obs;
  final Rx<String?> filterParty = Rx<String?>(null); // party *name*
  final activeTab = ReceiptTab.active.obs;
  final isTableView = false.obs;
  final pageSize = 10.obs;
  final currentPage = 1.obs;
  final isLoadingList = false.obs;

  /// `receipt_listing` doesn't return a total row/page count — same
  /// self-correcting approach as `EstimationController`/`PartyController`.
  final totalPagesRx = 1.obs;
  int get totalPages => totalPagesRx.value;

  Timer? _searchDebounce;

  // ---- Add Receipt form: static dropdown data -------------------------------
  final paymentModeOptions = <IdName>[].obs;
  final isLoadingForm = false.obs;
  final isSaving = false.obs;

  // ---- Add Receipt form: fields ---------------------------------------------
  final Rx<DateTime> receiptDate = Rx<DateTime>(DateTime.now());
  final billNumberCtrl = TextEditingController().obs;
  final deductionCtrl = TextEditingController();
  final narrationCtrl = TextEditingController();

  final isLookingUpBill = false.obs;
  final billLookupError = Rx<String?>(null);
  final billFoundNumber = ''.obs;
  final billParty = ''.obs;
  final billTotalAmount = 0.0.obs;
  bool get hasBillLoaded => billFoundNumber.value.isNotEmpty;

  // Current "Add To Bill" row-in-progress.
  final Rx<IdName?> selectedPaymentMode = Rx<IdName?>(null);
  final bankOptions = <IdName>[].obs;
  final isLoadingBanks = false.obs;
  final Rx<IdName?> selectedBank = Rx<IdName?>(null);
  final amountCtrl = TextEditingController();
  final isLoadingBalance = false.obs;
  final accountBalance = Rx<double?>(null);

  final paymentLines = <ReceiptPaymentLine>[].obs;

  double get deduction => double.tryParse(deductionCtrl.text.trim()) ?? 0;
  double get addedTotal => paymentLines.fold(0.0, (sum, l) => sum + l.amount);

  /// Best-effort "how much of the bill is left to allocate" figure. The
  /// server doesn't expose a paid/pending breakdown on the bill-lookup
  /// call, so this only accounts for what's been added to the table in
  /// this session plus the deduction — not any receipts made earlier.
  double get remainingForBill => billTotalAmount.value - deduction - addedTotal;

  @override
  void onInit() {
    super.onInit();
    loadReceipts();
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    billNumberCtrl.value.dispose();
    deductionCtrl.dispose();
    narrationCtrl.dispose();
    amountCtrl.dispose();
    super.onClose();
  }

  // ---- List loading / filtering / pagination --------------------------------

  String? _partyIdForName(String? name) {
    if (name == null) return null;
    return parties.firstWhereOrNull((p) => p.name == name)?.serverPartyId;
  }

  Future<void> loadReceipts() async {
    isLoadingList.value = true;
    try {
      final result = await _receiptRepository.listReceipts(
        filterFromDate: filterFrom.value != null
            ? _apiDateFormat.format(filterFrom.value!)
            : '',
        filterToDate: filterTo.value != null
            ? _apiDateFormat.format(filterTo.value!)
            : '',
        searchText: searchQuery.value.trim(),
        filterPartyId: _partyIdForName(filterParty.value) ?? '',
        cancelled: activeTab.value == ReceiptTab.cancel ? '1' : '0',
        pageNumber: currentPage.value,
        pageLimit: pageSize.value,
      );

      final rowStatus = switch (activeTab.value) {
        ReceiptTab.active => DocStatus.active,
        ReceiptTab.cancel => DocStatus.cancelled,
      };

      if (result.partyList.isNotEmpty) {
        parties.assignAll(result.partyList.map((p) => PartyModel(
              id: p.id,
              serverPartyId: p.id,
              name: p.name.isEmpty ? 'Untitled Party' : p.name,
              hasFullDetails: false,
            )));
      }

      receipts.assignAll(result.items.map((item) {
        final parsedDate = DateTime.tryParse(item.receiptDate) ??
            _tryParse(_serverStoredDateFormat, item.receiptDate) ??
            DateTime.now();
        return ReceiptModel(
          id: item.receiptId,
          receiptNumber: item.receiptNumber,
          date: parsedDate,
          agentName: _stripHtml(item.agentName).isEmpty
              ? 'Direct'
              : _stripHtml(item.agentName),
          partyName: item.partyName,
          totalAmount: item.totalAmount,
          status: rowStatus,
        );
      }));

      totalPagesRx.value = receipts.length < pageSize.value
          ? currentPage.value
          : currentPage.value + 1;
    } on ApiRequestException catch (e) {
      Get.snackbar('Could not load receipts', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } on ApiException catch (e) {
      Get.snackbar('Could not load receipts', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoadingList.value = false;
    }
  }

  DateTime? _tryParse(DateFormat fmt, String raw) {
    try {
      return fmt.parseStrict(raw);
    } catch (_) {
      return null;
    }
  }

  String _stripHtml(String raw) =>
      raw.replaceAll(RegExp(r'<[^>]*>'), '').trim();

  /// The current page's rows, as returned by the server — the list view
  /// still calls this `visibleReceipts` to match its existing layout code.
  List<ReceiptModel> get visibleReceipts => receipts;

  void setSearch(String value) {
    searchQuery.value = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      currentPage.value = 1;
      loadReceipts();
    });
  }

  void setDateFrom(DateTime? date) {
    filterFrom.value = date;
    currentPage.value = 1;
    loadReceipts();
  }

  void setDateTo(DateTime? date) {
    filterTo.value = date;
    currentPage.value = 1;
    loadReceipts();
  }

  void setPartyFilter(String? party) {
    filterParty.value = party;
    currentPage.value = 1;
    loadReceipts();
  }

  void setTab(ReceiptTab tab) {
    activeTab.value = tab;
    currentPage.value = 1;
    loadReceipts();
  }

  void clearFilters() {
    searchQuery.value = '';
    filterFrom.value = null;
    filterTo.value = null;
    filterParty.value = null;
    activeTab.value = ReceiptTab.active;
    currentPage.value = 1;
    loadReceipts();
  }

  void setPageSize(int size) {
    pageSize.value = size;
    currentPage.value = 1;
    loadReceipts();
  }

  void setPageNo(int page) {
    currentPage.value = page;
    loadReceipts();
  }

  void goToPage(int page) => setPageNo(page.clamp(1, totalPages));

  void toggleViewMode(bool table) => isTableView.value = table;

  // ---- Delete ---------------------------------------------------------------

  Future<void> deleteReceipt(ReceiptModel receipt) async {
    try {
      final result =
          await _receiptRepository.deleteReceipt(receiptId: receipt.id);
      Get.snackbar('Receipt cancelled', result.message,
          snackPosition: SnackPosition.BOTTOM);
      await loadReceipts();
    } on ApiRequestException catch (e) {
      Get.snackbar('Could not delete', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } on ApiException catch (e) {
      Get.snackbar('Could not delete', e.message,
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  // ---- Print / download report PDF ------------------------------------------

  Future<void> _openReceiptReport(ReceiptModel receipt) async {
    final uri = ApiEndpoints.receiptReport(receipt.id);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      Get.snackbar('Could not open', 'Unable to open the receipt report',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> printReceipt(ReceiptModel receipt) =>
      _openReceiptReport(receipt);
 Future<void> downloadReceipt(ReceiptModel receipt) async {
  try {
    await PdfDownloader.download(
      uri: ApiEndpoints.receiptReport(receipt.id),
      fileName: receipt.receiptNumber,
    );
    Get.snackbar('Downloaded', 'Receipt report saved',
        snackPosition: SnackPosition.BOTTOM);
  } catch (e) {
    Get.snackbar('Could not download', 'Unable to download the receipt report',
        snackPosition: SnackPosition.BOTTOM);
  }
}

  // ---- Add Receipt form -------------------------------------------------------

  void _resetForm() {
    receiptDate.value = DateTime.now();
    billNumberCtrl.value.text = '';
    deductionCtrl.text = '';
    narrationCtrl.text = '';
    billLookupError.value = null;
    billFoundNumber.value = '';
    billParty.value = '';
    billTotalAmount.value = 0;
    selectedPaymentMode.value = null;
    bankOptions.clear();
    selectedBank.value = null;
    amountCtrl.text = '';
    accountBalance.value = null;
    paymentLines.clear();
  }

  Future<void> startCreate({String? prefillBillNumber}) async {
    _resetForm();
    if (prefillBillNumber != null && prefillBillNumber.isNotEmpty) {
    billNumberCtrl.value.text = prefillBillNumber;
    billNumberCtrl.refresh();
  }
    isLoadingForm.value = true;
    try {
      final result = await _receiptRepository.getFormInitData();
      paymentModeOptions.assignAll(result.paymentModes);
      final serverDate = _tryParse(_apiDateFormat, result.receiptDate);
      if (serverDate != null) receiptDate.value = serverDate;
    } on ApiRequestException catch (e) {
      Get.snackbar('Could not load form', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } on ApiException catch (e) {
      Get.snackbar('Could not load form', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoadingForm.value = false;
    }
     if (prefillBillNumber != null && prefillBillNumber.isNotEmpty) {
    await lookupBillNumber();
  }
  }

  /// Looks up the bill typed into "Bill Number" — mirrors the web app
  /// triggering this on blur/enter rather than on every keystroke.
  Future<void> lookupBillNumber() async {
    final billNo = billNumberCtrl.value.text.trim();
    billLookupError.value = null;
    if (billNo.isEmpty) {
      billFoundNumber.value = '';
      billParty.value = '';
      billTotalAmount.value = 0;
      return;
    }
    isLookingUpBill.value = true;
    try {
      final result = await _receiptRepository.lookupBill(billNo);
      billFoundNumber.value = result.estimateNumber;
      billParty.value = result.party;
      billTotalAmount.value = result.totalAmount;
    } on ApiRequestException catch (e) {
      billFoundNumber.value = '';
      billParty.value = '';
      billTotalAmount.value = 0;
      billLookupError.value = e.message;
    } on ApiException catch (e) {
      billLookupError.value = e.message;
    } finally {
      isLookingUpBill.value = false;
    }
  }

  /// Loads the Bank dropdown for a chosen payment mode. An empty result
  /// means this mode is cash-style — no Bank field needed for this row.
  Future<void> selectPaymentMode(IdName? mode) async {
    selectedPaymentMode.value = mode;
    selectedBank.value = null;
    bankOptions.clear();
    accountBalance.value = null;
    if (mode == null) return;

    isLoadingBanks.value = true;
    try {
      final result = await _receiptRepository.getBanksForPaymentMode(mode.id);
      bankOptions.assignAll(result.banks);
      if (result.banks.isEmpty) {
        // Cash-style mode — balance is keyed directly off the payment mode.
        await _loadBalance(mode.id);
      }
    } on ApiRequestException catch (e) {
      Get.snackbar('Could not load banks', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } on ApiException catch (e) {
      Get.snackbar('Could not load banks', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoadingBanks.value = false;
    }
  }

  Future<void> selectBank(IdName? bank) async {
    selectedBank.value = bank;
    if (bank != null) await _loadBalance(bank.id);
  }

  Future<void> _loadBalance(String accountId) async {
    isLoadingBalance.value = true;
    accountBalance.value = null;
    try {
      final result = await _receiptRepository.getAccountBalance(accountId);
      accountBalance.value = result.balanceAmount;
    } on ApiException {
      accountBalance.value = null;
    } finally {
      isLoadingBalance.value = false;
    }
  }

  /// Appends the in-progress Payment Mode/Bank/Amount row to the table —
  /// "Add To Bill" on the web app.
  bool addPaymentLine() {
    final mode = selectedPaymentMode.value;
    if (mode == null) {
      Get.snackbar('Select payment mode', 'Choose a payment mode first',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }
    final needsBank = bankOptions.isNotEmpty;
    if (needsBank && selectedBank.value == null) {
      Get.snackbar('Select bank', 'Choose a bank for this payment mode',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      Get.snackbar('Enter amount', 'Amount must be greater than zero',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }

    paymentLines.add(ReceiptPaymentLine(
      paymentModeId: mode.id,
      paymentModeName: mode.name,
      bankId: selectedBank.value?.id ?? '',
      bankName: selectedBank.value?.name ?? '',
      amount: amount,
    ));

    selectedPaymentMode.value = null;
    selectedBank.value = null;
    bankOptions.clear();
    amountCtrl.text = '';
    accountBalance.value = null;
    return true;
  }

  void removePaymentLine(int index) => paymentLines.removeAt(index);

  void updatePaymentLineAmount(int index, double amount) {
    paymentLines[index].amount = amount;
    paymentLines.refresh();
  }

  Future<bool> submitReceipt() async {
    if (!hasBillLoaded) {
      Get.snackbar('Bill required', 'Look up a valid bill number first',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }
    if (paymentLines.isEmpty) {
      Get.snackbar('Add payment', 'Add at least one payment mode row',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }
    final creator = _sessionService.currentSession.value?.userId;
    if (creator == null || creator.isEmpty) {
      Get.snackbar('Session expired', 'Please log in again',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }

    isSaving.value = true;
    try {
      final result = await _receiptRepository.saveReceipt(
        creator: creator,
        receiptDate: _apiDateFormat.format(receiptDate.value),
        againstBillNumber: billFoundNumber.value,
        deduction: deductionCtrl.text.trim(),
        narration: narrationCtrl.text.trim(),
        entries: paymentLines
            .map((l) => ReceiptPaymentEntry(
                  paymentModeId: l.paymentModeId,
                  bankId: l.bankId,
                  amount: l.amount.toStringAsFixed(2),
                ))
            .toList(),
      );
      Get.back();
      Get.snackbar('Saved', result.message,
          snackPosition: SnackPosition.BOTTOM);
      currentPage.value = 1;
      Future.delayed(const Duration(seconds: 1), () async {
        await loadReceipts();
        if (Get.isRegistered<EstimationController>()) {
          unawaited(Get.find<EstimationController>().loadEstimates());
        }
        
      });
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
