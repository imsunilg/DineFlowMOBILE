// Plain data classes that mirror the API DTOs. Every parser tolerates missing/null fields so a server-side
// addition or omission never crashes a screen. No business rules live here: totals and prices come from the API.

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String _s(Object? v, [String fallback = '']) => v == null ? fallback : '$v';
String? _n(Object? v) => v == null ? null : '$v';
DateTime? _t(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
List<Map<String, dynamic>> _list(Object? v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

class Paged<T> {
  Paged({required this.items, required this.page, required this.totalPages, required this.totalCount});
  final List<T> items;
  final int page;
  final int totalPages;
  final int totalCount;

  factory Paged.from(Object? json, T Function(Map<String, dynamic>) parse) {
    final m = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    return Paged(items: _list(m['items']).map(parse).toList(), page: _i(m['page']), totalPages: _i(m['totalPages']), totalCount: _i(m['totalCount']));
  }
}

class UserProfile {
  UserProfile({required this.id, required this.email, required this.fullName, required this.tenantCode, required this.roles, required this.permissions});
  final String id;
  final String email;
  final String fullName;
  final String? tenantCode;
  final List<String> roles;
  final Set<String> permissions;

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: _s(j['id']),
        email: _s(j['email']),
        fullName: _s(j['fullName']),
        tenantCode: _n(j['tenantCode']),
        roles: (j['roles'] as List? ?? const []).map((e) => '$e').toList(),
        permissions: (j['permissions'] as List? ?? const []).map((e) => '$e').toSet(),
      );

  String get firstName => fullName.trim().isEmpty ? 'there' : fullName.trim().split(' ').first;
}

class Branding {
  Branding({
    required this.tenantCode,
    required this.applicationName,
    required this.displayName,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.currencySymbol,
    required this.features,
    required this.platformName,
    this.logoUrl,
  });
  final String tenantCode;
  final String applicationName;
  final String displayName;
  final String primaryColor;
  final String secondaryColor;
  final String accentColor;
  final String currencySymbol;
  final Map<String, bool> features;
  final String platformName;
  final String? logoUrl;

  factory Branding.fromJson(Map<String, dynamic> j) => Branding(
        tenantCode: _s(j['tenantCode']),
        applicationName: _s(j['applicationName']),
        displayName: _s(j['displayName']),
        primaryColor: _s(j['primaryColor'], '#7c3aed'),
        secondaryColor: _s(j['secondaryColor'], '#111827'),
        accentColor: _s(j['accentColor'], '#f59e0b'),
        currencySymbol: _s(j['currencySymbol']),
        features: {for (final e in (j['features'] as Map? ?? const {}).entries) '${e.key}': e.value == true},
        platformName: _s(j['platformName']),
        logoUrl: _n(j['logoUrl']),
      );

  bool isEnabled(String? feature) => feature == null || features[feature] != false;
}

class DiningTable {
  DiningTable({required this.id, required this.floorId, required this.code, required this.capacity, required this.status});
  final String id;
  final String floorId;
  final String code;
  final int capacity;
  final String status;

  factory DiningTable.fromJson(Map<String, dynamic> j) =>
      DiningTable(id: _s(j['id']), floorId: _s(j['floorId']), code: _s(j['code']), capacity: _i(j['capacity']), status: _s(j['status'], 'Available'));
}

class FloorLayout {
  FloorLayout({required this.id, required this.name, required this.tables});
  final String id;
  final String name;
  final List<DiningTable> tables;

  factory FloorLayout.fromJson(Map<String, dynamic> j) => FloorLayout(id: _s(j['id']), name: _s(j['name']), tables: _list(j['tables']).map(DiningTable.fromJson).toList());
}

class TableSummary {
  TableSummary({required this.total, required this.available, required this.reserved, required this.occupied, required this.cleaning, required this.blocked});
  final int total, available, reserved, occupied, cleaning, blocked;

  factory TableSummary.fromJson(Map<String, dynamic> j) => TableSummary(
      total: _i(j['total']), available: _i(j['available']), reserved: _i(j['reserved']), occupied: _i(j['occupied']), cleaning: _i(j['cleaning']), blocked: _i(j['blocked']));
}

class Variant {
  Variant({required this.id, required this.name, required this.price});
  final String id;
  final String name;
  final double price;

  factory Variant.fromJson(Map<String, dynamic> j) => Variant(id: _s(j['id']), name: _s(j['name']), price: _d(j['price']));
}

class MenuItem {
  MenuItem({required this.id, required this.name, required this.basePrice, required this.isVeg, required this.isAvailable, required this.serviceArea, required this.variants, required this.addons});
  final String id;
  final String name;
  final double basePrice;
  final bool isVeg;
  final bool isAvailable;
  final String serviceArea;
  final List<Variant> variants;
  final List<Variant> addons;

  factory MenuItem.fromJson(Map<String, dynamic> j) => MenuItem(
        id: _s(j['id']),
        name: _s(j['name']),
        basePrice: _d(j['basePrice']),
        isVeg: j['isVeg'] == true,
        isAvailable: j['isAvailable'] != false,
        serviceArea: _s(j['serviceArea'], 'Restaurant'),
        variants: _list(j['variants']).map(Variant.fromJson).toList(),
        addons: _list(j['addons']).map(Variant.fromJson).toList(),
      );
}

class MenuCategory {
  MenuCategory({required this.id, required this.name, required this.serviceArea, required this.items});
  final String id;
  final String name;
  final String serviceArea;
  final List<MenuItem> items;

  factory MenuCategory.fromJson(Map<String, dynamic> j) =>
      MenuCategory(id: _s(j['id']), name: _s(j['name']), serviceArea: _s(j['serviceArea'], 'Restaurant'), items: _list(j['items']).map(MenuItem.fromJson).toList());
}

class OrderLine {
  final String serviceArea;
  OrderLine({required this.serviceArea, required this.id, required this.itemName, required this.variantName, required this.quantity, required this.unitPrice, required this.lineSubtotal, required this.status, required this.notes, required this.addons});
  final String id;
  final String itemName;
  final String? variantName;
  final int quantity;
  final double unitPrice;
  final double lineSubtotal;
  final String status;
  final String? notes;
  final List<String> addons;

  factory OrderLine.fromJson(Map<String, dynamic> j) => OrderLine(
        serviceArea: _s(j['serviceArea'], 'Restaurant'),
        id: _s(j['id']),
        itemName: _s(j['itemName']),
        variantName: _n(j['variantName']),
        quantity: _i(j['quantity']),
        unitPrice: _d(j['unitPrice']),
        lineSubtotal: _d(j['lineSubtotal']),
        status: _s(j['status']),
        notes: _n(j['notes']),
        addons: _list(j['addons']).map((a) => _s(a['name'])).toList(),
      );

  bool get isDraft => status == 'Draft';
  bool get isCancelled => status == 'Cancelled';
}

class Order {
  Order({
    required this.id,
    required this.orderNo,
    required this.orderType,
    required this.tableId,
    required this.tableCode,
    required this.customerName,
    required this.status,
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.serviceChargeAmount,
    required this.roundOff,
    required this.grandTotal,
    required this.billId,
    required this.lines,
  });
  final String id;
  final String orderNo;
  final String orderType;
  final String? tableId;
  final String? tableCode;
  final String? customerName;
  final String status;
  final double subtotal, discountAmount, taxAmount, serviceChargeAmount, roundOff, grandTotal;
  final String? billId;
  final List<OrderLine> lines;

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        id: _s(j['id']),
        orderNo: _s(j['orderNo']),
        orderType: _s(j['orderType']),
        tableId: _n(j['tableId']),
        tableCode: _n(j['tableCode']),
        customerName: _n(j['customerName']),
        status: _s(j['status']),
        subtotal: _d(j['subtotal']),
        discountAmount: _d(j['discountAmount']),
        taxAmount: _d(j['taxAmount']),
        serviceChargeAmount: _d(j['serviceChargeAmount']),
        roundOff: _d(j['roundOff']),
        grandTotal: _d(j['grandTotal']),
        billId: _n(j['billId']),
        lines: _list(j['lines']).map(OrderLine.fromJson).toList(),
      );

  List<OrderLine> get liveLines => lines.where((l) => !l.isCancelled).toList();
  bool get hasDraft => lines.any((l) => l.isDraft);
  bool get isOpen => status != 'Completed' && status != 'Cancelled';
}

