/// Resolves a user-entered Add/Discount/Deduction value that may be either
/// a plain rupee amount (e.g. "150") or a percentage of [base] when suffixed
/// with `%` (e.g. "10%" on a ₹2100 base resolves to ₹210).
///
/// Empty or unparsable input resolves to 0. The result is rounded to 2
/// decimal places, same precision used everywhere else in the money UI.
double resolvePercentOrAmount(String input, double base) {
  final text = input.trim();
  if (text.isEmpty) return 0;

  if (text.endsWith('%')) {
    final pctText = text.substring(0, text.length - 1).trim();
    final pct = double.tryParse(pctText);
    if (pct == null) return 0;
    return double.parse((base * pct / 100).toStringAsFixed(2));
  }

  final amount = double.tryParse(text);
  return amount == null ? 0 : double.parse(amount.toStringAsFixed(2));
}