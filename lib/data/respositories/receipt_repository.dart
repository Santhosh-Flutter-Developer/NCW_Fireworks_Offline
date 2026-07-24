import 'package:get/get.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/cache_keys.dart';
import '../../core/services/local_cache_service.dart';
import '../../core/utils/offline_filter_utils.dart';
import '../models/receipt/id_name.dart';
import '../models/receipt/receipt_balance_response_model.dart';
import '../models/receipt/receipt_bank_response_model.dart';
import '../models/receipt/receipt_bill_lookup_response_model.dart';
import '../models/receipt/receipt_form_init_response_model.dart';
import '../models/receipt/receipt_list_response_model.dart';
import '../models/receipt/receipt_save_response_model.dart';

/// One payment-mode/bank/amount line, as sent inside the parallel
/// `payment_mode_id` / `bank_id` / `amount` arrays on `receipt_update`.
class ReceiptPaymentEntry {
  final String paymentModeId;

  /// Sent verbatim, including `""` for cash-style modes — the server
  /// expects one array slot per payment line either way (see the
  /// Postman example: `bank_id: ["", "<real id>"]`).
  final String bankId;
  final String amount;

  const ReceiptPaymentEntry({
    required this.paymentModeId,
    required this.bankId,
    required this.amount,
  });

  Map<String, dynamic> toJson() => {
        'payment_mode_id': paymentModeId,
        'bank_id': bankId,
        'amount': amount,
      };

  factory ReceiptPaymentEntry.fromJson(Map<String, dynamic> json) =>
      ReceiptPaymentEntry(
        paymentModeId: json['payment_mode_id']?.toString() ?? '',
        bankId: json['bank_id']?.toString() ?? '',
        amount: json['amount']?.toString() ?? '',
      );
}

/// Talks to `receipt.php`. Every method either returns a successful,
/// validated result or throws a typed [ApiException] — callers never need
/// to inspect raw response maps.
class ReceiptRepository {
  ReceiptRepository({
    ApiClient? apiClient,
    LocalCacheService? cacheService,
  })  : _apiClient = apiClient ?? ApiClient(),
        _cache = cacheService ?? Get.find<LocalCacheService>();

  final ApiClient _apiClient;
  final LocalCacheService _cache;

  /// The `YY-YY` financial-year suffix `receipt_number` gets appended
  /// with — same convention as `EstimateRepository._financialYearSuffix`.
  static String _financialYearSuffix(DateTime date) {
    final startYear = date.month >= 4 ? date.year : date.year - 1;
    String two(int y) => (y % 100).toString().padLeft(2, '0');
    return '${two(startYear)}-${two(startYear + 1)}';
  }

  /// Builds a *provisional* receipt number for a Receipt created
  /// offline: `RE<seq>/<FY>` — matching the format already seen on
  /// synced receipts (`RE019/26-27`, `RE020/26-27`, …), continuing the
  /// highest sequence already used this financial year across every
  /// cached tab (Active/Cancel) and anything still pending sync.
  ///
  /// This is provisional, not reserved: unlike Estimate/Quotation,
  /// `receipt_update` doesn't take a client-supplied number at all — the
  /// server assigns the real `receipt_number` itself once this actually
  /// syncs, and that real number is what ends up cached from then on.
  /// This is purely so the pending row shown in the meantime looks like
  /// a receipt number instead of showing the source estimate's own bill
  /// number.
  String nextReceiptNumber() {
    final fy = _financialYearSuffix(DateTime.now());
    final pattern =
        RegExp('RE(\\d+)/${RegExp.escape(fy)}\$', caseSensitive: false);

    var maxSeq = 0;
    void scan(Iterable<Map<String, dynamic>> rows, String key) {
      for (final row in rows) {
        final number = row[key]?.toString() ?? '';
        final match = pattern.firstMatch(number);
        if (match != null) {
          final seq = int.tryParse(match.group(1)!) ?? 0;
          if (seq > maxSeq) maxSeq = seq;
        }
      }
    }

    scan(_cache.getJsonList(CacheKeys.receiptActive), 'receipt_number');
    scan(_cache.getJsonList(CacheKeys.receiptCancel), 'receipt_number');
    scan(_cache.getJsonList(CacheKeys.receiptPending), 'receipt_number');

    final next = (maxSeq + 1).toString().padLeft(3, '0');
    return 'RE$next/$fy';
  }

