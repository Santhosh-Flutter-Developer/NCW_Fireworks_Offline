class BillingItemModel {
  String productId;
  String productName;
  int quantity;
  double rate;
  double discountPercent;
  String unit;

  /// Which totals section (1 or 2) this line item is grouped under —
  /// mirrors the "Section 1 / Section 2" split on the web app's
  /// Add Quotation screen.
  int section;

  BillingItemModel({
    required this.productId,
    required this.productName,
    this.quantity = 1,
    required this.rate,
    this.discountPercent = 0,
    this.unit = 'BOX',
    this.section = 1,
  });

  double get amount {
    final gross = quantity * rate;
    return gross - (gross * discountPercent / 100);
  }
}

enum DocStatus {
  draft,
  sent,
  approved,
  rejected,
  expired,
  converted,
  active,
  cancelled,
}

extension DocStatusX on DocStatus {
  String get label {
    switch (this) {
      case DocStatus.draft:
        return 'Draft';
      case DocStatus.sent:
        return 'Sent';
      case DocStatus.approved:
        return 'Approved';
      case DocStatus.rejected:
        return 'Rejected';
      case DocStatus.expired:
        return 'Expired';
      case DocStatus.converted:
        return 'Converted';
      case DocStatus.active:
        return 'Active';
      case DocStatus.cancelled:
        return 'Cancel';
    }
  }
}
