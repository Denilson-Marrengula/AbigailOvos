import 'package:abigailovos/auth/auth_service.dart';
import 'package:abigailovos/seller/stock_alert.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('alerta usa stock disponível e compara decimais sem arredondamento', () {
    const product = Product(
      name: 'Ovos',
      unit: 'bandeja',
      price: '1',
      minimumStock: '9007199254740992.01',
    );
    const equal = StockBalance(
      physical: 1,
      reserved: 0,
      available: 9007199254740992,
      availableText: '9007199254740992.01',
    );
    const above = StockBalance(
      physical: 1,
      reserved: 0,
      available: 9007199254740992,
      availableText: '9007199254740992.02',
    );
    expect(stockAlert(product, equal), StockAlert.low);
    expect(stockAlert(product, above), StockAlert.normal);
    expect(stockAlert(product, null), StockAlert.unavailable);
    expect(
      stockAlert(
        product,
        const StockBalance(
          physical: 5,
          reserved: 5,
          available: 0,
          availableText: '0.00',
        ),
      ),
      StockAlert.empty,
    );
    expect(
      stockAlert(
        product,
        const StockBalance(physical: 1, reserved: 0, available: 1),
      ),
      StockAlert.unavailable,
    );
  });
}