  /// Payment Mode dropdown options for the Add Receipt form — refreshed
  /// once at login and via the Sync button (see
  /// `DataSyncService._syncReceiptCatalogue`), read here with no network
  /// call. Mirrors `EstimateRepository.cachedPricelists`.
  List<IdName> cachedPaymentModes() => _cache
      .getJsonList(CacheKeys.receiptPaymentModes)
      .map((m) => IdName(
            id: m['id']?.toString() ?? '',
            name: m['name']?.toString() ?? '',
          ))
      .toList();

  /// Banks linked to [paymentModeId], from the full payment-mode → bank
  /// catalogue cached at login/Sync — backs the Add Receipt form's Bank
  /// dropdown with no network call. An empty list means this mode is
  /// cash-style, same meaning as an empty [ReceiptBankResponseModel.banks].
  List<IdName> cachedBanksForPaymentMode(String paymentModeId) => _cache
      .getJsonList(CacheKeys.receiptBanks)
      .where((m) => m['payment_mode_id']?.toString() == paymentModeId)
      .map((m) => IdName(
            id: m['id']?.toString() ?? '',
            name: m['name']?.toString() ?? '',
          ))
      .toList();

  /// Bootstraps the Add Receipt form: today's default receipt date plus
  /// the Payment Mode dropdown options. Only called now as a one-time
  /// backward-compat fallback and by [DataSyncService] to refresh
  /// [cachedPaymentModes] — the normal Add Receipt flow reads
  /// [cachedPaymentModes] directly and never touches the network. There's
  /// no "load an existing receipt" mode — Receipts are create-or-delete
  /// only.
  Future<ReceiptFormInitResponseModel> getFormInitData() async {
    final json = await _apiClient.postJson(
      ApiEndpoints.receipt,
      body: {'show_receipt_id': ''},
    );

    final result = ReceiptFormInitResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Banks linked to a chosen payment mode, for the Bank dropdown. An
  /// empty list back (still `code == 200`) means this mode is cash-style
  /// and has no bank of its own — see [ReceiptBankResponseModel].
  Future<ReceiptBankResponseModel> getBanksForPaymentMode(
    String paymentModeId,
  ) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.receipt,
      body: {'selected_bank_payment_mode': paymentModeId},
    );

