/// Forma de pago sugerida a la app ReciboPagos (extra `tipo`).
enum RecibopagosPaymentType {
  credit('credito'),
  debit('debito');

  const RecibopagosPaymentType(this.wire);

  /// Valor que viaja en el Intent.
  final String wire;
}

/// Cobro a lanzar contra la app ReciboPagos.
class RecibopagosChargeRequest {
  /// Monto en pesos enteros (extra `monto`). Debe ser > 0: en 0 la app RP
  /// abre en modo normal en vez de cobrar.
  final int amount;

  /// Id de orden (extra `orden_id`). Vuelve como `order_id` y es la llave
  /// para conciliar con [RecibopagosClient.lastCharge]. Enviarlo siempre.
  final String orderId;

  /// Id de transacción de nuestro sistema (extra `id_transaction`).
  final String? transactionId;

  /// Forma de pago sugerida (extra `tipo`). `null` = la elige el cajero.
  final RecibopagosPaymentType? paymentType;

  /// Venta exenta de IVA (extra `exempt` = 1).
  final bool exempt;

  /// Salta la calculadora y va directo al cobro (extra `exit_wallet`).
  final bool skipKeypad;

  const RecibopagosChargeRequest({
    required this.amount,
    required this.orderId,
    this.transactionId,
    this.paymentType,
    this.exempt = false,
    this.skipKeypad = true,
  });

  /// Extras del Intent, con los nombres y tipos de la doc oficial.
  Map<String, Object?> toExtras({String? channel}) {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'debe ser mayor a 0');
    }
    return <String, Object?>{
      'monto': amount,
      'orden_id': orderId,
      'exit_wallet': skipKeypad,
      'exempt': exempt ? 1 : 0,
      if (transactionId != null) 'id_transaction': transactionId,
      if (paymentType != null) 'tipo': paymentType!.wire,
      if (channel != null) 'channel': channel,
    };
  }
}

/// Cobro **aprobado** (`status_paid == "paid"`).
class RecibopagosChargeResponse {
  final String orderId;
  final String transactionId;
  final String authorizationCode;
  final String cardLastDigits;

  /// `CREDITO` o `DEBITO`, tal como lo envía ReciboPagos.
  final String paymentMethod;

  /// Número de cuotas. 0 = contado.
  final int installments;

  /// Propina cobrada, en pesos.
  final int gratuity;

  /// Total pagado, propina incluida.
  final int paidAmount;
  final String terminalSerial;

  /// Extras crudos del Intent de respuesta, para logs y soporte.
  final Map<String, Object?> raw;

  const RecibopagosChargeResponse({
    required this.orderId,
    required this.transactionId,
    required this.authorizationCode,
    required this.cardLastDigits,
    required this.paymentMethod,
    required this.installments,
    required this.gratuity,
    required this.paidAmount,
    required this.terminalSerial,
    required this.raw,
  });

  factory RecibopagosChargeResponse.fromExtras(Map<String, Object?> e) =>
      RecibopagosChargeResponse(
        orderId: _readString(e, 'order_id'),
        transactionId: _readString(e, 'transaction_id'),
        authorizationCode: _readString(e, 'authorization_code'),
        cardLastDigits: _readString(e, 'card_last_digits'),
        paymentMethod: _readString(e, 'payment_method'),
        installments: _readInt(e, 'installments'),
        gratuity: _readInt(e, 'gratuity'),
        paidAmount: _readInt(e, 'paid_amount'),
        terminalSerial: _readString(e, 'terminal_serial'),
        raw: e,
      );

  @override
  String toString() =>
      'RecibopagosChargeResponse(orderId: $orderId, paidAmount: $paidAmount, '
      'auth: $authorizationCode, last4: $cardLastDigits)';
}

/// Último cobro según el ContentProvider de respaldo de ReciboPagos.
///
/// Sirve para conciliar si nuestra app murió antes de recibir el resultado.
/// No reemplaza a [RecibopagosClient.charge].
class RecibopagosLastCharge {
  final String orderId;

  /// Veredicto: solo `paid` es aprobado.
  final String statusPaid;
  final String estado;
  final String resultCode;
  final String transactionId;

  /// Datos crudos aplanados del provider.
  final Map<String, Object?> raw;

  const RecibopagosLastCharge({
    required this.orderId,
    required this.statusPaid,
    required this.estado,
    required this.resultCode,
    required this.transactionId,
    required this.raw,
  });

  bool get isPaid => statusPaid == 'paid';

  /// Aplana las filas del cursor. La doc no fija el esquema, así que acepta
  /// filas `key`/`value` (estilo SharedPreferences) y filas con columnas.
  factory RecibopagosLastCharge.fromRows(List<Map<String, Object?>> rows) {
    final Map<String, Object?> flat = <String, Object?>{};
    for (final Map<String, Object?> row in rows) {
      if (row.containsKey('key') && row.containsKey('value')) {
        flat['${row['key']}'] = row['value'];
      } else {
        flat.addAll(row);
      }
    }
    return RecibopagosLastCharge(
      orderId: _readString(flat, 'order_id'),
      statusPaid: _readString(flat, 'status_paid'),
      estado: _readString(flat, 'estado'),
      resultCode: _readString(flat, 'result_code'),
      transactionId: _readString(flat, 'transaction_id'),
      raw: flat,
    );
  }

  @override
  String toString() =>
      'RecibopagosLastCharge(orderId: $orderId, statusPaid: $statusPaid)';
}

// La doc advierte que en cancelaciones los extras pueden llegar ausentes o
// null, y no fija si los numéricos viajan como int o String: se lee tolerante.

String _readString(Map<String, Object?> e, String key) => e[key]?.toString() ?? '';

int _readInt(Map<String, Object?> e, String key) {
  final Object? v = e[key];
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}'.trim()) ?? 0;
}
