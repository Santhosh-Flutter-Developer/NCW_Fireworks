import 'package:get/get.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/cache_keys.dart';
import '../../core/services/local_cache_service.dart';
import '../models/custom_product/custom_product_models.dart';

/// Which product picker a queued custom product (or a sync run) belongs
/// to — Quotation and Estimation each keep their own pending queue and
/// are synced independently, from their own Sync button.
enum CustomProductModule { quotation, estimation }

extension CustomProductModuleX on CustomProductModule {
  String get _cacheKey {
    switch (this) {
      case CustomProductModule.quotation:
        return CacheKeys.quotationCustomProductPending;
      case CustomProductModule.estimation:
        return CacheKeys.estimationCustomProductPending;
    }
  }
}

/// Talks to `product.php` for the Add Custom Product feature that backs
/// the Quotation and Estimation product pickers.
///
/// Same offline-first shape as every other repository here: adding a
/// custom product from either picker never calls the network directly —
/// it's queued via [queueCustomProduct], and only sent to the server via
/// [syncPendingCustomProducts] when the person taps Sync on the
/// Quotation/Estimation screen (see `DataSyncService`), *before* that
/// screen's own pending quotations/estimates go out, since a line item
/// referencing a custom product's locally-generated id needs the server
/// to already know that id.
class CustomProductRepository {
  CustomProductRepository({
    ApiClient? apiClient,
    LocalCacheService? cacheService,
  })  : _apiClient = apiClient ?? ApiClient(),
        _cache = cacheService ?? Get.find<LocalCacheService>();

  final ApiClient _apiClient;
  final LocalCacheService _cache;

  /// Fetches the category/unit dropdown data for the Add Custom Product
  /// form. Only ever called by [DataSyncService] (post-login sync and the
  /// per-page Sync button) to refresh the offline cache that
  /// [cachedCategories]/[cachedUnits] read from — the form itself never
  /// touches the network.
  Future<CustomProductInitResponseModel> getInitData() async {
    final json = await _apiClient.postJson(
      ApiEndpoints.productPrice,
      body: {'add_custom_product': '1'},
    );

    final result = CustomProductInitResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Category dropdown options for the Add Custom Product form — synced
  /// once at login/Sync, read here with no network call.
  List<CustomProductOption> cachedCategories() => _cache
      .getJsonList(CacheKeys.customProductCategories)
      .map((m) => CustomProductOption(
            id: m['id']?.toString() ?? '',
            name: m['name']?.toString() ?? '',
          ))
      .toList();

  /// Unit dropdown options for the Add Custom Product form — same
  /// refresh cycle as [cachedCategories].
  List<CustomProductOption> cachedUnits() => _cache
      .getJsonList(CacheKeys.customProductUnits)
      .map((m) => CustomProductOption(
            id: m['id']?.toString() ?? '',
            name: m['name']?.toString() ?? '',
          ))
      .toList();

  /// Every custom product added on this device for [module] and
  /// [pricelistId] that hasn't been synced yet — shaped so the product
  /// picker can show it as an ordinary product option alongside the
  /// synced catalogue. Persists across app restarts (backed by the same
  /// Hive cache as everything else) and disappears once
  /// [syncPendingCustomProducts] succeeds and folds it into the next
  /// catalogue sync.
  List<Map<String, dynamic>> cachedCustomProductsForPricelist(
    CustomProductModule module,
    String pricelistId,
  ) =>
      _cache
          .getJsonList(module._cacheKey)
          .where((m) => m['pricelist_id']?.toString() == pricelistId)
          .toList();

  /// Adds one new custom product to [module]'s on-device pending queue.
  /// [editId] is generated on this device (see `IdGenerator.generate`)
  /// and doubles as the product's permanent id from here on — the same
  /// pattern already used for a Quotation's/Estimate's own `edit_id` —
  /// so it can be used immediately as this line's `product_id` on the
  /// quotation/estimate form without waiting for a server round trip.
  Future<void> queueCustomProduct({
    required CustomProductModule module,
    required String editId,
    required String categoryId,
    String categoryName = '',
    required String productName,
    required String unitId,
    String unitName = '',
    required String pricelistId,
    required String price,
  }) async {
    final key = module._cacheKey;
    final pending = _cache.getJsonList(key);
    final row = <String, dynamic>{
      'edit_id': editId,
      'category_id': categoryId,
      'category_name': categoryName,
      'product_name': productName,
      'unit_id': unitId,
      'unit_name': unitName,
      'pricelist_id': pricelistId,
      'price': price,
    };
    final updated = [
      ...pending.where((p) => p['edit_id'] != editId),
      row,
    ];
    await _cache.putJsonList(key, updated);
  }

  /// Number of custom products added on this device for [module] that
  /// haven't been sent to the server yet.
  int pendingCount(CustomProductModule module) =>
      _cache.getJsonList(module._cacheKey).length;

  /// Sends every queued custom product for [module] to `product.php` in
  /// one batch call (`product_update` / `product_data: [...]`, matching
  /// the shape the endpoint expects — see the original request's
  /// reference screenshot). Only ever called from the Sync button (via
  /// `DataSyncService`), and always before that same sync pushes the
  /// pending quotations/estimates that may reference these products'
  /// `edit_id` as their `product_id`.
  ///
  /// On success, clears [module]'s queue. On failure, the queue is left
  /// untouched so nothing saved on the device is lost — the next Sync
  /// attempt retries the same batch, and (by design) the quotation/
  /// estimate sync that would follow never runs this time either, since
  /// [DataSyncService] lets this throw and stops that section's sync.
  Future<CustomProductSaveResponseModel> syncPendingCustomProducts({
    required CustomProductModule module,
    required String creator,
  }) async {
    final key = module._cacheKey;
    final pending = _cache.getJsonList(key);
    if (pending.isEmpty) {
      return const CustomProductSaveResponseModel(
        code: 200,
        message: 'Nothing to sync',
      );
    }

    final productData = pending
        .map((row) => {
              'edit_id': row['edit_id'] ?? '',
              'category_id': row['category_id'] ?? '',
              'product_name': row['product_name'] ?? '',
              'unit_id': row['unit_id'] ?? '',
              'pricelist_id': row['pricelist_id'] ?? '',
              'price': row['price'] ?? '',
            })
        .toList();

    final json = await _apiClient.postJson(
      ApiEndpoints.productPrice,
      body: {
        'product_update': '1',
        'creator': creator,
        'product_data': productData,
      },
    );

    final result = CustomProductSaveResponseModel.fromJson(json);
    if (!result.isSuccess) {
      throw ApiRequestException(result.message);
    }

    await _cache.putJsonList(key, []);
    return result;
  }
}
