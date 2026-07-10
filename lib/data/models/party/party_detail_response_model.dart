import '../../../core/network/api_exception.dart';

/// Parses the `{"head": {...}}` envelope returned for a `show_party_id`
/// call — full details for a single party, used to hydrate the Edit
/// form before letting the user save (the list endpoint only gives us
/// id/name/state, which isn't enough to edit safely).
///
/// Sample shape:
/// ```json
/// {
///   "head": {
///     "code": 200,
///     "msg": "",
///     "agent_id": "",
///     "party_name": "Mano Traders For Checking 1",
///     "mobile_number": 9786731501,
///     "email": "",
///     "address": "",
///     "state": "Tamil Nadu",
///     "district": "Madurai",
///     "city": "Madurai",
///     "pincode": 625003,
///     "identification": "",
///     "gst_number": "29GGGGG1314R9Z6",
///     "opening_balance": 5000,
///     "opening_balance_type": 2
///   }
/// }
/// ```
/// Note several fields come back as JSON numbers here even though the
/// create/update call sends them as strings — everything below is
/// parsed defensively (accepts either).
class PartyDetailResponseModel {
  final int code;
  final String message;
  final String agentId;
  final String partyName;
  final String mobileNumber;
  final String email;
  final String address;
  final String state;
  final String district;
  final String city;
  final String othersCity;
  final String pincode;
  final String identification;
  final String gstNumber;
  final double openingBalance;

  /// Raw `opening_balance_type` from the server (1 = Credit, 2 = Debit
  /// per the confirmed mapping) — null when there's no balance set.
  final int? openingBalanceType;

  const PartyDetailResponseModel({
    required this.code,
    required this.message,
    this.agentId = '',
    this.partyName = '',
    this.mobileNumber = '',
    this.email = '',
    this.address = '',
    this.state = '',
    this.district = '',
    this.city = '',
    this.othersCity = '',
    this.pincode = '',
    this.identification = '',
    this.gstNumber = '',
    this.openingBalance = 0,
    this.openingBalanceType,
  });

  bool get isSuccess => code == 200;

  static String _str(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    return s == 'null' ? '' : s;
  }

  factory PartyDetailResponseModel.fromJson(Map<String, dynamic> json) {
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

    final rawBalance = head['opening_balance'];
    final openingBalance = rawBalance is num
        ? rawBalance.toDouble()
        : double.tryParse(rawBalance?.toString() ?? '') ?? 0;

    final rawBalanceType = head['opening_balance_type'];
    final openingBalanceType = rawBalanceType is int
        ? rawBalanceType
        : int.tryParse(rawBalanceType?.toString() ?? '');

    return PartyDetailResponseModel(
      code: code,
      message: message,
      agentId: _str(head['agent_id']),
      partyName: _str(head['party_name']),
      mobileNumber: _str(head['mobile_number']),
      email: _str(head['email']),
      address: _str(head['address']),
      state: _str(head['state']),
      district: _str(head['district']),
      city: _str(head['city']),
      othersCity: _str(head['others_city']),
      pincode: _str(head['pincode']),
      identification: _str(head['identification']),
      gstNumber: _str(head['gst_number']),
      openingBalance: openingBalance,
      openingBalanceType: openingBalanceType,
    );
  }
}
