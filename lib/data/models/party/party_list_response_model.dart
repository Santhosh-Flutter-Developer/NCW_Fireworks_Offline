import '../../../core/network/api_exception.dart';

/// One row from `party_list` in a `party_listing` response.
///
/// The endpoint only returns these three fields per row — notably no
/// phone/email/address/district/city/GST/balance — so a row built from
/// this can't be safely round-tripped through an edit+save without
/// wiping those other fields server-side. Callers should mark whatever
/// they build from this as "not fully known" (see
/// `PartyModel.hasFullDetails`).
class PartyListItem {
  final String partyId;
  final String partyName;
  final String state;

  const PartyListItem({
    required this.partyId,
    required this.partyName,
    required this.state,
  });

  factory PartyListItem.fromJson(Map<String, dynamic> json) {
    return PartyListItem(
      partyId: json['party_id']?.toString() ?? '',
      partyName: json['party_name']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
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