class OrderSummary {
  OrderSummary({required this.id, required this.orderNo, required this.orderType, required this.tableCode, required this.customerName, required this.status, required this.grandTotal, required this.itemCount, required this.createdAt});
  final String id, orderNo, orderType, status;
  final String? tableCode, customerName;
  final double grandTotal;
  final int itemCount;
  final DateTime? createdAt;

  factory OrderSummary.fromJson(Map<String, dynamic> j) => OrderSummary(
        id: _s(j['id']),
        orderNo: _s(j['orderNo']),
        orderType: _s(j['orderType']),
        tableCode: _n(j['tableCode']),
        customerName: _n(j['customerName']),
        status: _s(j['status']),
        grandTotal: _d(j['grandTotal']),
        itemCount: _i(j['itemCount']),
        createdAt: _t(j['createdAt']),
      );
}

class TaxLine {
  TaxLine({required this.name, required this.ratePercent, required this.amount});
  final String name;
  final double ratePercent, amount;

  factory TaxLine.fromJson(Map<String, dynamic> j) => TaxLine(name: _s(j['name']), ratePercent: _d(j['ratePercent']), amount: _d(j['amount']));
}

class Bill {
  Bill({required this.id, required this.billNo, required this.status, required this.subtotal, required this.discountAmount, required this.taxAmount, required this.serviceChargeAmount, required this.roundOff, required this.grandTotal, required this.paidAmount, required this.dueAmount, required this.taxBreakdown});
  final String id, billNo, status;
  final double subtotal, discountAmount, taxAmount, serviceChargeAmount, roundOff, grandTotal, paidAmount, dueAmount;
  final List<TaxLine> taxBreakdown;

