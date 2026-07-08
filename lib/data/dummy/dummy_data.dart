import '../models/party_model.dart';
import '../models/product_model.dart';
import '../models/billing_item_model.dart';
import '../models/quotation_model.dart';
import '../models/estimation_model.dart';
import '../models/stock_adjustment_model.dart';

/// Centralized dummy/mock data used to power the UI before the
/// Supabase backend is wired up. Replace each generator with a
/// repository call when the backend is ready.
class DummyData {
  DummyData._();

  /// Agents shown in the Agent dropdown on both the Party list filter
  /// and the Add/Edit Party form, matching the web app.
  static const List<String> agents = [
    'Mahendran',
    'Karthik',
    'Priya Dharshini',
  ];

  static const List<String> states = ['Tamil Nadu'];

  static const Map<String, List<String>> districtsByState = {
    'Tamil Nadu': [
      'Virudhunagar',
      'Madurai',
      'Tirunelveli',
      'Sivagangai',
    ],
  };

  static const Map<String, List<String>> citiesByDistrict = {
    'Virudhunagar': ['Sivakasi', 'Virudhunagar', 'Sattur'],
    'Madurai': ['Madurai'],
    'Tirunelveli': ['Tirunelveli', 'Palayamkottai'],
    'Sivagangai': ['Sivagangai', 'Karaikudi'],
  };

  static List<PartyModel> parties() => [
        PartyModel(
          id: 'P001',
          name: 'VEERAPANDIAN - 9940382132',
          phone: '9940382132',
          state: 'Tamil Nadu',
          district: 'Virudhunagar',
          city: 'Sivakasi',
          openingBalance: 12500,
        ),
        PartyModel(
          id: 'P002',
          name: 'NIYAA CRACKERS WORLD',
          state: 'Tamil Nadu',
          district: 'Virudhunagar',
          city: 'Sivakasi',
          openingBalance: 0,
        ),
        PartyModel(
          id: 'P003',
          name: 'RAJASEKAR',
          state: 'Tamil Nadu',
          district: 'Virudhunagar',
          city: 'Sivakasi',
          openingBalance: 4500,
        ),
        PartyModel(
          id: 'P004',
          name: 'Akshaya Traders Sivakasi',
          state: 'Tamil Nadu',
          district: 'Virudhunagar',
          city: 'Sivakasi',
          openingBalance: 3200,
        ),
        PartyModel(
          id: 'P005',
          name: 'RAJASEGARAN',
          state: 'Tamil Nadu',
          district: 'Virudhunagar',
          city: 'Sivakasi',
          openingBalance: 0,
        ),
        PartyModel(
          id: 'P006',
          name: 'SASI TAPES - 9952567397',
          phone: '9952567397',
          agent: 'Mahendran',
          state: 'Tamil Nadu',
          district: 'Madurai',
          city: 'Madurai',
          openingBalance: 875,
        ),
        PartyModel(
          id: 'P007',
          name: 'SHANMUGAM - 8870106383',
          phone: '8870106383',
          state: 'Tamil Nadu',
          district: 'Virudhunagar',
          city: 'Sivakasi',
          openingBalance: 0,
        ),
        PartyModel(
          id: 'P008',
          name: 'PALANI',
          state: 'Tamil Nadu',
          district: 'Tirunelveli',
          city: 'Tirunelveli',
          openingBalance: 0,
          balanceType: BalanceType.debit,
        ),
        PartyModel(
          id: 'P009',
          name: 'MURUGAN KUIL FIRE WORKS',
          agent: 'Karthik',
          state: 'Tamil Nadu',
          district: 'Virudhunagar',
          city: 'Sivakasi',
          openingBalance: 45000,
        ),
        PartyModel(
          id: 'P010',
          name: 'KISHORE - 8220258027',
          phone: '8220258027',
          state: 'Tamil Nadu',
          district: 'Sivagangai',
          city: 'Karaikudi',
          openingBalance: 0,
        ),
      ];

  /// Dropdown master data for the Product screens.
  static const List<String> productCategories = [
    'NIGHT COMMETS - MB',
    'CERMONIAL COLOUR NIGHT - MB',
    'SVA GIFTBOX',
    'SPARKLERS',
    'AERIAL',
    'ROCKETS',
  ];

  static const List<String> productUnits = ['BOX', 'ITEM', 'PCS', 'PACK'];

  static const List<String> pricelists = [
    'MB JUNE RETAIL SALE PRICE LIST',
    'MB WHOLESALE PRICE LIST',
    'SEASON OPENING PRICE LIST',
  ];

