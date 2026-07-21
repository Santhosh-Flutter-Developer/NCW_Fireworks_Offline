import 'dart:developer' as developer;

import 'package:get/get.dart';

import '../../data/respositories/estimate_repository.dart';
import '../../data/respositories/party_repository.dart';
import '../../data/respositories/product_price_repository.dart';
import '../../data/respositories/quotation_repository.dart';
import '../../data/respositories/receipt_repository.dart';
import 'cache_keys.dart';
import 'local_cache_service.dart';

/// Pulls the Party / Price Upload / Quotation / Estimation / Receipt
/// lists down from the API and caches them locally.
///
/// This is now the *only* place in the app that ever calls those five
/// list endpoints live. Every list screen's own repository method
/// (`listParties`, `fetchPriceList`, `listQuotations`, `listEstimates`,
/// `listReceipts`) always reads from the offline cache this service
/// populates — online or offline, it makes no difference. Each
/// repository also exposes a `fetchLiveXxx` twin (`fetchLiveParties`,
/// `fetchLivePriceList`, etc.) that actually hits the network; those are
/// used exclusively here, never by a list screen directly.
///
/// Runs in two ways:
/// - [syncAll] — every section, in order — once, right after a
///   *successful online* login (see `LoginController`).
/// - The per-page Sync button — one section at a time (`syncParty`,
///   `syncPriceList`, `syncQuotations`, `syncEstimations`,
///   `syncReceipts`), whenever the person taps it while online.
///
/// Every list endpoint here is server-paginated, but sync deliberately
/// never sends `page_number`/`page_limit` at all — the `fetchLiveXxx`
/// methods treat both as optional and, when omitted, the endpoint
/// returns its full list in one shot. This is exactly the "full list,
/// no pagination" mode the backend is moving towards for sync callers;
/// once every endpoint is confirmed to support it, nothing else here
/// needs to change.
///
/// A single section failing (timeout, server hiccup mid-sync, etc.)
/// never throws out of [syncAll] — the user is already validly logged in
/// by the time this runs, so the worst case is "some lists are stale",
/// not "login is broken". [lastError] surfaces the most recent failure
/// for anyone who wants to show a subtle warning.
class DataSyncService extends GetxService {
  DataSyncService({
    PartyRepository? partyRepository,
    ProductPriceRepository? productPriceRepository,
    QuotationRepository? quotationRepository,
    EstimateRepository? estimateRepository,
    ReceiptRepository? receiptRepository,
    LocalCacheService? cache,
  })  : _partyRepository = partyRepository ?? PartyRepository(),
        _productPriceRepository =
            productPriceRepository ?? ProductPriceRepository(),
        _quotationRepository = quotationRepository ?? QuotationRepository(),
        _estimateRepository = estimateRepository ?? EstimateRepository(),
        _receiptRepository = receiptRepository ?? ReceiptRepository(),
        _cache = cache ?? Get.find<LocalCacheService>();

  final PartyRepository _partyRepository;
  final ProductPriceRepository _productPriceRepository;
  final QuotationRepository _quotationRepository;
  final EstimateRepository _estimateRepository;
  final ReceiptRepository _receiptRepository;
  final LocalCacheService _cache;

  final isSyncing = false.obs;
  final statusMessage = ''.obs;
  final RxnString lastError = RxnString();

  /// Runs the full sync — every section, in order. Intended to run exactly
  /// once, right after a successful online login (see `LoginController`).
  /// Per-module sync buttons on each list screen should call their own
  /// `syncXxx()` method below instead of this, so tapping "Sync" on, say,
  /// the Quotation page doesn't also re-pull Party/Price List/Estimation/
  /// Receipt in the background.
  Future<void> syncAll() async {
    if (isSyncing.value) return;
    isSyncing.value = true;
    lastError.value = null;
    try {
      await _runStep('Syncing parties…', _syncParties);
      await _runStep('Syncing price list…', _syncPriceList);
      await _runStep('Syncing quotations…', _syncQuotations);
      await _runStep('Syncing estimations…', _syncEstimations);
      await _runStep('Syncing receipts…', _syncReceipts);
      await _cache.putString(
        CacheKeys.lastSyncedAt,
        DateTime.now().toIso8601String(),
      );
    } finally {
      isSyncing.value = false;
      statusMessage.value = '';
    }
  }

