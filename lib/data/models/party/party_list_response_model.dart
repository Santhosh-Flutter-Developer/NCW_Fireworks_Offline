import '../../../core/network/api_exception.dart';

/// One row from `party_list` in a `party_listing` response — or, when
/// [isPending] is true, one row built from the on-device pending-sync
/// queue ([CacheKeys.partyPending]) instead.
///
/// `party_listing` actually returns every field below per row (agent,
/// contact, address, GST, opening balance, ...), so a row parsed via
/// [fromJson] carries full details as long as [hasFullDetails] is true —
/// that flag is only false for rows cached by an older build of this app
/// that stored just id/name/state; those still need a `show_party_id`
/// fetch before they can be edited safely (see `PartyController.startEdit`).
/// A pending row (built via [fromPendingRow]) always has full details —
/// it was typed in on this device, nothing to fetch.
class PartyListItem {
  final String partyId;
  final String partyName;
  final String state;

  /// True for a row sourced from the pending-sync queue rather than the
  /// synced `party_list` cache — i.e. an add/edit made on this device
  /// that hasn't been sent to the server yet.
  final bool isPending;

  /// For a pending row, the queue entry's own id — used to find/replace
  /// this exact entry later (re-editing before sync, or removing it).
  /// Empty for a synced row.
  final String localId;

  final String agentId;
  final String agentName;
  final String mobileNumber;
  final String email;
  final String identification;
  final String address;
  final String district;
  final String city;
  final String othersCity;
  final String pincode;
  final String gstNumber;
  final String openingBalance;
  final String openingBalanceType;
  final bool isDraft;

  /// Whether every field above is actually known for this row. True for
  /// every pending row and every freshly-synced row; false only for a
  /// row cached before this app version started storing full details
  /// (see the `_full` marker in [DataSyncService]).
  final bool hasFullDetails;

  const PartyListItem({
    required this.partyId,
    required this.partyName,
    required this.state,
    this.isPending = false,
    this.localId = '',
    this.agentId = '',
    this.agentName = '',
    this.mobileNumber = '',
    this.email = '',
    this.identification = '',
    this.address = '',
    this.district = '',
    this.city = '',
    this.othersCity = '',
    this.pincode = '',
    this.gstNumber = '',
    this.openingBalance = '',
    this.openingBalanceType = '',
    this.isDraft = false,
    this.hasFullDetails = false,
  });

  factory PartyListItem.fromJson(Map<String, dynamic> json) {
    return PartyListItem(
      partyId: json['party_id']?.toString() ?? '',
      partyName: json['party_name']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      agentId: json['agent_id']?.toString() ?? '',
      agentName: json['agent_name']?.toString() ?? '',
      mobileNumber: json['mobile_number']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      identification: json['identification']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      district: json['district']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      othersCity: json['others_city']?.toString() ?? '',
      pincode: json['pincode']?.toString() ?? '',
      gstNumber: json['gst_number']?.toString() ?? '',
      openingBalance: json['opening_balance']?.toString() ?? '',
      openingBalanceType: json['opening_balance_type']?.toString() ?? '',
      isDraft: json['draft']?.toString() == '1',
      hasFullDetails: json['_full'] == true,
    );
  }

  /// Builds a row from one entry of the pending-sync queue (the same
  /// shape [PartyRepository.queuePartyForSync] writes). [partyId] here is
  /// the row's `edit_id` — empty for a brand-new party not yet on the
  /// server, or the real server id when this is a queued edit of an
  /// already-synced party.
  factory PartyListItem.fromPendingRow(Map<String, dynamic> row) {
    return PartyListItem(
      partyId: row['edit_id']?.toString() ?? '',
      partyName: row['party_name']?.toString() ?? '',
      state: row['state']?.toString() ?? '',
      isPending: true,
      localId: row['local_id']?.toString() ?? '',
      agentId: row['agent_id']?.toString() ?? '',
      mobileNumber: row['mobile_number']?.toString() ?? '',
      email: row['email']?.toString() ?? '',
      identification: row['identification']?.toString() ?? '',
      address: row['address']?.toString() ?? '',
      district: row['district']?.toString() ?? '',
      city: row['city']?.toString() ?? '',
      othersCity: row['others_city']?.toString() ?? '',
      pincode: row['pincode']?.toString() ?? '',
      gstNumber: row['gst_number']?.toString() ?? '',
      openingBalance: row['opening_balance']?.toString() ?? '',
      openingBalanceType: row['opening_balance_type']?.toString() ?? '',
      hasFullDetails: true,
    );
  }
}

/// Parses the `{"head": {...}}` envelope returned for a `party_listing`
/// call. The sample response we have access to doesn't show a total
/// row/page count anywhere in `head`, so [totalCount] is left null when
/// none of the common field names are present — callers fall back to
/// inferring "is there a next page" from whether a full page of rows
/// came back.
class PartyListResponseModel {
  final int code;
  final String message;
  final List<PartyListItem> items;

  /// Total number of rows across all pages, when the server tells us —
  /// checked under a few common field-name guesses (see fromJson). Use
  /// this together with the page limit to compute total pages.
  final int? totalRecords;

  /// Total number of *pages*, when the server tells us directly (as
  /// opposed to a row count we'd have to divide ourselves).
  final int? totalPages;

  const PartyListResponseModel({
    required this.code,
    required this.message,
    required this.items,
    this.totalRecords,
    this.totalPages,
  });

  bool get isSuccess => code == 200;

  factory PartyListResponseModel.fromJson(Map<String, dynamic> json) {
    final head = json['head'];
    if (head is! Map) {
      throw const InvalidResponseException(
        'Server response was missing the expected "head" field.',
      );
    }

    final rawCode = head['code'];
    final code = rawCode is int
        ? rawCode
        : int.tryParse(rawCode?.toString() ?? '') ?? -1;

    final rawMsg = head['msg'];
    final message = (rawMsg is String && rawMsg.trim().isNotEmpty)
        ? rawMsg.trim()
        : 'Unexpected response from server.';

    final rawList = head['party_list'];
    final items = <PartyListItem>[];
    if (rawList is List) {
      for (final row in rawList) {
        if (row is Map<String, dynamic>) {
          items.add(PartyListItem.fromJson(row));
        } else if (row is Map) {
          items.add(PartyListItem.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }

    int? readInt(String key) {
      final raw = head[key];
      if (raw == null) return null;
      return raw is int ? raw : int.tryParse(raw.toString());
    }

    final totalPages = readInt('total_pages') ?? readInt('page_count');
    final totalRecords = readInt('total_count') ??
        readInt('total_records') ??
        readInt('total') ??
        readInt('count');

    return PartyListResponseModel(
      code: code,
      message: message,
      items: items,
      totalRecords: totalRecords,
      totalPages: totalPages,
    );
  }
}