  static List<ProductModel> products() => [
        ProductModel(
          id: 'PR001',
          category: 'NIGHT COMMETS - MB',
          code: '',
          name: '6" SINGLE SUPER HEROES SERIES (EXCLUSIVE)',
          unit: 'BOX',
          stockMaintain: true,
          negativeStock: true,
          currentStock: 0,
          prices: [
            PricelistEntry(
                pricelistName: 'MB JUNE RETAIL SALE PRICE LIST', price: 1226),
          ],
        ),
        ProductModel(
          id: 'PR002',
          category: 'CERMONIAL COLOUR NIGHT - MB',
          code: '',
          name: 'GRAND OPENING 5*10 CRACKLING MULTI COLOUR SHOTS',
          unit: 'BOX',
          stockMaintain: true,
          negativeStock: true,
          currentStock: 0,
          prices: [
            PricelistEntry(
                pricelistName: 'MB JUNE RETAIL SALE PRICE LIST', price: 2450),
          ],
        ),
        ProductModel(
          id: 'PR003',
          category: 'SVA GIFTBOX',
          code: '',
          name: 'NATCHIYAR (45 Item)',
          unit: 'BOX',
          stockMaintain: true,
          negativeStock: true,
          currentStock: -4,
          prices: [
            PricelistEntry(
                pricelistName: 'MB JUNE RETAIL SALE PRICE LIST', price: 3200),
          ],
        ),
        ProductModel(
          id: 'PR004',
          category: 'SVA GIFTBOX',
          code: '',
          name: '7 HILLS (41 Item)',
          unit: 'BOX',
          stockMaintain: true,
          negativeStock: true,
          currentStock: -3,
          prices: [
            PricelistEntry(
                pricelistName: 'MB JUNE RETAIL SALE PRICE LIST', price: 2890),
          ],
        ),
        ProductModel(
          id: 'PR005',
          category: 'SVA GIFTBOX',
          code: '',
          name: 'GANESH (36 item)',
          unit: 'BOX',
          stockMaintain: true,
          negativeStock: true,
          currentStock: -3,
          prices: [
            PricelistEntry(
                pricelistName: 'MB JUNE RETAIL SALE PRICE LIST', price: 2540),
          ],
        ),
        ProductModel(
          id: 'PR006',
          category: 'SVA GIFTBOX',
          code: '',
          name: 'SKYTOWER (33 item)',
          unit: 'BOX',
          stockMaintain: true,
          negativeStock: true,
          currentStock: -3,
          prices: [
            PricelistEntry(
                pricelistName: 'MB JUNE RETAIL SALE PRICE LIST', price: 2310),
          ],
        ),
        ProductModel(
          id: 'PR007',
          category: 'SVA GIFTBOX',
          code: '',
          name: 'SILVER (30 Item)',
          unit: 'BOX',
          stockMaintain: true,
          negativeStock: true,
          currentStock: -3,
          prices: [
            PricelistEntry(
                pricelistName: 'MB JUNE RETAIL SALE PRICE LIST', price: 2100),
          ],
        ),
        ProductModel(
          id: 'PR008',
          category: 'SVA GIFTBOX',
          code: '',
          name: 'GOLD (27 Item)',
          unit: 'BOX',
          stockMaintain: true,
          negativeStock: true,
          currentStock: -3,
          prices: [
            PricelistEntry(
                pricelistName: 'MB JUNE RETAIL SALE PRICE LIST', price: 1890),
          ],
        ),
        ProductModel(
          id: 'PR009',
          category: 'SVA GIFTBOX',
          code: '',
          name: 'FUNLAND (24 Item)',
          unit: 'BOX',
          stockMaintain: true,
          negativeStock: true,
          currentStock: -3,
          prices: [
            PricelistEntry(
                pricelistName: 'MB JUNE RETAIL SALE PRICE LIST', price: 1650),
          ],
        ),
        ProductModel(
          id: 'PR010',
          category: 'SVA GIFTBOX',
          code: '',
          name: 'DIAMOND (21 Item)',
          unit: 'BOX',
          stockMaintain: true,
          negativeStock: true,
          currentStock: -3,
          prices: [
            PricelistEntry(
                pricelistName: 'MB JUNE RETAIL SALE PRICE LIST', price: 1420),
          ],
        ),
      ];