  /// Re-syncs only the Party list's offline cache — used by the Sync
  /// button on the Party screen.
  Future<void> syncParty() =>
      _syncOne('Syncing parties…', _syncParties);

  /// Re-syncs only the Price List's offline cache — used by the Sync
  /// button on the Price Upload screen.
  Future<void> syncPriceList() =>
      _syncOne('Syncing price list…', _syncPriceList);

  /// Re-syncs only the Quotation list's offline cache (all three tabs) —
  /// used by the Sync button on the Quotation screen.
  Future<void> syncQuotations() =>
      _syncOne('Syncing quotations…', _syncQuotations);

  /// Re-syncs only the Estimation list's offline cache (all three tabs) —
  /// used by the Sync button on the Estimate screen.
  Future<void> syncEstimations() =>
      _syncOne('Syncing estimations…', _syncEstimations);

  /// Re-syncs only the Receipt list's offline cache (both tabs) — used by
  /// the Sync button on the Receipt screen.
  Future<void> syncReceipts() =>
      _syncOne('Syncing receipts…', _syncReceipts);

  /// Shared guard/cleanup around a single-module sync — mirrors
  /// [syncAll]'s isSyncing/lastError/statusMessage handling, but for just
  /// one section instead of all five. Doesn't touch [CacheKeys.lastSyncedAt]
  /// since that's meant to reflect a *full* sync, not a partial one.
  Future<void> _syncOne(String label, Future<void> Function() step) async {
    if (isSyncing.value) return;
    isSyncing.value = true;
    lastError.value = null;
    try {
      await _runStep(label, step);
    } finally {
      isSyncing.value = false;
      statusMessage.value = '';
    }
  }

  Future<void> _runStep(String label, Future<void> Function() step) async {
    statusMessage.value = label;
    try {
      await step();
    } catch (e, st) {
      lastError.value = e.toString();
      developer.log(
        'Offline sync step failed: $label',
        error: e,
        stackTrace: st,
        name: 'DataSyncService',
      );
    }
  }

  /// Updates [statusMessage] with exactly what's being synced right now
  /// (e.g. "Syncing quotations — Draft"), for the top status strip in
  /// [AppScaffold] to display while [isSyncing] is true.
  void _announce(String message) {
    statusMessage.value = message;
  }

  Future<void> _syncParties() async {
    _announce('Syncing parties');
    final result = await _partyRepository.fetchLiveParties();
    final items = result.items
        .map((p) => {
              'party_id': p.partyId,
              'party_name': p.partyName,
              'state': p.state,
            })
        .toList();
    await _cache.putJsonList(CacheKeys.party, items);
  }

  Future<void> _syncPriceList() async {
    _announce('Syncing price list');
    final pricelists = <String, Map<String, dynamic>>{};
    final products = <String, Map<String, dynamic>>{};
    final result = await _productPriceRepository.fetchLivePriceList();
    final rows = result.rows
        .map((r) => {
              'sno': r.sno,
              'pricelist_name': r.pricelistName,
              'product_name': r.productName,
              'price': r.price,
              'price_unit_name': r.unit,
              'discount': r.discountEnabled ? 'ON' : 'OFF',
            })
        .toList();
    for (final p in result.pricelists) {
      pricelists[p.id] = {'pricelist_id': p.id, 'pricelist_name': p.name};
    }
    for (final p in result.products) {
      products[p.id] = {'product_id': p.id, 'product_name': p.name};
    }
    await _cache.putJsonList(CacheKeys.priceRows, rows);
    await _cache.putJsonList(
        CacheKeys.priceLists, pricelists.values.toList());
    await _cache.putJsonList(CacheKeys.priceProducts, products.values.toList());
  }

