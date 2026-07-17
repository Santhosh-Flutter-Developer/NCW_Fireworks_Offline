class ApiEndpoints {
  ApiEndpoints._();

  static const String baseUrl =
      'https://sriseosolutions.com/mahendran/niyacrackers/section/retail_mobile_app/API';

  static const String reportsBaseUrl =
      'https://sriseosolutions.com/mahendran/niyacrackers/section/retail_mobile_app/reports';

  static Uri get login => Uri.parse('$baseUrl/login.php');
  static Uri get party => Uri.parse('$baseUrl/party.php');
  static Uri get productPrice => Uri.parse('$baseUrl/product.php');
  static Uri get estimate => Uri.parse('$baseUrl/estimate.php');
  static Uri get quotation => Uri.parse('$baseUrl/quotation.php');
  static Uri get receipt => Uri.parse('$baseUrl/receipt.php');

  /// Print/download A4 PDF for one estimate — same report is used for both
  /// actions; the browser/OS's own PDF viewer offers print & save/download.
  static Uri estimateReport(String estimateId) => Uri.parse(
      '$reportsBaseUrl/rpt_estimate_a4.php?view_estimate_id=$estimateId&from=D');

  /// Print/download A4 PDF for one quotation — same report for both
  /// actions, same reasoning as [estimateReport].
  static Uri quotationReport(String quotationId) => Uri.parse(
      '$reportsBaseUrl/rpt_quotation_a4.php?view_quotation_id=$quotationId&from=D');

  /// Print/download A5 PDF for one receipt — same report for both actions,
  /// same reasoning as [estimateReport].
  static Uri receiptReport(String receiptId) => Uri.parse(
      '$reportsBaseUrl/rpt_receipt_a5.php?view_receipt_id=$receiptId&from=D');
}