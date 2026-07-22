/// Converts a rupee amount to words using the Indian numbering system
/// (Hundred / Thousand / Lakh / Crore, not the Western Million/Billion
/// split) — matches the "Amount in words" line on the printed quotation,
/// e.g. `8206` → `Rupees Eight Thousand Two Hundred and Six Only`.
class IndianCurrencyWords {
  static const _ones = [
    '',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
    'Thirteen',
    'Fourteen',
    'Fifteen',
    'Sixteen',
    'Seventeen',
    'Eighteen',
    'Nineteen',
  ];

  static const _tens = [
    '',
    '',
    'Twenty',
    'Thirty',
    'Forty',
    'Fifty',
    'Sixty',
    'Seventy',
    'Eighty',
    'Ninety',
  ];

  /// e.g. `8206.5` → `Rupees Eight Thousand Two Hundred and Six and Fifty
  /// Paise Only`. Rounds to the nearest paisa; a whole-rupee amount omits
  /// the Paise clause entirely, matching the sample bill.
  static String convert(double amount) {
    final rounded = (amount.abs() * 100).round();
    final rupees = rounded ~/ 100;
    final paise = rounded % 100;

    final rupeeWords = rupees == 0 ? 'Zero' : _convertWhole(rupees);
    final buffer = StringBuffer('Rupees $rupeeWords');
    if (paise > 0) {
      buffer.write(' and ${_convertWhole(paise)} Paise');
    }
    buffer.write(' Only');
    return buffer.toString();
  }

  static String _convertWhole(int n) {
    if (n == 0) return '';
    if (n < 20) return _ones[n];
    if (n < 100) {
      final rest = n % 10;
      return '${_tens[n ~/ 10]}${rest > 0 ? ' ${_ones[rest]}' : ''}';
    }
    if (n < 1000) {
      final rest = n % 100;
      return '${_ones[n ~/ 100]} Hundred${rest > 0 ? ' and ${_convertWhole(rest)}' : ''}';
    }
    if (n < 100000) {
      final rest = n % 1000;
      return '${_convertWhole(n ~/ 1000)} Thousand${rest > 0 ? ' ${_convertWhole(rest)}' : ''}';
    }
    if (n < 10000000) {
      final rest = n % 100000;
      return '${_convertWhole(n ~/ 100000)} Lakh${rest > 0 ? ' ${_convertWhole(rest)}' : ''}';
    }
    final rest = n % 10000000;
    return '${_convertWhole(n ~/ 10000000)} Crore${rest > 0 ? ' ${_convertWhole(rest)}' : ''}';
  }
}