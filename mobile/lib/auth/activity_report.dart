/// Valores fornecidos pelo backend, sem conversão de dinheiro para double.
class ActivityCustomer {
  const ActivityCustomer({
    required this.id,
    required this.name,
    required this.phone,
    required this.operations,
    required this.amount,
  });
  final String id;
  final String name;
  final String? phone;
  final int operations;
  final String amount;
}

class ActivityMethod {
  const ActivityMethod({
    required this.method,
    required this.operations,
    required this.amount,
  });
  final String method;
  final int operations;
  final String amount;
}

class ActivitySeller {
  const ActivitySeller({
    required this.seller,
    required this.operations,
    required this.amount,
  });
  final String seller;
  final int operations;
  final String amount;
}

class ActivityItem {
  const ActivityItem({
    required this.name,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });
  final String name;
  final String unit;
  final String quantity;
  final String unitPrice;
  final String lineTotal;
}

class ActivityOperation {
  const ActivityOperation({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.seller,
    required this.amount,
    required this.createdAt,
    required this.deliveredAt,
    required this.paidAt,
    required this.deliveryStatus,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.items,
  });
  final String id;
  final String customerName;
  final String? customerPhone;
  final String seller;
  final String amount;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? paidAt;
  final String deliveryStatus;
  final String paymentStatus;
  final String? paymentMethod;
  final List<ActivityItem> items;
}

class ActivityReport {
  const ActivityReport({
    required this.periodStart,
    required this.periodEnd,
    required this.queriedAt,
    required this.unknownDeliveredDates,
    required this.unknownPaidDates,
    required this.deliveredAmount,
    required this.debtAmount,
    required this.pendingOrderAmount,
    required this.paidAmount,
    required this.deliveredCustomers,
    required this.debtCustomers,
    required this.pendingOrders,
    required this.paymentMethods,
    required this.payments,
    required this.sellers,
    required this.deliveries,
  });
  final String periodStart;
  final String periodEnd;
  final DateTime queriedAt;
  final int unknownDeliveredDates;
  final int unknownPaidDates;
  final String deliveredAmount;
  final String debtAmount;
  final String pendingOrderAmount;
  final String paidAmount;
  final List<ActivityCustomer> deliveredCustomers;
  final List<ActivityCustomer> debtCustomers;
  final List<ActivityOperation> pendingOrders;
  final List<ActivityMethod> paymentMethods;
  final List<ActivityOperation> payments;
  final List<ActivitySeller> sellers;
  final List<ActivityOperation> deliveries;

  factory ActivityReport.fromJson(
    dynamic value, {
    required String from,
    required String to,
  }) {
    final data = _map(value);
    if (data['periodStart'] != from ||
        data['periodEnd'] != to ||
        data['timeZone'] != 'Africa/Maputo') {
      throw const FormatException('Período ou fuso inválido');
    }
    final report = ActivityReport(
      periodStart: from,
      periodEnd: to,
      queriedAt: _instant(data['queriedAt']),
      unknownDeliveredDates: _count(data['unknownDeliveredDates']),
      unknownPaidDates: _count(data['unknownPaidDates']),
      deliveredAmount: _decimal(data['deliveredAmount']),
      debtAmount: _decimal(data['debtAmount']),
      pendingOrderAmount: _decimal(data['pendingOrderAmount']),
      paidAmount: _decimal(data['paidAmount']),
      deliveredCustomers: _list(data['deliveredCustomers'], _customer),
      debtCustomers: _list(data['debtCustomers'], _customer),
      pendingOrders: _list(data['pendingOrders'], _operation),
      paymentMethods: _list(data['paymentMethods'], _method),
      payments: _list(data['payments'], _operation),
      sellers: _list(data['sellers'], (value) {
        final seller = _map(value);
        return ActivitySeller(
          seller: _text(seller['seller']),
          operations: _count(seller['operations']),
          amount: _decimal(seller['amount']),
        );
      }),
      deliveries: _list(data['deliveries'], _operation),
    );
    // Do not present an incomplete or inconsistent breakdown as a financial total.
    final methods = report.paymentMethods.map((entry) => entry.method).toSet();
    final count = report.paymentMethods.fold<int>(
      0,
      (sum, entry) => sum + entry.operations,
    );
    BigInt cents(String value) => BigInt.parse(value.replaceAll('.', ''));
    final amount = report.paymentMethods.fold<BigInt>(
      BigInt.zero,
      (sum, entry) => sum + cents(entry.amount),
    );
    if (methods.length != 5 ||
        report.paymentMethods.length != 5 ||
        count != report.payments.length ||
        amount != cents(report.paidAmount)) {
      throw const FormatException('Discriminação de pagamentos incompleta');
    }
    for (final method in report.paymentMethods) {
      final matching = report.payments.where(
        (sale) => (sale.paymentMethod ?? 'UNKNOWN') == method.method,
      );
      final actualAmount = matching.fold<BigInt>(
        BigInt.zero,
        (sum, sale) => sum + cents(sale.amount),
      );
      if (matching.length != method.operations ||
          actualAmount != cents(method.amount)) {
        throw const FormatException('Pagamentos não correspondem aos totais');
      }
    }
    final start = DateTime.parse('${from}T00:00:00Z')
        .subtract(const Duration(hours: 2));
    final end = DateTime.parse('${to}T00:00:00Z')
        .add(const Duration(days: 1))
        .subtract(const Duration(hours: 2));
    bool inPeriod(DateTime? date) =>
        date != null && !date.isBefore(start) && date.isBefore(end);
    if (report.deliveries.any(
          (sale) =>
              sale.deliveryStatus != 'DELIVERED' || !inPeriod(sale.deliveredAt),
        ) ||
        report.payments.any(
          (sale) =>
              sale.paymentStatus != 'PAID' ||
              sale.deliveryStatus == 'CANCELLED' ||
              !inPeriod(sale.paidAt),
        ) ||
        report.pendingOrders.any((sale) => sale.deliveryStatus != 'PENDING')) {
      throw const FormatException(
        'Operações fora do período ou com estado inválido',
      );
    }
    return report;
  }
}

