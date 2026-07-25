import '../../../core/network/api_exception.dart';

/// A generic `{id, name}` pair for the category / unit dropdowns on the
/// Add Custom Product form.
class CustomProductOption {
  final String id;
  final String name;
  const CustomProductOption({required this.id, required this.name});

  @override
  String toString() => name;
}

/// Parses the `{"head": {...}}` envelope returned for an
/// `add_custom_product` call on `product.php` — the category and unit
/// dropdown data for the Add Custom Product form (see image 3 in the
/// original request: `category_list` of `{category_id, category_name}`).
/// The unit list is read the same way, under whichever of `unit_list` /
/// `units_list` the server sends — both are checked so this keeps
/// working regardless of which name the backend settles on.
class CustomProductInitResponseModel {
  final int code;
  final String message;
  final List<CustomProductOption> categories;
  final List<CustomProductOption> units;

  const CustomProductInitResponseModel({
    required this.code,
    required this.message,
    required this.categories,
    required this.units,
  });

  bool get isSuccess => code == 200;

  factory CustomProductInitResponseModel.fromJson(Map<String, dynamic> json) {
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

    final rawMsg = head['msg'];
    final message = (rawMsg is String && rawMsg.trim().isNotEmpty)
        ? rawMsg.trim()
        : 'Unexpected response from server.';

    List<CustomProductOption> readOptions(
      dynamic rawList,
      String idKey,
      String nameKey,
    ) {
      final options = <CustomProductOption>[];
      if (rawList is List) {
        for (final row in rawList) {
          if (row is Map) {
            options.add(CustomProductOption(
              id: row[idKey]?.toString() ?? '',
              name: row[nameKey]?.toString() ?? '',
            ));
          }
        }
      }
      return options;
    }

    return CustomProductInitResponseModel(
      code: code,
      message: message,
      categories: readOptions(
        head['category_list'],
        'category_id',
        'category_name',
      ),
      units: readOptions(
        head['unit_list'] ?? head['units_list'],
        'unit_id',
        'unit_name',
      ),
    );
  }
}

/// Parses the `{"head": {...}}` envelope returned for a `product_update`
/// call on `product.php` (used both for a single custom product add and
/// for the batched sync of everything queued offline).
class CustomProductSaveResponseModel {
  final int code;
  final String message;

  const CustomProductSaveResponseModel({
    required this.code,
    required this.message,
  });

  bool get isSuccess => code == 200;

  factory CustomProductSaveResponseModel.fromJson(Map<String, dynamic> json) {
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

    final rawMsg = head['msg'];
    final message = (rawMsg is String && rawMsg.trim().isNotEmpty)
        ? rawMsg.trim()
        : 'Unexpected response from server.';

    return CustomProductSaveResponseModel(code: code, message: message);
  }
}