  static List<QuotationModel> quotations() {
    final prods = products();
    return [
      QuotationModel(
        id: 'Q001',
        quotationNo: 'QUT001/26-27',
        partyId: 'P001',
        partyName: 'Sri Lakshmi Traders',
        agentName: 'Mahendran',
        pricelistName: 'MB JUNE RETAIL SALE PRICE LIST',
        date: DateTime(2026, 7, 1),
        validTill: DateTime(2026, 7, 15),
        items: [
          BillingItemModel(
              productId: prods[0].id,
              productName: prods[0].name,
              quantity: 20,
              rate: prods[0].price,
              unit: prods[0].unit),
          BillingItemModel(
              productId: prods[2].id,
              productName: prods[2].name,
              quantity: 5,
              rate: prods[2].price,
              discountPercent: 5,
              unit: prods[2].unit),
        ],
        status: DocStatus.active,
      ),
      QuotationModel(
        id: 'Q002',
        quotationNo: 'QUT002/26-27',
        partyId: 'P006',
        partyName: 'THARUN',
        agentName: 'Direct',
        pricelistName: 'MB JUNE RETAIL SALE PRICE LIST',
        date: DateTime(2026, 6, 1),
        validTill: DateTime(2026, 6, 15),
        items: [
          BillingItemModel(
              productId: prods[6].id,
              productName: prods[6].name,
              quantity: 10,
              rate: prods[6].price,
              unit: prods[6].unit),
        ],
        status: DocStatus.active,
      ),
      QuotationModel(
        id: 'Q003',
        quotationNo: 'QUT003/26-27',
        partyId: 'P006',
        partyName: 'Anbu & Sons',
        agentName: 'Karthik',
        pricelistName: 'MB JUNE RETAIL SALE PRICE LIST',
        date: DateTime(2026, 6, 28),
        validTill: DateTime(2026, 7, 5),
        items: [
          BillingItemModel(
              productId: prods[4].id,
              productName: prods[4].name,
              quantity: 30,
              rate: prods[4].price,
              unit: prods[4].unit),
          BillingItemModel(
              productId: prods[7].id,
              productName: prods[7].name,
              quantity: 100,
              rate: prods[7].price,
              unit: prods[7].unit),
        ],
        status: DocStatus.draft,
      ),
      QuotationModel(
        id: 'Q004',
        quotationNo: 'QUT004/26-27',
        partyId: 'P002',
        partyName: 'Kaveri Crackers Wholesale',
        agentName: 'Priya Dharshini',
        pricelistName: 'MB JUNE RETAIL SALE PRICE LIST',
        date: DateTime(2026, 6, 20),
        validTill: DateTime(2026, 6, 30),
        items: [
          BillingItemModel(
              productId: prods[1].id,
              productName: prods[1].name,
              quantity: 40,
              rate: prods[1].price,
              unit: prods[1].unit),
        ],
        status: DocStatus.cancelled,
      ),
    ];
  }

  static List<EstimationModel> estimations() {
    final prods = products();
    return [
      EstimationModel(
        id: 'E001',
        estimationNo: 'EST-2026-001',
        partyId: 'P002',
        partyName: 'Kaveri Crackers Wholesale',
        date: DateTime(2026, 7, 2),
        items: [
          BillingItemModel(
              productId: prods[3].id,
              productName: prods[3].name,
              quantity: 60,
              rate: prods[3].price),
          BillingItemModel(
              productId: prods[5].id,
              productName: prods[5].name,
              quantity: 12,
              rate: prods[5].price),
        ],
        status: DocStatus.draft,
      ),
      EstimationModel(
        id: 'E002',
        estimationNo: 'EST-2026-002',
        partyId: 'P001',
        partyName: 'Sri Lakshmi Traders',
        date: DateTime(2026, 7, 4),
        items: [
          BillingItemModel(
              productId: prods[6].id,
              productName: prods[6].name,
              quantity: 8,
              rate: prods[6].price),
        ],
        status: DocStatus.converted,
      ),
      EstimationModel(
        id: 'E003',
        estimationNo: 'EST-2026-003',
        partyId: 'P006',
        partyName: 'Anbu & Sons',
        date: DateTime(2026, 6, 30),
        items: [
          BillingItemModel(
              productId: prods[0].id,
              productName: prods[0].name,
              quantity: 15,
              rate: prods[0].price),
          BillingItemModel(
              productId: prods[2].id,
              productName: prods[2].name,
              quantity: 3,
              rate: prods[2].price),
        ],
        status: DocStatus.sent,
      ),
    ];
  }

  static List<StockAdjustmentModel> stockAdjustments() {
    final prods = products();
    return [
      StockAdjustmentModel(
        id: 'SA001',
        refNo: 'ADJ-2026-001',
        productId: prods[1].id,
        productName: prods[1].name,
        date: DateTime(2026, 7, 5),
        type: AdjustmentType.reduction,
        quantity: 12,
        stockBefore: 30,
        stockAfter: 18,
        reason: 'Damaged during transit',
      ),
      StockAdjustmentModel(
        id: 'SA002',
        refNo: 'ADJ-2026-002',
        productId: prods[2].id,
        productName: prods[2].name,
        date: DateTime(2026, 7, 3),
        type: AdjustmentType.addition,
        quantity: 50,
        stockBefore: 14,
        stockAfter: 64,
        reason: 'New purchase from Standard Fireworks',
      ),
      StockAdjustmentModel(
        id: 'SA003',
        refNo: 'ADJ-2026-003',
        productId: prods[5].id,
        productName: prods[5].name,
        date: DateTime(2026, 7, 1),
        type: AdjustmentType.damage,
        quantity: 4,
        stockBefore: 9,
        stockAfter: 5,
        reason: 'Water damage in godown',
      ),
      StockAdjustmentModel(
        id: 'SA004',
        refNo: 'ADJ-2026-004',
        productId: prods[7].id,
        productName: prods[7].name,
        date: DateTime(2026, 6, 29),
        type: AdjustmentType.correction,
        quantity: 20,
        stockBefore: 880,
        stockAfter: 900,
        reason: 'Physical count correction',
      ),
    ];
  }
}