  factory Bill.fromJson(Map<String, dynamic> j) => Bill(
        id: _s(j['id']),
        billNo: _s(j['billNo']),
        status: _s(j['status']),
        subtotal: _d(j['subtotal']),
        discountAmount: _d(j['discountAmount']),
        taxAmount: _d(j['taxAmount']),
        serviceChargeAmount: _d(j['serviceChargeAmount']),
        roundOff: _d(j['roundOff']),
        grandTotal: _d(j['grandTotal']),
        paidAmount: _d(j['paidAmount']),
        dueAmount: _d(j['dueAmount']),
        taxBreakdown: _list(j['taxBreakdown']).map(TaxLine.fromJson).toList(),
      );
}

class PaymentMethod {
  PaymentMethod({required this.id, required this.name});
  final String id, name;

  factory PaymentMethod.fromJson(Map<String, dynamic> j) => PaymentMethod(id: _s(j['id']), name: _s(j['name']));
}

class KitchenItem {
  KitchenItem({required this.id, required this.name, required this.variantName, required this.quantity, required this.notes, required this.status, required this.addons});
  final String id, name, status;
  final String? variantName, notes;
  final int quantity;
  final List<String> addons;

  factory KitchenItem.fromJson(Map<String, dynamic> j) => KitchenItem(
        id: _s(j['id']),
        name: _s(j['name']),
        variantName: _n(j['variantName']),
        quantity: _i(j['quantity']),
        notes: _n(j['notes']),
        status: _s(j['status']),
        addons: (j['addons'] as List? ?? const []).map((e) => '$e').toList(),
      );
}

class KitchenTicket {
  KitchenTicket({required this.orderId, required this.orderNo, required this.orderType, required this.tableCode, required this.sentAt, required this.items});
  final String orderId, orderNo, orderType;
  final String? tableCode;
  final DateTime? sentAt;
  final List<KitchenItem> items;

  factory KitchenTicket.fromJson(Map<String, dynamic> j) => KitchenTicket(
        orderId: _s(j['orderId']),
        orderNo: _s(j['orderNo']),
        orderType: _s(j['orderType']),
        tableCode: _n(j['tableCode']),
        sentAt: _t(j['sentAt']),
        items: _list(j['items']).map(KitchenItem.fromJson).toList(),
      );
}

class BarStockRow {
  BarStockRow({required this.productName, required this.categoryName, required this.volumeMl, required this.quantityMl, required this.wholeBottles, required this.looseMl, required this.isLow});
  final String productName, categoryName;
  final int volumeMl;
  final double quantityMl;
  final int wholeBottles;
  final double looseMl;
  final bool isLow;

  factory BarStockRow.fromJson(Map<String, dynamic> j) => BarStockRow(
        productName: _s(j['productName']),
        categoryName: _s(j['categoryName']),
        volumeMl: _i(j['volumeMl']),
        quantityMl: _d(j['quantityMl']),
        wholeBottles: _i(j['wholeBottles']),
        looseMl: _d(j['looseMl']),
        isLow: j['isLow'] == true,
      );
}

class InvStockRow {
  InvStockRow({required this.name, required this.code, required this.unitCode, required this.quantity, required this.reorderLevel, required this.level, required this.warehouseName});
  final String name, code, unitCode, level, warehouseName;
  final double quantity, reorderLevel;

  factory InvStockRow.fromJson(Map<String, dynamic> j) => InvStockRow(
        name: _s(j['name']),
        code: _s(j['code']),
        unitCode: _s(j['unitCode']),
        quantity: _d(j['quantity']),
        reorderLevel: _d(j['reorderLevel']),
        level: _s(j['level'], 'OK'),
        warehouseName: _s(j['warehouseName']),
      );
}

class StockAlert {
  StockAlert({required this.source, required this.name, required this.quantity, required this.threshold, required this.unit});
  final String source, name, unit;
  final double quantity, threshold;

  factory StockAlert.fromJson(Map<String, dynamic> j) =>
      StockAlert(source: _s(j['source']), name: _s(j['name']), quantity: _d(j['quantity']), threshold: _d(j['threshold']), unit: _s(j['unit']));
}