    final result = ReceiptBankResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Looks up an active bill (estimate) by its printed number, for the
  /// "Bill Number" field on Billwise Payment. Only called now as a
  /// one-time backward-compat fallback — the Add Receipt form's Bill
  /// Number field is read-only and only ever prefilled from the Estimate
  /// list's Receipt icon (`EstimationController.payReceipt`), which
  /// always knows the source estimate's own id and so uses
  /// [lookupBillByEstimateId] instead, entirely offline. Throws with the
  /// server's own message (`"Empty Estimate"` / `"Invalid Estimate"`)
  /// when not found.
  Future<ReceiptBillLookupResponseModel> lookupBill(String billNumber) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.receipt,
      body: {'payment_bill_number': billNumber},
    );

    final result = ReceiptBillLookupResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  static String _stripHtml(String raw) => raw.replaceAll(RegExp(r'<[^>]*>'), '');

  /// Finds [estimateId] in the same estimation cache the Estimate list
  /// itself reads (Active tab, plus anything still only sitting in the
  /// estimate pending-sync queue, matched by that queue entry's own
  /// `local_id` — the same id `EstimationModel.id` exposes for a
  /// not-yet-synced row — since an estimate created offline and not yet
  /// synced can still be paid against) and returns its party/total,
  /// entirely offline. This is what backs the read-only Bill Number field
  /// on Add Receipt now — no network call, no dependency on
  /// `EstimateRepository` itself, just the shared cache keys both
  /// repositories already agree on.
  ///
  /// Throws [ApiRequestException] with the same wording the server would
  /// use (`"Invalid Estimate"`) if the id isn't found in either place —
  /// e.g. a very stale cache from before the estimate was last synced.
  ReceiptBillLookupResponseModel lookupBillByEstimateId(String estimateId) {
    Map<String, dynamic>? findIn(String cacheKey, String idKey) {
      for (final row in _cache.getJsonList(cacheKey)) {
        if (row[idKey]?.toString() == estimateId) return row;
      }
      return null;
    }

    final row = findIn(CacheKeys.estimationActive, 'estimate_id') ??
        findIn(CacheKeys.estimationPending, 'local_id');

    if (row == null) {
      throw const ApiRequestException('Invalid Estimate');
    }

    final party = _stripHtml(row['party_name_mobile_city']?.toString() ??
            row['party_name']?.toString() ??
            '')
        .trim();

    // A synced row carries the server's own `grand_total`; a
    // not-yet-synced pending row doesn't have one yet (see
    // `EstimateListItem.fromPendingRow`'s `grandTotal: 0` comment) — the
    // form only needs a total to show/validate against, so recompute it
    // from the pending row's own product/section/charge fields the same
    // way `EstimationModel.total` would.
    double total;
    final rawGrandTotal = row['grand_total'];
    if (rawGrandTotal != null && double.tryParse(rawGrandTotal.toString()) != null &&
        double.parse(rawGrandTotal.toString()) != 0) {
      total = double.parse(rawGrandTotal.toString());
    } else {
      total = _recomputePendingEstimateTotal(row);
    }

    return ReceiptBillLookupResponseModel(
      code: 200,
      message: 'Loaded from offline data',
      estimateNumber: row['estimate_number']?.toString() ?? '',
      party: party.isEmpty ? 'Direct' : party,
      totalAmount: total,
    );
  }

  /// Best-effort grand-total recompute for a pending (not-yet-synced)
  /// estimate row — product line amounts plus both sections'
  /// add/discount plus charges, mirroring `EstimationModel.total`.
  double _recomputePendingEstimateTotal(Map<String, dynamic> row) {
    double subTotal = 0;
    final rawProducts = row['product_data'];
    if (rawProducts is List) {
      for (final p in rawProducts) {
        if (p is Map) {
          final qty = double.tryParse(p['product_quantity']?.toString() ?? '') ?? 0;
          final rate = double.tryParse(p['product_rate']?.toString() ?? '') ?? 0;
          subTotal += qty * rate;
        }
      }
    }
    double section1Add = double.tryParse(row['section1_add_value']?.toString() ?? '') ?? 0;
    double section1Discount = double.tryParse(row['section1_discount']?.toString() ?? '') ?? 0;
    double section2Add = double.tryParse(row['section2_add_value']?.toString() ?? '') ?? 0;
    double section2Discount = double.tryParse(row['section2_discount']?.toString() ?? '') ?? 0;
    double chargesTotal = 0;
    final rawCharges = row['charges'];
    if (rawCharges is List) {
      for (final c in rawCharges) {
        if (c is Map) {
          final value = double.tryParse(c['other_charges_value']?.toString() ?? '') ?? 0;
          final isMinus = c['other_charges_type']?.toString() == 'Minus';
          chargesTotal += isMinus ? -value.abs() : value.abs();
        }
      }
    }
    return subTotal +
        (section1Add - section1Discount) +
        (section2Add - section2Discount) +
        chargesTotal;
  }

  /// Current balance for a chosen payment mode/bank/account — the
  /// "Account Balance : ..." helper text shown next to the Amount field.
  Future<ReceiptBalanceResponseModel> getAccountBalance(
    String accountBalanceId,
  ) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.receipt,
      body: {'account_balance_id': accountBalanceId},
    );

    final result = ReceiptBalanceResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Returns a page of the Receipt list — always from the offline cache
  /// that [DataSyncService]/the Sync button populate, regardless of
  /// whether the device currently has internet.
  ///
  /// [cancelled] selects which tab's rows come back (Receipts have no
  /// Draft tab, just Active/Cancel) — pass `'1'`/`'0'` explicitly, same
  /// as the cache is stored per-tab.
  ///
  /// The only thing that ever calls the live `receipt_listing` endpoint
  /// is a manual tap of the Sync button (`DataSyncService.syncReceipts`),
  /// which fetches the full, unpaginated list for both tabs. Browsing the
  /// list itself never hits the network — this keeps behavior identical
  /// online and offline and means a flaky connection can never cause a
  /// half-loaded list or an unexpectedly slow screen while just looking
  /// at data.
  Future<ReceiptListResponseModel> listReceipts({
    String filterFromDate = '',
    String filterToDate = '',
    String searchText = '',
    String filterPartyId = '',
    String cancelled = '0',
    int? pageNumber,
    int? pageLimit,
  }) async {
    return _receiptsFromCache(
      cancelled: cancelled,
      filterFromDate: filterFromDate,
      filterToDate: filterToDate,
      searchText: searchText,
      filterPartyId: filterPartyId,
      pageNumber: pageNumber,
      pageLimit: pageLimit,
    );
  }

  /// Calls the live `receipt_listing` endpoint directly, no cache
  /// fallback. This is the *only* method in the app that ever does — used
  /// exclusively by [DataSyncService] (both the post-login full sync and
  /// the per-page Sync button), to refresh the offline cache that
  /// [listReceipts] reads from. Throws on failure exactly like any other
  /// API call here; [DataSyncService] is what catches and reports it.
  Future<ReceiptListResponseModel> fetchLiveReceipts({
    String filterFromDate = '',
    String filterToDate = '',
    String searchText = '',
    String filterPartyId = '',
    String cancelled = '0',
    int? pageNumber,
    int? pageLimit,
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.receipt,
      body: {
        'receipt_listing': '1',
        'filter_from_date': filterFromDate,
        'filter_to_date': filterToDate,
        'search_text': searchText,
        'filter_party_id': filterPartyId,
        'cancelled': cancelled,
        if (pageNumber != null) 'page_number': pageNumber.toString(),
        if (pageLimit != null) 'page_limit': pageLimit.toString(),
      },
    );

    final result = ReceiptListResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// [cancelled] picks which cached tab snapshot to read from —
  /// [DataSyncService] stores Active/Cancel separately (Receipts have no
  /// Draft tab), the same split the server's `cancelled` flag produces.
  /// Returns every cached row matching the given filters, unpaginated —
  /// merged with anything still sitting in the receipt pending-sync
  /// queue, which (Receipts having no draft/cancel state of their own)
  /// always shows under the Active tab, same as `EstimateRepository`'s
  /// equivalent merge.
  List<ReceiptListItem> _filterCachedReceipts({
    required String cancelled,
    required String filterFromDate,
    required String filterToDate,
    required String searchText,
    required String filterPartyId,
  }) {
    final cacheKey =
        cancelled == '1' ? CacheKeys.receiptCancel : CacheKeys.receiptActive;

    final pending = cancelled == '1'
        ? const <ReceiptListItem>[]
        : _cache
            .getJsonList(CacheKeys.receiptPending)
            .map(ReceiptListItem.fromPendingRow)
            .toList()
            .reversed
            .toList();

    final synced = _cache
        .getJsonList(cacheKey)
        .map(ReceiptListItem.fromJson)
        .toList();

    final all = [...pending, ...synced];

    final partyList = _cache
        .getJsonList(CacheKeys.receiptParties)
        .map((m) => IdName(
              id: m['id']?.toString() ?? '',
              name: m['name']?.toString() ?? '',
            ))
        .toList();

    String? nameForId(List<IdName> options, String id) {
      for (final o in options) {
        if (o.id == id) return o.name;
      }
      return null;
    }

    final partyName =
        filterPartyId.isEmpty ? null : nameForId(partyList, filterPartyId);

    return all.where((r) {
      if (!matchesDateRange(r.receiptDate, filterFromDate, filterToDate)) {
        return false;
      }
      if (partyName != null &&
          !r.partyName.toLowerCase().contains(partyName.toLowerCase())) {
        return false;
      }
      return matchesSearch(searchText, [
        r.receiptNumber,
        r.partyName,
        r.agentName,
      ]);
    }).toList();
  }

  ReceiptListResponseModel _receiptsFromCache({
    required String cancelled,
    required String filterFromDate,
    required String filterToDate,
    required String searchText,
    required String filterPartyId,
    required int? pageNumber,
    required int? pageLimit,
  }) {
    final filtered = _filterCachedReceipts(
      cancelled: cancelled,
      filterFromDate: filterFromDate,
      filterToDate: filterToDate,
      searchText: searchText,
      filterPartyId: filterPartyId,
    );

    final partyList = _cache
        .getJsonList(CacheKeys.receiptParties)
        .map((m) => IdName(
              id: m['id']?.toString() ?? '',
              name: m['name']?.toString() ?? '',
            ))
        .toList();

    return ReceiptListResponseModel(
      code: 200,
      message: 'Loaded from offline data',
      items: paginate(filtered, pageNumber, pageLimit),
      partyList: partyList,
      totalRecords: filtered.length,
    );
  }

  /// Creates a new Billwise Payment receipt against [againstBillNumber].
  /// [entries] becomes the three parallel `payment_mode_id` / `bank_id` /
  /// `amount` arrays exactly as captured in the Postman example.
  Future<ReceiptSaveResponseModel> saveReceipt({
    required String creator,
    required String receiptDate, // dd-MM-yyyy
    required String againstBillNumber,
    String deduction = '',
    String narration = '',
    required List<ReceiptPaymentEntry> entries,
  }) async {
    final body = <String, dynamic>{
      'receipt_update': '1',
      'creator': creator,
      'receipt_date': receiptDate,
      'against_bill_number': againstBillNumber,
      'deduction': deduction,
      'narration': narration,
      'payment_mode_id': entries.map((e) => e.paymentModeId).toList(),
      'bank_id': entries.map((e) => e.bankId).toList(),
      'amount': entries.map((e) => e.amount).toList(),
    };

    final json = await _apiClient.postJson(ApiEndpoints.receipt, body: body);

    final result = ReceiptSaveResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Queues a new Billwise Payment receipt on this device instead of
  /// calling `receipt.php` directly — the same offline-first shape every
  /// other "Add/Edit" flow in the app uses (see
  /// `EstimateRepository.queueEstimateForSync`). Only a manual tap of the
  /// Sync button ever actually sends this to the server (see
  /// [syncPendingReceipts]).
  ///
  /// [estimateId] is the source estimate's own id (see
  /// `EstimationController.payReceipt`) — stored purely so
  /// [markEstimateLocallyConverted] and [reapplyPendingConversions] know
  /// which estimate row to flip `isConverted` on; it's never sent to
  /// `receipt.php` itself, which only ever takes the bill *number*.
  Future<void> queueReceiptForSync({
    required String localId,
    required String estimateId,
    required String receiptNumber,
    required String billNumber,
    required String partyName,
    String agentName = 'Direct',
    required String receiptDate, // dd-MM-yyyy
    required String receiptDateIso, // yyyy-MM-dd, for offline date filters
    String deduction = '',
    String narration = '',
    required double totalAmount,
    required List<ReceiptPaymentEntry> entries,
  }) async {
    final pending = _cache.getJsonList(CacheKeys.receiptPending);
    final row = <String, dynamic>{
      'local_id': localId,
      'estimate_id': estimateId,
      'receipt_number': receiptNumber,
      'bill_number': billNumber,
      'party_name': partyName,
      'agent_name': agentName,
      'receipt_date': receiptDate,
      'receipt_date_iso': receiptDateIso,
      'deduction': deduction,
      'narration': narration,
      'total_amount': totalAmount,
      'entries': entries.map((e) => e.toJson()).toList(),
    };
    final updated = [
      ...pending.where((p) => p['local_id'] != localId),
      row,
    ];
    await _cache.putJsonList(CacheKeys.receiptPending, updated);

    if (estimateId.isNotEmpty) {
      await markEstimateLocallyConverted(
        estimateId: estimateId,
        localReceiptId: localId,
      );
    }
  }

  /// Cancels a Receipt that's still only sitting in the pending-sync
  /// queue — entirely offline, since it was never sent to `receipt.php`
  /// in the first place. Un-marks the source estimate's `receipt_id` too
  /// (only if it's still exactly this queue entry's [localId] — never
  /// clobbers a real server-assigned `receipt_id` that might have landed
  /// there in the meantime), so its Receipt/Edit icons come back
  /// immediately: the conversion never actually happened.
  Future<void> removePendingReceipt(String localId) async {
    final pending = _cache.getJsonList(CacheKeys.receiptPending);
    Map<String, dynamic>? row;
    for (final p in pending) {
      if (p['local_id'] == localId) {
        row = p;
        break;
      }
    }
    await _cache.putJsonList(
      CacheKeys.receiptPending,
      pending.where((p) => p['local_id'] != localId).toList(),
    );

    final estimateId = row?['estimate_id']?.toString() ?? '';
    if (estimateId.isEmpty) return;

    Future<void> unmark(String cacheKey, String idKey) async {
      final rows = _cache.getJsonList(cacheKey);
      var changed = false;
      for (final r in rows) {
        if (r[idKey]?.toString() == estimateId &&
            r['receipt_id']?.toString() == localId) {
          r['receipt_id'] = '';
          changed = true;
        }
      }
      if (changed) await _cache.putJsonList(cacheKey, rows);
    }

    await unmark(CacheKeys.estimationActive, 'estimate_id');
    await unmark(CacheKeys.estimationPending, 'local_id');
  }

  /// Stamps [estimateId]'s cached row — wherever it currently sits: the
  /// synced Active tab, or the estimate's own pending-sync queue if the
  /// estimate itself hasn't been sent to the server yet — with a
  /// non-empty `receipt_id`, so `EstimationModel.isConverted` flips (and
  /// the Estimate list's Receipt/Edit icons hide) the moment a Receipt is
  /// queued against it, offline included, without waiting for either
  /// side to actually sync. A real sync later overwrites this with the
  /// server's own `receipt_id` once the receipt is actually created; see
  /// [reapplyPendingConversions] for why that overwrite is guarded
  /// against happening too early.
  Future<void> markEstimateLocallyConverted({
    required String estimateId,
    required String localReceiptId,
  }) async {
    Future<void> patch(String cacheKey, String idKey) async {
      final rows = _cache.getJsonList(cacheKey);
      var changed = false;
      for (final row in rows) {
        if (row[idKey]?.toString() == estimateId &&
            (row['receipt_id']?.toString() ?? '').isEmpty) {
          row['receipt_id'] = localReceiptId;
          changed = true;
        }
      }
      if (changed) await _cache.putJsonList(cacheKey, rows);
    }

    await patch(CacheKeys.estimationActive, 'estimate_id');
    await patch(CacheKeys.estimationPending, 'local_id');
  }

  /// Safety net called after `DataSyncService` re-pulls a fresh estimate
  /// list from the server: a fresh `estimate_listing` pull only reflects
  /// a receipt that's *itself* already synced, so an estimate paid
  /// offline but not yet synced from the Receipt side would otherwise
  /// have its locally-set `receipt_id` wiped back to empty by that fresh
  /// pull — briefly un-hiding the Receipt/Edit icons until the next Sync.
  /// Re-applies every entry still sitting in the receipt pending-sync
  /// queue, so the icons stay hidden continuously from the moment the
  /// Receipt was created until the server actually confirms it.
  Future<void> reapplyPendingConversions() async {
    final pending = _cache.getJsonList(CacheKeys.receiptPending);
    for (final row in pending) {
      final estimateId = row['estimate_id']?.toString() ?? '';
      final localId = row['local_id']?.toString() ?? '';
      if (estimateId.isEmpty || localId.isEmpty) continue;
      await markEstimateLocallyConverted(
        estimateId: estimateId,
        localReceiptId: localId,
      );
    }
  }

  /// Number of Receipts created on this device that haven't been sent to
  /// the server yet.
  int get pendingReceiptCount =>
      _cache.getJsonList(CacheKeys.receiptPending).length;

  /// Sends every queued Receipt to `receipt.php` one at a time — unlike
  /// Estimate/Quotation's single-batch `_data: [...]` call, `receipt_update`
  /// only ever takes one bill at a time (see [saveReceipt]). Only ever
  /// called from the Sync button (via `DataSyncService`), and only while
  /// online.
  ///
  /// Each entry is removed from the queue as soon as *that* entry
  /// succeeds, so a later failure in the same batch never re-sends
  /// receipts that already went through. If any entry fails, the
  /// exception is rethrown after the loop so `DataSyncService` reports
  /// the sync as failed and retries the remaining queue next time — but
  /// whatever already succeeded stays synced.
  Future<void> syncPendingReceipts({required String creator}) async {
    final pending = _cache.getJsonList(CacheKeys.receiptPending);
    if (pending.isEmpty) return;

    Object? firstError;
    for (final row in pending) {
      final localId = row['local_id']?.toString() ?? '';
      try {
        final rawEntries = row['entries'];
        final entries = <ReceiptPaymentEntry>[
          if (rawEntries is List)
            for (final e in rawEntries)
              if (e is Map) ReceiptPaymentEntry.fromJson(Map<String, dynamic>.from(e)),
        ];

        await saveReceipt(
          creator: creator,
          receiptDate: row['receipt_date']?.toString() ?? '',
          againstBillNumber: row['bill_number']?.toString() ?? '',
          deduction: row['deduction']?.toString() ?? '',
          narration: row['narration']?.toString() ?? '',
          entries: entries,
        );

        final stillPending = _cache.getJsonList(CacheKeys.receiptPending);
        await _cache.putJsonList(
          CacheKeys.receiptPending,
          stillPending.where((p) => p['local_id'] != localId).toList(),
        );
      } catch (e) {
        firstError ??= e;
      }
    }

    if (firstError != null) throw firstError;
  }

  /// Deletes/cancels a receipt (soft-void — payment entries are reversed
  /// server-side). There is no "restore" — matches the Receipt list only
  /// ever showing active rows.
  Future<ReceiptDeleteResponseModel> deleteReceipt({
    required String receiptId,
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.receipt,
      body: {'delete_receipt_id': receiptId},
    );

    final result = ReceiptDeleteResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }
}