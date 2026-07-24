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
import '../../core/utils/id_generator.dart';
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

  /// Bumped on every `loadReceipts()` call; a response is only applied
  /// if it's still the most recent request when it comes back — guards
  /// against rapid page/filter/tab changes firing overlapping requests
  /// whose responses arrive out of order and clobber the current page.
  int _requestId = 0;

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

  /// The source estimate's own id, set by [startCreate] whenever this
  /// form was opened via the Estimate list's Receipt icon
  /// (`EstimationController.payReceipt`) — the only way the Bill Number
  /// field is ever populated, since it's read-only. Carried through to
  /// [submitReceipt] so the queued receipt can flip that estimate's
  /// `isConverted` immediately, offline included (see
  /// `ReceiptRepository.markEstimateLocallyConverted`).
  String? _prefillEstimateId;

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
    resetForFreshVisit();
  }

  /// Called every time the Receipt list screen is freshly entered via
  /// navigation (see `_ReceiptListFreshVisit` in `receipt_list_view.dart`).
  /// GetX only disposes a `lazyPut` controller once every route bound to
  /// it has been fully popped — if the sidebar pushes `/receipt` again
  /// while an earlier visit is still further down the Navigator stack,
  /// the *same* controller instance gets reused and `onInit()` never runs
  /// a second time. This puts it back to a clean slate regardless — search
  /// text cleared, page size back to 10, first page, Active tab, both
  /// date filters cleared, "All Partys" selected, list view (not table
  /// view) — then reloads. Works the same online or offline since
  /// [loadReceipts] already falls back to the local cache when there's no
  /// connection.
  void resetForFreshVisit() {
    _searchDebounce?.cancel();
    searchQuery.value = '';
    pageSize.value = 10;
    currentPage.value = 1;
    activeTab.value = ReceiptTab.active;
    filterFrom.value = null;
    filterTo.value = null;
    filterParty.value = null;
    isTableView.value = false;
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
    final requestId = ++_requestId;
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
      if (requestId != _requestId) return; // A newer request has since started.

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
          isPending: item.isPending,
          localId: item.localId,
        );
      }));

      // Prefer the known total row count derived from the last sync (see
      // ReceiptRepository._cachedTotalCount) — this stays fixed while
      // paging instead of growing by one every time Next is tapped. Only
      // falls back to inferring from "was this page full" when nothing's
      // been synced yet to count against.
      final totalRecords = result.totalRecords;
      totalPagesRx.value = totalRecords != null
          ? (totalRecords <= 0
              ? 1
              : (totalRecords / pageSize.value).ceil())
          : (receipts.length < pageSize.value
              ? currentPage.value
              : currentPage.value + 1);
    } on ApiRequestException catch (e) {
      if (requestId != _requestId) return;
      final looksLikeEmptyResult = e.message.toLowerCase().contains('no') &&
          (e.message.toLowerCase().contains('record') ||
              e.message.toLowerCase().contains('receipt') ||
              e.message.toLowerCase().contains('data'));
      receipts.clear();
      totalPagesRx.value = 1;
      if (!looksLikeEmptyResult) {
        Get.snackbar('Could not load receipts', e.message,
            snackPosition: SnackPosition.BOTTOM);
      }
    } on ApiException catch (e) {
      if (requestId != _requestId) return;
      receipts.clear();
      totalPagesRx.value = 1;
      Get.snackbar('Could not load receipts', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (requestId == _requestId) isLoadingList.value = false;
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
    if (isLoadingList.value || page == currentPage.value) return;
    currentPage.value = page;
    loadReceipts();
  }

  void goToPage(int page) => setPageNo(page.clamp(1, totalPages));

  void toggleViewMode(bool table) => isTableView.value = table;

  // ---- Delete ---------------------------------------------------------------

  /// A synced receipt is cancelled on the server (soft-void — payment
  /// entries reversed server-side, matches the old behaviour exactly). A
  /// receipt still sitting in the pending-sync queue was never sent to
  /// the server at all, so "delete" here just drops it from the queue —
  /// entirely offline — and un-marks the source estimate's
  /// `isConverted`, so its Receipt/Edit icons come back immediately,
  /// since the conversion never actually happened.
  Future<void> deleteReceipt(ReceiptModel receipt) async {
    if (receipt.isPending) {
      await _receiptRepository.cancelPendingReceipt(receipt.localId);
      Get.snackbar('Cancelled', 'Moved to the Cancel tab.',
          snackPosition: SnackPosition.BOTTOM);
      await loadReceipts();
      if (Get.isRegistered<EstimationController>()) {
        unawaited(Get.find<EstimationController>().loadEstimates());
      }
      return;
    }
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

  /// A pending receipt has no server-side PDF yet — there's nothing to
  /// open/download until it's actually synced.
  bool _warnIfPending(ReceiptModel receipt) {
    if (!receipt.isPending) return false;
    if (receipt.status == DocStatus.cancelled) {
      // Cancelled before it ever reached the server (see
      // `ReceiptRepository.cancelPendingReceipt`) — this will never sync,
      // so there's no report to fetch, ever, not just "not yet".
      Get.snackbar('Nothing to show',
          'This receipt was cancelled before it was ever sent to the server — there\'s no report for it.',
          snackPosition: SnackPosition.BOTTOM);
    } else {
      Get.snackbar('Not synced yet',
          'This receipt will be available to print/download once it syncs.',
          snackPosition: SnackPosition.BOTTOM);
    }
    return true;
  }

  Future<void> _openReceiptReport(ReceiptModel receipt) async {
    final uri = ApiEndpoints.receiptReport(receipt.id);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      Get.snackbar('Could not open', 'Unable to open the receipt report',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> printReceipt(ReceiptModel receipt) async {
    if (_warnIfPending(receipt)) return;
    await _openReceiptReport(receipt);
  }

  Future<void> downloadReceipt(ReceiptModel receipt) async {
    if (_warnIfPending(receipt)) return;
    try {
      await PdfDownloader.download(
        uri: ApiEndpoints.receiptReport(receipt.id),
        fileName: receipt.receiptNumber,
      );
      Get.snackbar('Downloaded', 'Receipt report saved',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar(
          'Could not download', 'Unable to download the receipt report',
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

  /// Opens the Add Receipt form. When called from the Estimate list's
  /// Receipt icon (`EstimationController.payReceipt`), [prefillEstimateId]
  /// is the source estimate's own id — the only way this form is ever
  /// populated, since Bill Number is read-only. Reads the Payment Mode
  /// dropdown straight from the offline cache (synced at login/Sync), so
  /// opening this form never needs the network.
  Future<void> startCreate({
    String? prefillBillNumber,
    String? prefillEstimateId,
  }) async {
    _resetForm();
    _prefillEstimateId = prefillEstimateId;
    if (prefillBillNumber != null && prefillBillNumber.isNotEmpty) {
      billNumberCtrl.value.text = prefillBillNumber;
      billNumberCtrl.refresh();
    }
    receiptDate.value = DateTime.now();
    paymentModeOptions.assignAll(_receiptRepository.cachedPaymentModes());
    if (prefillBillNumber != null && prefillBillNumber.isNotEmpty) {
      await lookupBillNumber();
    }
  }

  /// Looks up the bill shown in "Bill Number" — entirely offline, from
  /// the shared estimate cache (see
  /// `ReceiptRepository.lookupBillByEstimateId`), since that field is
  /// read-only and only ever prefilled from the Estimate list with the
  /// source estimate's own id already in hand. Falls back to the legacy
  /// live `lookupBill` API by bill number only if no estimate id was
  /// carried through (shouldn't normally happen given the field is
  /// read-only, but keeps old call sites working).
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
      final estimateId = _prefillEstimateId;
      final result = estimateId != null && estimateId.isNotEmpty
          ? _receiptRepository.lookupBillByEstimateId(estimateId)
          : await _receiptRepository.lookupBill(billNo);
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

  /// Loads the Bank dropdown for a chosen payment mode — entirely offline
  /// from the payment-mode → bank catalogue cached at login/Sync. An
  /// empty result means this mode is cash-style — no Bank field needed
  /// for this row. Account Balance is no longer looked up here — that
  /// was the last live network call left in the Add Receipt form; there's
  /// no offline source for it, so it's simply not shown anymore rather
  /// than requiring the network.
  Future<void> selectPaymentMode(IdName? mode) async {
    selectedPaymentMode.value = mode;
    selectedBank.value = null;
    bankOptions.clear();
    accountBalance.value = null;
    if (mode == null) return;

    bankOptions.assignAll(_receiptRepository.cachedBanksForPaymentMode(mode.id));
  }

  Future<void> selectBank(IdName? bank) async {
    selectedBank.value = bank;
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
    final session = _sessionService.currentSession.value;
    final creator = session?.userId;
    if (creator == null || creator.isEmpty) {
      Get.snackbar('Session expired', 'Please log in again',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }

    isSaving.value = true;
    try {
      final localId = IdGenerator.generate();
      await _receiptRepository.queueReceiptForSync(
        localId: localId,
        // A new receipt's edit_id is the same freshly generated id as
        // localId — the same one-id-does-both-jobs convention
        // EstimationController.save uses for a new estimate.
        editId: localId,
        estimateId: _prefillEstimateId ?? '',
        receiptNumber: _receiptRepository.nextReceiptNumber(
          billPrefix: session?.billPrefix ?? '',
        ),
        billNumber: billFoundNumber.value,
        partyName: billParty.value.isEmpty ? 'Direct' : billParty.value,
        receiptDate: _apiDateFormat.format(receiptDate.value),
        receiptDateIso: _serverStoredDateFormat.format(receiptDate.value),
        deduction: deductionCtrl.text.trim(),
        narration: narrationCtrl.text.trim(),
        totalAmount: billTotalAmount.value,
        entries: paymentLines
            .map((l) => ReceiptPaymentEntry(
                  paymentModeId: l.paymentModeId,
                  bankId: l.bankId,
                  amount: l.amount.toStringAsFixed(2),
                ))
            .toList(),
      );
      Get.back();
      Get.snackbar(
          'Saved offline',
          'This receipt will be sent to the server the next time you Sync.',
          snackPosition: SnackPosition.BOTTOM);
      currentPage.value = 1;
      // Refresh right away so the new pending row shows up in this
      // session's Receipt list, and the Estimate list immediately hides
      // this estimate's Receipt/Edit icons (its cached `receipt_id` was
      // just stamped by `queueReceiptForSync`).
      await loadReceipts();
      if (Get.isRegistered<EstimationController>()) {
        unawaited(Get.find<EstimationController>().loadEstimates());
      }
      return true;
    } on ApiException catch (e) {
      Get.snackbar('Could not save', e.message,
          snackPosition: SnackPosition.BOTTOM);
      return false;
    } finally {
      isSaving.value = false;
    }
  }
}