class Customer {
  Customer({required this.id, required this.fullName, required this.phone, required this.email, required this.notes});
  final String id, fullName;
  final String? phone, email, notes;

  factory Customer.fromJson(Map<String, dynamic> j) =>
      Customer(id: _s(j['id']), fullName: _s(j['fullName']), phone: _n(j['phone']), email: _n(j['email']), notes: _n(j['notes']));
}

class CustomerProfile {
  CustomerProfile({required this.customer, required this.totalVisits, required this.totalSpend, required this.averageOrderValue, required this.favoriteItems, required this.pointsBalance, required this.tierName, required this.recentOrders});
  final Customer customer;
  final int totalVisits;
  final double totalSpend, averageOrderValue;
  final List<String> favoriteItems;
  final int? pointsBalance;
  final String? tierName;
  final List<OrderSummary> recentOrders;

  factory CustomerProfile.fromJson(Map<String, dynamic> j) {
    final stats = j['stats'] as Map<String, dynamic>? ?? const {};
    final loyalty = j['loyalty'] as Map<String, dynamic>?;
    return CustomerProfile(
      customer: Customer.fromJson(j['customer'] as Map<String, dynamic>? ?? const {}),
      totalVisits: _i(stats['totalVisits']),
      totalSpend: _d(stats['totalSpend']),
      averageOrderValue: _d(stats['averageOrderValue']),
      favoriteItems: _list(stats['favoriteItems']).map((f) => '${_s(f['name'])} × ${_i(f['quantity'])}').toList(),
      pointsBalance: loyalty == null ? null : _i(loyalty['pointsBalance']),
      tierName: loyalty == null ? null : _n(loyalty['tierName']),
      recentOrders: _list(j['recentOrders']).map(OrderSummary.fromJson).toList(),
    );
  }
}

class Reservation {
  Reservation({required this.id, required this.reservationNo, required this.guestName, required this.phone, required this.guestCount, required this.reservedAt, required this.tableCode, required this.status, required this.allowedTransitions, required this.specialRequest});
  final String id, reservationNo, guestName, status;
  final String? phone, tableCode, specialRequest;
  final int guestCount;
  final DateTime? reservedAt;
  final List<String> allowedTransitions;

  factory Reservation.fromJson(Map<String, dynamic> j) => Reservation(
        id: _s(j['id']),
        reservationNo: _s(j['reservationNo']),
        guestName: _s(j['guestName']),
        phone: _n(j['phone']),
        guestCount: _i(j['guestCount']),
        reservedAt: _t(j['reservedAt']),
        tableCode: _n(j['tableCode']),
        status: _s(j['status']),
        allowedTransitions: (j['allowedTransitions'] as List? ?? const []).map((e) => '$e').toList(),
        specialRequest: _n(j['specialRequest']),
      );
}

class AppNotification {
  AppNotification({required this.id, required this.type, required this.title, required this.message, required this.isRead, required this.createdAt});
  final String id, type, title, message;
  final bool isRead;
  final DateTime? createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> j) =>
      AppNotification(id: _s(j['id']), type: _s(j['type']), title: _s(j['title']), message: _s(j['message']), isRead: j['isRead'] == true, createdAt: _t(j['createdAt']));
}

class ChartPoint {
  ChartPoint(this.label, this.value);
  final String label;
  final double value;

  factory ChartPoint.fromJson(Map<String, dynamic> j) => ChartPoint(_s(j['label']), _d(j['value']));
}

class Dashboard {
  Dashboard({required this.salesToday, required this.ordersToday, required this.customersToday, required this.pendingOrders, required this.expensesToday, required this.inventoryAlerts, required this.dailySales, required this.topItems, required this.lowStock});
  final double salesToday, expensesToday;
  final int ordersToday, customersToday, pendingOrders, inventoryAlerts;
  final List<ChartPoint> dailySales;
  final List<(String, double, int)> topItems;
  final List<(String, double, String)> lowStock;

  factory Dashboard.fromJson(Map<String, dynamic> j) {
    final k = j['kpis'] as Map<String, dynamic>? ?? const {};
    return Dashboard(
      salesToday: _d(k['salesToday']),
      ordersToday: _i(k['ordersToday']),
      customersToday: _i(k['customersToday']),
      pendingOrders: _i(k['pendingOrders']),
      expensesToday: _d(k['expensesToday']),
      inventoryAlerts: _i(k['inventoryAlerts']),
      dailySales: _list(j['dailySales']).map(ChartPoint.fromJson).toList(),
      topItems: _list(j['topItems']).map((t) => (_s(t['name']), _d(t['value']), _i(t['quantity']))).toList(),
      lowStock: _list(j['lowStock']).map((l) => (_s(l['name']), _d(l['quantity']), _s(l['unit']))).toList(),
    );
  }
}
