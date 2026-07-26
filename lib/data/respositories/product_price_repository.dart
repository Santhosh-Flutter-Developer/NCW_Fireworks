import 'package:get/get.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/cache_keys.dart';
import '../../core/services/local_cache_service.dart';
import '../../core/utils/offline_filter_utils.dart';
import '../models/product_price_list_model.dart';

/// Reads the Product Price screen's data — always from the offline cache
/// that [DataSyncService]/the Sync button populate (see
/// `fetchPriceList`). The live `product_view` call itself is
/// [fetchLivePriceList], used only by [DataSyncService].
class ProductPriceRepository {
  ProductPriceRepository({
    ApiClient? apiClient,
    LocalCacheService? cacheService,
  })  : _apiClient = apiClient ?? ApiClient(),
        _cache = cacheService ?? Get.find<LocalCacheService>();

  final ApiClient _apiClient;
  final LocalCacheService _cache;

  /// Returns a page of the product price list — always from the offline
  /// cache that [DataSyncService]/the Sync button populate, regardless of
  /// whether the device currently has internet.
  ///
  /// The only thing that ever calls the live `product_view` endpoint is a
  /// manual tap of the Sync button (`DataSyncService.syncAllData`),
  /// which fetches the full, unpaginated list. Browsing the list itself
  /// never hits the network — this keeps behavior identical online and
  /// offline and means a flaky connection can never cause a half-loaded
  /// list or an unexpectedly slow screen while just looking at data.
  Future<ProductPriceListResponse> fetchPriceList({
    String pricelistId = '',
    String productId = '',
    int? pageNumber,
    int? pageLimit,
  }) async {
    return _priceListFromCache(
      pricelistId: pricelistId,
      productId: productId,
      pageNumber: pageNumber,
      pageLimit: pageLimit,
    );
  }

  /// Calls the live `product_view` endpoint directly, no cache fallback.
  /// This is the *only* method in the app that ever does — used
  /// exclusively by [DataSyncService] (both the post-login full sync and
  /// the per-page Sync button), to refresh the offline cache that
  /// [fetchPriceList] reads from. Throws on failure exactly like any
  /// other API call here; [DataSyncService] is what catches and reports
  /// it.
  Future<ProductPriceListResponse> fetchLivePriceList({
    String pricelistId = '',
    String productId = '',
    int? pageNumber,
    int? pageLimit,
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.productPrice,
      body: {
        'product_view': '1',
        'filter_pricelist_id': pricelistId,
        'filter_product_id': productId,
        if (pageNumber != null) 'page_number': '$pageNumber',
        if (pageLimit != null) 'page_limit': '$pageLimit',
      },
    );

    final result = ProductPriceListResponse.fromJson(json);
    if (result.code != 200) {
      throw InvalidResponseException(
        'Server returned an unexpected status (${result.code}).',
      );
    }
    return result;
  }

  /// Rows in the cache only carry pricelist/product *names* (same as the
  /// API), not ids, so a [pricelistId]/[productId] filter is resolved to
  /// a name via the cached dropdown options first, then matched by name.
  /// Returns every cached row matching the given filters, unpaginated —
  /// including any custom products added from the Quotation/Estimation
  /// product pickers that haven't been synced to the server yet (see
  /// `CustomProductRepository`/`CacheKeys.customProductPending`), listed
  /// first, ahead of the already-synced catalogue, so a newly-added one
  /// is immediately visible here too without waiting for the next Sync.
  List<ProductPriceRow> _filterCachedRows({
    required String pricelistId,
    required String productId,
  }) {
    final rows = _cache
        .getJsonList(CacheKeys.priceRows)
        .map(ProductPriceRow.fromJson)
        .toList();
    final pricelists = _cache
        .getJsonList(CacheKeys.priceLists)
        .map(PricelistOption.fromJson)
        .toList();
    final products = _cache
        .getJsonList(CacheKeys.priceProducts)
        .map(ProductOption.fromJson)
        .toList();

    String? nameForId(List<dynamic> options, String id) {
      for (final o in options) {
        if (o.id == id) return o.name as String;
      }
      return null;
    }

    // Pending custom products only carry a `pricelist_id`, so resolve it
    // to the same `pricelist_name` an already-synced row would carry,
    // via the same cached dropdown used for the filter above.
    final pendingCustom = _cache
        .getJsonList(CacheKeys.customProductPending)
        .map((row) => ProductPriceRow.fromCustomRow(
              row,
              pricelistName:
                  nameForId(pricelists, row['pricelist_id']?.toString() ?? '') ??
                      '',
              sno: 0,
            ))
        .toList();

    final pricelistName =
        pricelistId.isEmpty ? null : nameForId(pricelists, pricelistId);
    final productName =
        productId.isEmpty ? null : nameForId(products, productId);

    final filtered = [...pendingCustom, ...rows].where((r) {
      if (pricelistName != null && r.pricelistName != pricelistName) {
        return false;
      }
      if (productName != null && r.productName != productName) {
        return false;
      }
      return true;
    }).toList();

    // Re-number S.No sequentially now that pending custom rows have been
    // folded in at the front — keeps the column meaningful instead of
    // repeating "0" for every unsynced custom product.
    return [
      for (var i = 0; i < filtered.length; i++)
        ProductPriceRow(
          sno: i + 1,
          pricelistName: filtered[i].pricelistName,
          productName: filtered[i].productName,
          price: filtered[i].price,
          unit: filtered[i].unit,
          discountEnabled: filtered[i].discountEnabled,
        ),
    ];
  }

  ProductPriceListResponse _priceListFromCache({
    required String pricelistId,
    required String productId,
    required int? pageNumber,
    required int? pageLimit,
  }) {
    final filtered = _filterCachedRows(
      pricelistId: pricelistId,
      productId: productId,
    );
    final pricelists = _cache
        .getJsonList(CacheKeys.priceLists)
        .map(PricelistOption.fromJson)
        .toList();
    final products = _cache
        .getJsonList(CacheKeys.priceProducts)
        .map(ProductOption.fromJson)
        .toList();

    return ProductPriceListResponse(
      code: 200,
      rows: paginate(filtered, pageNumber, pageLimit),
      pricelists: pricelists,
      products: products,
      totalRecords: filtered.length,
    );
  }
}