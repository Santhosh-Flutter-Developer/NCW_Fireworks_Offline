/// A generic `{id, name}` pair — used for the pricelist/party dropdown
/// options returned by `quotation.php`.
class IdName {
  final String id;
  final String name;
  const IdName({required this.id, required this.name});

  @override
  String toString() => name;
}

/// Reads a `head` value that may come back as either a comma-separated
/// string (the `explode(",", ...)` fields) or a JSON array, into a
/// `List<String>`. `quotation.php` sends CSV-decrypted strings for names
/// (e.g. `product_name`) and arrays for ids/quantities/rates.
List<String> readStringList(dynamic raw) {
  if (raw == null) return [];
  if (raw is List) {
    return raw.map((e) => e?.toString() ?? '').toList();
  }
  final s = raw.toString();
  if (s.isEmpty) return [];
  return s.split(',');
}

double readNum(dynamic raw) {
  if (raw == null) return 0;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString()) ?? 0;
}

int readIntSafe(dynamic raw) {
  if (raw == null) return 0;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString()) ?? 0;
}