  Future<void> _syncQuotations() async {
    final parties = <String, Map<String, dynamic>>{};

    Future<void> syncTab(
      String cacheKey,
      String tabLabel, {
      required String drafted,
      required String cancelled,
    }) async {
      _announce('Syncing quotations — $tabLabel');
      final result = await _quotationRepository.fetchLiveQuotations(
        drafted: drafted,
        cancelled: cancelled,
      );
      final items = result.items
          .map((q) => {
                'quotation_id': q.quotationId,
                'quotation_number': q.quotationNumber,
                'quotation_date': q.quotationDate,
                'party_name_mobile_city': q.partyNameMobileCity,
                'total_quantity': q.totalQuantity,
                'grand_total': q.grandTotal,
                'estimate_id': q.estimateId,
              })
          .toList();
      for (final p in result.partyList) {
        parties[p.id] = {'id': p.id, 'name': p.name};
      }
      await _cache.putJsonList(cacheKey, items);
    }

    // Same three tabs as the Quotation list screen: Active, Draft, Cancel.
    await syncTab(CacheKeys.quotationActive, 'Active',
        drafted: '0', cancelled: '0');
    await syncTab(CacheKeys.quotationDraft, 'Draft',
        drafted: '1', cancelled: '0');
    await syncTab(CacheKeys.quotationCancel, 'Cancelled',
        drafted: '0', cancelled: '1');
    await _cache.putJsonList(
        CacheKeys.quotationParties, parties.values.toList());
  }

  Future<void> _syncEstimations() async {
    final agents = <String, Map<String, dynamic>>{};
    final parties = <String, Map<String, dynamic>>{};

    Future<void> syncTab(
      String cacheKey,
      String tabLabel, {
      required String drafted,
      required String cancelled,
    }) async {
      _announce('Syncing estimations — $tabLabel');
      final result = await _estimateRepository.fetchLiveEstimates(
        drafted: drafted,
        cancelled: cancelled,
      );
      final items = result.items
          .map((e) => {
                'estimate_id': e.estimateId,
                'estimate_number': e.estimateNumber,
                'estimate_date': e.estimateDate,
                'agent_name_mobile_city': e.agentNameMobileCity,
                'party_name_mobile_city': e.partyNameMobileCity,
                'total_quantity': e.totalQuantity,
                'grand_total': e.grandTotal,
                'receipt_id': e.receiptId,
              })
          .toList();
      for (final a in result.agentList) {
        agents[a.id] = {'id': a.id, 'name': a.name};
      }
      for (final p in result.partyList) {
        parties[p.id] = {'id': p.id, 'name': p.name};
      }
      await _cache.putJsonList(cacheKey, items);
    }

    // Same three tabs as the Estimation list screen: Active, Draft, Cancel.
    await syncTab(CacheKeys.estimationActive, 'Active',
        drafted: '0', cancelled: '0');
    await syncTab(CacheKeys.estimationDraft, 'Draft',
        drafted: '1', cancelled: '0');
    await syncTab(CacheKeys.estimationCancel, 'Cancelled',
        drafted: '0', cancelled: '1');
    await _cache.putJsonList(
        CacheKeys.estimationAgents, agents.values.toList());
    await _cache.putJsonList(
        CacheKeys.estimationParties, parties.values.toList());
  }

  Future<void> _syncReceipts() async {
    final parties = <String, Map<String, dynamic>>{};

    Future<void> syncTab(
      String cacheKey,
      String tabLabel, {
      required String cancelled,
    }) async {
      _announce('Syncing receipts — $tabLabel');
      final result = await _receiptRepository.fetchLiveReceipts(
        cancelled: cancelled,
      );
      final items = result.items
          .map((r) => {
                'receipt_id': r.receiptId,
                'receipt_number': r.receiptNumber,
                'receipt_date': r.receiptDate,
                'agent_name': r.agentName,
                'party_name': r.partyName,
                'total_amount': r.totalAmount,
              })
          .toList();
      for (final p in result.partyList) {
        parties[p.id] = {'id': p.id, 'name': p.name};
      }
      await _cache.putJsonList(cacheKey, items);
    }

    // Receipts only have Active/Cancel — no draft state.
    await syncTab(CacheKeys.receiptActive, 'Active', cancelled: '0');
    await syncTab(CacheKeys.receiptCancel, 'Cancelled', cancelled: '1');
    await _cache.putJsonList(
        CacheKeys.receiptParties, parties.values.toList());
  }
}