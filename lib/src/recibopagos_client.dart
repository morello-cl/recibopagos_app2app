import 'dart:developer' as developer;

import 'package:flutter/services.dart';

import 'models.dart';
import 'recibopagos_exception.dart';

/// Nombre del `MethodChannel`; coincide con `CHANNEL_NAME` en Kotlin.
const String recibopagosChannelName = 'cl.mufin.recibopagos_app2app';

/// `Activity.RESULT_OK`.
const int _resultOk = -1;

enum RecibopagosMode {
  /// Cobra contra la app real, sin logs.
  production,

  /// Cobra contra la app real y loggea request/response.
  debug,

  /// No toca Android: simula la respuesta según [RecibopagosMockOutcome].
  mock,
}

/// Resultado simulado en [RecibopagosMode.mock].
enum RecibopagosMockOutcome {
  approved,
  cancelled,
  timeout,
  rejected,
  failed,

  /// `resultCode -5` sin extras: equipo sin modo intent o back del cajero.
  notInIntentMode,
}

/// Cliente App To App de ReciboPagos.
///
/// Doc oficial: https://recibopagos.com/desarrolladores/app-to-app
///
/// ```dart
/// final rp = RecibopagosClient(channel: 'DTEx');
/// if (!await rp.isInstalled()) return;
/// try {
///   final r = await rp.charge(
///     const RecibopagosChargeRequest(amount: 12500, orderId: 'VENTA-1'),
///   );
///   // aprobado: r.paidAmount, r.authorizationCode
/// } on RecibopagosCancelledException {
///   // cancelado o equipo sin modo intent
/// } on RecibopagosException catch (e) {
///   // timeout / rechazado / failed / desconocido
/// }
/// ```
class RecibopagosClient {
  final RecibopagosMode mode;

  /// Identifica a la app que llama (extra `channel`), p. ej. `DTEx`.
  final String? channel;

  final RecibopagosMockOutcome mockOutcome;
  final Duration mockDelay;

  final MethodChannel _method;

  RecibopagosClient({
    this.mode = RecibopagosMode.production,
    this.channel,
    this.mockOutcome = RecibopagosMockOutcome.approved,
    this.mockDelay = const Duration(seconds: 2),
    MethodChannel? methodChannel,
  }) : _method = methodChannel ?? const MethodChannel(recibopagosChannelName);

