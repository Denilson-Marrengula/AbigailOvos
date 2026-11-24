import '../auth/auth_service.dart';

enum StockAlert { unavailable, empty, low, normal }

// The server supplies decimal text so comparison never relies on binary
// floating-point rounding for large quantities.
BigInt? _hundredths(String value) {
  final match = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(value);
  if (match == null) return null;
  final whole = BigInt.tryParse(match.group(2)!);
  if (whole == null) return null;
  final fraction = BigInt.parse((match.group(3) ?? '').padRight(2, '0'));
  final result = whole * BigInt.from(100) + fraction;
  return match.group(1) == '-' ? -result : result;
}

StockAlert stockAlert(Product product, StockBalance? balance) {
  if (balance == null) return StockAlert.unavailable;
  if (balance.available <= 0) return StockAlert.empty;
  if (product.minimumStock == null) return StockAlert.normal;
  final available = balance.availableText == null
      ? null
      : _hundredths(balance.availableText!);
  final minimum = _hundredths(product.minimumStock!);
  if (available == null || minimum == null) return StockAlert.unavailable;
  return available <= minimum ? StockAlert.low : StockAlert.normal;
}