Map _map(dynamic value) {
  if (value is! Map) throw const FormatException('Objeto inválido');
  return value;
}

String _text(dynamic value) {
  if (value is! String || value.isEmpty) {
    throw const FormatException('Texto inválido');
  }
  return value;
}

String? _optionalText(dynamic value) => value == null ? null : _text(value);

int _count(dynamic value) {
  if (value is! int || value < 0) {
    throw const FormatException('Contagem inválida');
  }
  return value;
}

String _decimal(dynamic value, {bool money = true}) {
  final text = _text(value);
  final pattern = money ? r'^\d+\.\d{2}$' : r'^\d+(\.\d{1,2})?$';
  if (!RegExp(pattern).hasMatch(text)) {
    throw const FormatException('Decimal inválido');
  }
  return text;
}

DateTime _instant(dynamic value) {
  final parsed = DateTime.tryParse(_text(value));
  if (parsed == null || !parsed.isUtc) {
    throw const FormatException('Data inválida');
  }
  return parsed;
}

DateTime? _optionalInstant(dynamic value) =>
    value == null ? null : _instant(value);

List<T> _list<T>(dynamic value, T Function(dynamic) parse) {
  if (value is! List) throw const FormatException('Lista inválida');
  return value.map(parse).toList(growable: false);
}

ActivityCustomer _customer(dynamic value) {
  final data = _map(value);
  return ActivityCustomer(
    id: _text(data['customerId']),
    name: _text(data['name']),
    phone: _optionalText(data['phone']),
    operations: _count(data['operations']),
    amount: _decimal(data['amount']),
  );
}

ActivityMethod _method(dynamic value) {
  final data = _map(value);
  final method = _text(data['method']);
  if (!const {'EMOLA', 'MPESA', 'BANK', 'CASH', 'UNKNOWN'}.contains(method)) {
    throw const FormatException('Meio de pagamento inválido');
  }
  return ActivityMethod(
    method: method,
    operations: _count(data['operations']),
    amount: _decimal(data['amount']),
  );
}

ActivityOperation _operation(dynamic value) {
  final data = _map(value);
  final delivery = _text(data['deliveryStatus']);
  final payment = _text(data['paymentStatus']);
  final method = _optionalText(data['paymentMethod']);
  if (!const {'PENDING', 'DELIVERED', 'CANCELLED'}.contains(delivery) ||
      !const {'PENDING', 'PAID'}.contains(payment) ||
      (method != null &&
          !const {'EMOLA', 'MPESA', 'BANK', 'CASH'}.contains(method))) {
    throw const FormatException('Estado inválido');
  }
  return ActivityOperation(
    id: _text(data['id']),
    customerName: _text(data['customerName']),
    customerPhone: _optionalText(data['customerPhone']),
    seller: _text(data['seller']),
    amount: _decimal(data['amount']),
    createdAt: _instant(data['createdAt']),
    deliveredAt: _optionalInstant(data['deliveredAt']),
    paidAt: _optionalInstant(data['paidAt']),
    deliveryStatus: delivery,
    paymentStatus: payment,
    paymentMethod: method,
    items: _list(data['items'], (value) {
      final item = _map(value);
      return ActivityItem(
        name: _text(item['name']),
        unit: _text(item['unit']),
        quantity: _decimal(item['quantity'], money: false),
        unitPrice: _decimal(item['unitPrice']),
        lineTotal: _decimal(item['lineTotal']),
      );
    }),
  );
}
