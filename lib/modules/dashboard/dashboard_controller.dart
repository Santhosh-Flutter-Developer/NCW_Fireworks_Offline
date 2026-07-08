import 'package:get/get.dart';
import '../../data/dummy/dummy_data.dart';
import '../../data/models/billing_item_model.dart';

class DashboardController extends GetxController {
  final parties = DummyData.parties();
  final products = DummyData.products();
  final quotations = DummyData.quotations();
  final estimations = DummyData.estimations();
  final stockAdjustments = DummyData.stockAdjustments();

  int get totalParties => parties.length;
  int get totalProducts => products.length;
  int get lowStockCount => products.where((p) => p.needsAttention).length;

  double get quotationsValue =>
      quotations.fold(0, (sum, q) => sum + q.total);

  double get estimationsValue =>
      estimations.fold(0, (sum, e) => sum + e.total);

  int get pendingQuotations =>
      quotations.where((q) => q.status == DocStatus.active).length;

  int get pendingEstimations =>
      estimations.where((e) => e.status == DocStatus.draft).length;

  /// Weekly sales trend used for the dashboard chart (dummy figures).
  List<double> get weeklyTrend => const [12, 18, 14, 22, 19, 26, 24];

  List<String> get weeklyLabels =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Product count by category for the dashboard donut chart. Using a
  /// count rather than summed stock keeps the chart meaningful even when
  /// products are running negative (negative stock is allowed here).
  Map<String, int> get stockByCategory {
    final map = <String, int>{};
    for (final p in products) {
      map[p.category] = (map[p.category] ?? 0) + 1;
    }
    return map;
  }
}
