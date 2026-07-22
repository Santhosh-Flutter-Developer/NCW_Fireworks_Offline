/// Key names used in [LocalCacheService] for everything [DataSyncService]
/// pulls down after a successful online login. Centralized here so the
/// sync side (writes) and the future offline-read side (repositories
/// reading cache-first) always agree on the same keys.
class CacheKeys {
  CacheKeys._();

  static const party = 'party_list';

  /// Queue of Party adds/edits made on this device that haven't been sent
  /// to `party.php` yet. Every save from the Party form — create or edit,
  /// online or offline — lands here first; only a manual tap of the Sync
  /// button ever drains it (see [PartyRepository.queuePartyForSync] /
  /// [PartyRepository.syncPendingParties]).
  static const partyPending = 'party_pending';

  static const priceRows = 'price_list_rows';
  static const priceLists = 'price_list_options';
  static const priceProducts = 'price_list_products';

  static const quotationActive = 'quotation_active';
  static const quotationDraft = 'quotation_draft';
  static const quotationCancel = 'quotation_cancel';
  static const quotationParties = 'quotation_parties';

  static const estimationActive = 'estimation_active';
  static const estimationDraft = 'estimation_draft';
  static const estimationCancel = 'estimation_cancel';
  static const estimationAgents = 'estimation_agents';
  static const estimationParties = 'estimation_parties';

  static const receiptActive = 'receipt_active';
  static const receiptCancel = 'receipt_cancel';
  static const receiptParties = 'receipt_parties';

  /// ISO-8601 timestamp string of the last time [DataSyncService.syncAll]
  /// completed (even if some individual steps failed).
  static const lastSyncedAt = 'meta_last_synced_at';
}