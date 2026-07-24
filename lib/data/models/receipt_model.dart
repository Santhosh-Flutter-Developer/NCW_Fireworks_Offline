import 'billing_item_model.dart';

/// One row in the Receipt list — mirrors the columns on the web app's
/// Receipt screen: Receipt Date / Receipt Number / Agent Name / Party
/// Name / Amount.
class ReceiptModel {
  final String id; // server receipt_id
  final String receiptNumber;
  final DateTime date;
  final String agentName;
  final String partyName;
  final double totalAmount;

  /// Driven by the selected Active/Cancel tab on the list screen (the
  /// `receipt_listing` rows themselves don't carry a per-row status).
  final DocStatus status;

  /// True when this row was built from the on-device pending-sync queue
  /// — a Receipt created against an estimate on this device that hasn't
  /// been sent to `receipt.php` yet. Drives the "Pending sync" badge on
  /// the list, same as `EstimationModel.isPending`.
  final bool isPending;

  /// The pending-sync queue entry's own id, when [isPending] is true.
  /// Empty for a row that came from the synced server cache.
  final String localId;

  const ReceiptModel({
    required this.id,
    required this.receiptNumber,
    required this.date,
    required this.agentName,
    required this.partyName,
    required this.totalAmount,
    this.status = DocStatus.active,
    this.isPending = false,
    this.localId = '',
  });
}

/// One payment-mode/bank/amount row added via "Add To Bill" on the Add
/// Receipt screen — becomes one entry each in the parallel
/// `payment_mode_id` / `bank_id` / `amount` arrays sent on `receipt_update`.
class ReceiptPaymentLine {
  final String paymentModeId;
  final String paymentModeName;

  /// Empty when this line's payment mode isn't linked to any bank (Cash,
  /// Petty Cash, old-balance carry-forwards) — sent as `""` in `bank_id`.
  final String bankId;
  final String bankName;
  double amount;

  ReceiptPaymentLine({
    required this.paymentModeId,
    required this.paymentModeName,
    this.bankId = '',
    this.bankName = '',
    required this.amount,
  });

  bool get isCash => bankId.isEmpty;
}