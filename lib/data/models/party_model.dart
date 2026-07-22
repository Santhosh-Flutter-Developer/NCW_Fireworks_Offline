enum BalanceType { credit, debit }

extension BalanceTypeX on BalanceType {
  String get label => this == BalanceType.credit ? 'Credit' : 'Debit';
}

class PartyModel {
  final String id;

  /// The party's real identifier on the server (`party_id` from
  /// `party.php`), when known. `null` for parties that only exist
  /// locally (e.g. dummy/demo rows, or a row created before the API
  /// returned one) — editing such a row can't be sent to the API yet
  /// since there's no id for the server to match against.
  String? serverPartyId;
  String agent;
  String name;
  String phone;
  String email;
  String address;
  String state;
  String district;
  String city;
  String othersCity;
  String pincode;
  String identification;
  String gstin;
  double openingBalance;
  BalanceType balanceType;
  bool isDraft;
   bool hasFullDetails;

  /// True when this row was built from the on-device pending-sync queue
  /// — an add/edit made on this device that hasn't been sent to
  /// `party.php` yet. Drives the "Pending sync" badge on the list.
  bool isPending;

  /// The pending-sync queue entry's own id, when [isPending] is true —
  /// used to update/remove that exact entry on a later edit or delete.
  /// Null for a row that came from the synced server cache.
  String? localId;

  PartyModel({
    required this.id,
    this.serverPartyId,
    this.agent = '',
    required this.name,
    this.phone = '',
    this.email = '',
    this.address = '',
    this.state = 'Tamil Nadu',
    this.district = '',
    this.city = '',
    this.othersCity = '',
    this.pincode = '',
    this.identification = '',
    this.gstin = '',
    this.openingBalance = 0,
    this.balanceType = BalanceType.credit,
    this.isDraft = false,
    this.hasFullDetails = true,
    this.isPending = false,
    this.localId,
  });

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String get agentLabel => agent.isEmpty ? '-' : agent;

  String get cityLabel =>
      city == 'Others' && othersCity.isNotEmpty ? othersCity : city;
}