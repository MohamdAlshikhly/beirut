class Category {
  final int id;
  final String name;

  Category({required this.id, required this.name});

  factory Category.fromJson(Map<String, dynamic> json) =>
      Category(id: json['id'], name: json['name']);
}

class Product {
  final int id;
  final String name;
  final String? barcode;
  final double price;
  final double? costPrice;
  final double quantity;
  final int? categoryId;
  final String? imageUrl;
  final int? baseUnitId;
  final double baseUnitConversion;
  final bool isCard;

  Product({
    required this.id,
    required this.name,
    this.barcode,
    required this.price,
    this.costPrice,
    required this.quantity,
    this.categoryId,
    this.imageUrl,
    this.baseUnitId,
    this.baseUnitConversion = 1.0,
    this.isCard = false,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'],
    name: json['name'],
    barcode: json['barcode'],
    price: (json['price'] as num).toDouble(),
    costPrice: json['cost_price'] != null
        ? (json['cost_price'] as num).toDouble()
        : null,
    quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
    categoryId: json['category_id'],
    imageUrl: json['image_url'],
    baseUnitId: json['base_unit_id'],
    baseUnitConversion:
        (json['base_unit_conversion'] as num?)?.toDouble() ?? 1.0,
    isCard: (json['is_card'] as num?)?.toInt() == 1,
  );

  Product copyWith({
    int? id,
    String? name,
    String? barcode,
    double? price,
    double? costPrice,
    double? quantity,
    int? categoryId,
    String? imageUrl,
    int? baseUnitId,
    double? baseUnitConversion,
    bool? isCard,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      price: price ?? this.price,
      costPrice: costPrice ?? this.costPrice,
      quantity: quantity ?? this.quantity,
      categoryId: categoryId ?? this.categoryId,
      imageUrl: imageUrl ?? this.imageUrl,
      baseUnitId: baseUnitId ?? this.baseUnitId,
      baseUnitConversion: baseUnitConversion ?? this.baseUnitConversion,
      isCard: isCard ?? this.isCard,
    );
  }
}

class CardItem {
  final int id;
  final String name;
  final int productId;
  final int price;
  final int spendedBalance;

  CardItem({
    required this.id,
    required this.name,
    required this.productId,
    required this.price,
    required this.spendedBalance,
  });

  factory CardItem.fromJson(Map<String, dynamic> json) => CardItem(
    id: json['id'],
    name: json['name'] ?? '',
    productId: json['productId'] ?? json['product_id'],
    price: (json['price'] as num?)?.toInt() ?? 0,
    spendedBalance: (json['spended_balance'] as num?)?.toInt() ?? 0,
  );
}

class AppUser {
  final int id;
  final String name;
  final String role; // 'admin', 'cashier'
  final String? password;

  AppUser({
    required this.id,
    required this.name,
    required this.role,
    this.password,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'],
    name: json['name'],
    role: json['role'],
    password: json['password']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role,
    'password': password,
  };
}

class SessionLog {
  final int id;
  final int userId;
  final String? userName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final bool isActive;

  SessionLog({
    required this.id,
    required this.userId,
    this.userName,
    required this.startedAt,
    this.endedAt,
    required this.isActive,
  });

  factory SessionLog.fromJson(Map<String, dynamic> json) => SessionLog(
    id: json['id'],
    userId: json['user_id'],
    userName:
        json['user_name'] ??
        (json['users'] != null ? json['users']['name'] : null),
    startedAt: DateTime.parse(json['started_at']).toLocal(),
    endedAt: json['ended_at'] != null
        ? DateTime.parse(json['ended_at']).toLocal()
        : null,
    isActive: json['is_active'] == true || json['is_active'] == 1,
  );
}

class Sale {
  final int? id;
  final double totalPrice;
  final String paymentType; // 'cash', 'card'
  final DateTime? createdAt;
  final int? userId;
  final bool? isSynced;

  Sale({
    this.id,
    required this.totalPrice,
    required this.paymentType,
    this.createdAt,
    this.userId,
    this.isSynced = false,
  });

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'total_price': totalPrice,
    'payment_type': paymentType,
    if (userId != null) 'user_id': userId,
    'is_synced': isSynced,
  };

  factory Sale.fromJson(Map<String, dynamic> json) => Sale(
    id: json['id'],
    totalPrice: (json['total_price'] as num).toDouble(),
    paymentType: json['payment_type'],
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'])
        : null,
    userId: json['user_id'],
    isSynced: json['is_synced'] == true || json['is_synced'] == 1,
  );
}

class SaleItem {
  final int? id;
  final int? saleId;
  final int productId;
  final double quantity;
  final double price;

  SaleItem({
    this.id,
    this.saleId,
    required this.productId,
    required this.quantity,
    required this.price,
  });

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    if (saleId != null) 'sale_id': saleId,
    'product_id': productId,
    'quantity': quantity,
    'price': price,
  };

  factory SaleItem.fromJson(Map<String, dynamic> json) => SaleItem(
    id: json['id'],
    saleId: json['sale_id'],
    productId: json['product_id'],
    quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
    price: (json['price'] as num).toDouble(),
  );
}

class StockMovement {
  final int? id;
  final int productId;
  final double change;
  final String? reason;

  StockMovement({
    this.id,
    required this.productId,
    required this.change,
    this.reason,
  });

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'product_id': productId,
    'change': change,
    'reason': reason,
  };
}

class Balance {
  final int id;
  final DateTime createdAt;
  final int currentBalance;

  Balance({
    required this.id,
    required this.createdAt,
    required this.currentBalance,
  });

  factory Balance.fromJson(Map<String, dynamic> json) => Balance(
    id: json['id'],
    createdAt: DateTime.parse(json['created_at']),
    currentBalance: json['currentBalance'] ?? 0,
  );
}
