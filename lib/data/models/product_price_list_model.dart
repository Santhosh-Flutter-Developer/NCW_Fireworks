import '../../core/network/api_exception.dart';

/// One row of the Product Price table, as returned inside
/// `head.product_price_list` by `product.php`.
///
/// Known shape:
/// ```json
/// {
///   "sno": 1,
///   "pricelist_name": "SVA GB PRICE LIST 2026",
///   "product_name": "BEES (15 Item)",
///   "price": 250,
///   "price_unit_name": "BOX",
///   "discount": "OFF"
/// }
/// ```
class ProductPriceRow {
  final int sno;
  final String pricelistName;
  final String productName;
  final double price;
  final String unit;
  final bool discountEnabled;

  const ProductPriceRow({
    required this.sno,
    required this.pricelistName,
    required this.productName,
    required this.price,
    required this.unit,
    required this.discountEnabled,
  });

  factory ProductPriceRow.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['price'];
    final price = rawPrice is num
        ? rawPrice.toDouble()
        : double.tryParse(rawPrice?.toString() ?? '') ?? 0;

    final rawSno = json['sno'];
    final sno = rawSno is int ? rawSno : int.tryParse(rawSno?.toString() ?? '') ?? 0;

    return ProductPriceRow(
      sno: sno,
      pricelistName: (json['pricelist_name'] as String?)?.trim() ?? '',
      productName: (json['product_name'] as String?)?.trim() ?? '',
      price: price,
      unit: (json['price_unit_name'] as String?)?.trim() ?? '',
      discountEnabled:
          (json['discount'] as String?)?.trim().toUpperCase() == 'ON',
    );
  }

  /// Builds a row for a custom product added from the Quotation/
  /// Estimation product picker (see `CustomProductRepository`,
  /// `CacheKeys.customProductPending`) that hasn't been synced to the
  /// server yet, so it can show up in the Price Upload list the same way
  /// an ordinary catalogue row does. [pricelistName] is resolved by the
  /// caller from the queued row's `pricelist_id`, since the pending
  /// queue itself only carries the id, not the name.
  factory ProductPriceRow.fromCustomRow(
    Map<String, dynamic> row, {
    required String pricelistName,
    required int sno,
  }) {
    final rawPrice = row['price'];
    final price = rawPrice is num
        ? rawPrice.toDouble()
        : double.tryParse(rawPrice?.toString() ?? '') ?? 0;

    return ProductPriceRow(
      sno: sno,
      pricelistName: pricelistName,
      productName: row['product_name']?.toString().trim() ?? '',
      price: price,
      unit: row['unit_name']?.toString().trim() ?? '',
      discountEnabled: false,
    );
  }
}

/// One entry of the `head.pricelist` master list used to populate the
/// Pricelist filter/upload dropdown.
class PricelistOption {
  final String id;
  final String name;
  const PricelistOption({required this.id, required this.name});

  factory PricelistOption.fromJson(Map<String, dynamic> json) {
    return PricelistOption(
      id: (json['pricelist_id'] as String?)?.trim() ?? '',
      name: (json['pricelist_name'] as String?)?.trim() ?? '',
    );
  }
}

/// One entry of the `head.product_list` master list used to populate the
/// Product filter/upload dropdown.
class ProductOption {
  final String id;
  final String name;
  const ProductOption({required this.id, required this.name});

  factory ProductOption.fromJson(Map<String, dynamic> json) {
    return ProductOption(
      id: (json['product_id'] as String?)?.trim() ?? '',
      // The API HTML-escapes some names (e.g. `&quot;`), so this is
      // unescaped for display.
      name: _unescapeHtml((json['product_name'] as String?)?.trim() ?? ''),
    );
  }
}

String _unescapeHtml(String input) => input
    .replaceAll('&quot;', '"')
    .replaceAll('&amp;', '&')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

/// Parses the `{"head": {...}}` envelope returned by
/// `retail_mobile_app/API/product.php` for `product_view: "1"`.
class ProductPriceListResponse {
  final int code;
  final List<ProductPriceRow> rows;
  final List<PricelistOption> pricelists;
  final List<ProductOption> products;

  /// Total rows matching the current filters, independent of pagination —
  /// derived from the fully-synced local cache (see
  /// `ProductPriceRepository._cachedTotalCount`), not from this
  /// particular page's response. Null when there's no synced snapshot yet
  /// to count against, in which case the caller falls back to inferring
  /// "is there a next page" from whether this page came back full.
  final int? totalRecords;

  const ProductPriceListResponse({
    required this.code,
    required this.rows,
    required this.pricelists,
    required this.products,
    this.totalRecords,
  });

  factory ProductPriceListResponse.fromJson(Map<String, dynamic> json) {
    final head = json['head'];
    if (head is! Map) {
      throw const InvalidResponseException(
        'Server response was missing the expected "head" field.',
      );
    }

    final rawCode = head['code'];
    final code = rawCode is int
        ? rawCode
        : int.tryParse(rawCode?.toString() ?? '') ?? -1;

    List<Map<String, dynamic>> asMapList(dynamic raw) {
      if (raw is! List) return const [];
      return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }

    final rows = asMapList(head['product_price_list'])
        .map(ProductPriceRow.fromJson)
        .toList();
    final pricelists =
        asMapList(head['pricelist']).map(PricelistOption.fromJson).toList();
    final products =
        asMapList(head['product_list']).map(ProductOption.fromJson).toList();

    return ProductPriceListResponse(
      code: code,
      rows: rows,
      pricelists: pricelists,
      products: products,
    );
  }
}