  /// `true` si la app ReciboPagos está instalada y acepta cobros por Intent.
  /// No dice si el equipo está en modo intent: eso solo se sabe al cobrar.
  Future<bool> isInstalled() async {
    if (mode == RecibopagosMode.mock) return true;
    try {
      return await _method.invokeMethod<bool>('isInstalled') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Lanza el cobro y espera el resultado.
  ///
  /// Retorna **solo** si `status_paid == "paid"`. Cualquier otro desenlace
  /// lanza una subclase de [RecibopagosException].
  Future<RecibopagosChargeResponse> charge(
    RecibopagosChargeRequest request,
  ) async {
    final Map<String, Object?> extras = request.toExtras(channel: channel);
    _log('charge → $extras');

    final Map<Object?, Object?>? result;
    if (mode == RecibopagosMode.mock) {
      result = await _simulate(extras);
    } else {
      try {
        result = await _method.invokeMapMethod<Object?, Object?>(
          'charge',
          <String, Object?>{'extras': extras},
        );
      } on PlatformException catch (e) {
        _log('charge ✗ ${e.code} ${e.message}');
        if (e.code == 'MFN-04') {
          throw RecibopagosNotInstalledException(e.message ?? 'No instalada');
        }
        throw RecibopagosUnknownException(
          e.message ?? 'Error nativo',
          code: e.code,
        );
      }
    }
    _log('charge ← $result');
    return parseResult(result, sentOrderId: request.orderId);
  }

  /// Último cobro según el ContentProvider de ReciboPagos, o `null` si no hay
  /// datos. Para conciliar cuando nuestra app murió durante el cobro: comparar
  /// [RecibopagosLastCharge.orderId] con la orden pendiente.
  Future<RecibopagosLastCharge?> lastCharge() async {
    if (mode == RecibopagosMode.mock) return null;
    final List<Object?>? rows;
    try {
      rows = await _method.invokeListMethod<Object?>('lastCharge');
    } on PlatformException catch (e) {
      throw RecibopagosUnknownException(
        e.message ?? 'Error leyendo provider',
        code: e.code,
      );
    }
    if (rows == null || rows.isEmpty) return null;
    return RecibopagosLastCharge.fromRows(<Map<String, Object?>>[
      for (final Object? r in rows)
        if (r is Map) r.cast<String, Object?>(),
    ]);
  }

  /// Interpreta la respuesta nativa `{resultCode, extras}`.
  ///
  /// Expuesto para tests; las apps usan [charge].
  static RecibopagosChargeResponse parseResult(
    Map<Object?, Object?>? result, {
    required String sentOrderId,
  }) {
    final int? resultCode = result?['resultCode'] as int?;
    final Object? rawExtras = result?['extras'];
    final Map<String, Object?> extras = rawExtras is Map
        ? rawExtras.cast<String, Object?>()
        : const <String, Object?>{};
    final String status = extras['status_paid']?.toString() ?? '';

    switch (status) {
      case 'paid':
        // RESULT_OK no implica pago; `paid` sí, aunque el resultCode sea raro.
        final RecibopagosChargeResponse r =
            RecibopagosChargeResponse.fromExtras(extras);
        if (r.orderId.isNotEmpty && r.orderId != sentOrderId) {
          throw RecibopagosUnknownException(
            'order_id "${r.orderId}" no coincide con "$sentOrderId"',
            statusPaid: status,
            resultCode: resultCode,
            raw: extras,
          );
        }
        return r;
      case 'cancel':
        throw RecibopagosCancelledException('Cobro cancelado',
            statusPaid: status, resultCode: resultCode, raw: extras);
      case 'timeout':
        throw RecibopagosTimeoutException('El cobro caducó',
            statusPaid: status, resultCode: resultCode, raw: extras);
      case 'rechazado':
        throw RecibopagosRejectedException('Pago rechazado',
            statusPaid: status, resultCode: resultCode, raw: extras);
      case 'failed':
        throw RecibopagosFailedException('Falla en ReciboPagos',
            statusPaid: status, resultCode: resultCode, raw: extras);
    }

    if (resultCode != _resultOk) {
      throw RecibopagosCancelledException(
        'Cancelado, rechazado o equipo sin modo intent',
        statusPaid: status.isEmpty ? null : status,
        resultCode: resultCode,
        raw: extras,
      );
    }
    throw RecibopagosUnknownException(
      'status_paid desconocido: "$status"',
      statusPaid: status,
      resultCode: resultCode,
      raw: extras,
    );
  }

  Future<Map<Object?, Object?>> _simulate(Map<String, Object?> extras) async {
    await Future<void>.delayed(mockDelay);
    final int amount = extras['monto'] as int;
    Map<Object?, Object?> withStatus(String s) => <Object?, Object?>{
          'resultCode': _resultOk,
          'extras': <String, Object?>{
            'order_id': extras['orden_id'],
            'status_paid': s,
          },
        };
    switch (mockOutcome) {
      case RecibopagosMockOutcome.approved:
        return <Object?, Object?>{
          'resultCode': _resultOk,
          'extras': <String, Object?>{
            'order_id': extras['orden_id'],
            'status_paid': 'paid',
            'transaction_id': 'MOCK-${DateTime.now().millisecondsSinceEpoch}',
            'authorization_code': '123456',
            'card_last_digits': '4242',
            'payment_method': extras['tipo'] == 'credito' ? 'CREDITO' : 'DEBITO',
            'installments': 0,
            'gratuity': 0,
            'paid_amount': amount,
            'terminal_serial': 'MOCK0001',
          },
        };
      case RecibopagosMockOutcome.cancelled:
        return withStatus('cancel');
      case RecibopagosMockOutcome.timeout:
        return withStatus('timeout');
      case RecibopagosMockOutcome.rejected:
        return withStatus('rechazado');
      case RecibopagosMockOutcome.failed:
        return withStatus('failed');
      case RecibopagosMockOutcome.notInIntentMode:
        return <Object?, Object?>{'resultCode': -5, 'extras': null};
    }
  }

  void _log(String msg) {
    if (mode == RecibopagosMode.production) return;
    developer.log('[RP:${mode.name.toUpperCase()}] $msg',
        name: 'recibopagos_app2app');
  }
}
