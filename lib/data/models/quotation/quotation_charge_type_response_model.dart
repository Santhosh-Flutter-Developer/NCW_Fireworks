import '../../../core/network/api_exception.dart';

/// Parses the `{"head": {...}}` envelope returned for a
/// `type_other_charges_id` call — tells the UI whether a chosen charge is
/// added ("Plus") or deducted ("Minus") before it's added to the form.
/// Mirrors `EstimateChargeTypeResponseModel` on the Estimate side.
class QuotationChargeTypeResponseModel {
  final int code;
  final String message;
  final String chargesType; // "Plus" or "Minus"

  const QuotationChargeTypeResponseModel({
    required this.code,
    required this.message,
    required this.chargesType,
  });

  bool get isSuccess => code == 200;

  factory QuotationChargeTypeResponseModel.fromJson(
      Map<String, dynamic> json) {
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

    return QuotationChargeTypeResponseModel(
      code: code,
      message: message,
      chargesType: head['charges_type']?.toString() ?? 'Plus',
    );
  }
}