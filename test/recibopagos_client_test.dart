import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recibopagos_app2app/recibopagos_app2app.dart';

Map<Object?, Object?> res(int code, Map<String, Object?>? extras) =>
    <Object?, Object?>{'resultCode': code, 'extras': extras};

RecibopagosChargeResponse parse(Map<Object?, Object?>? r) =>
    RecibopagosClient.parseResult(r, sentAmount: 12500);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('request → extras con nombres y tipos de la doc', () {
    final Map<String, Object?> e = const RecibopagosChargeRequest(
      amount: 12500,
      orderId: 'V-1',
      transactionId: 'T-9',
      paymentType: RecibopagosPaymentType.credit,
      exempt: true,
    ).toExtras(channel: 'DTEx');
    expect(e, <String, Object?>{
      'monto': 12500,
      'orden_id': 'V-1',
      'exit_wallet': true,
      'exempt': 1,
      'id_transaction': 'T-9',
      'tipo': 'credito',
      'channel': 'DTEx',
    });
    expect(
      () => const RecibopagosChargeRequest(amount: 0, orderId: 'x').toExtras(),
      throwsArgumentError,
    );
    expect(
      () => const RecibopagosChargeRequest(amount: 1, orderId: ' ').toExtras(),
      throwsArgumentError,
    );
    expect(
      () => const RecibopagosChargeRequest(
        amount: 0x80000000,
        orderId: 'V-1',
      ).toExtras(),
      throwsArgumentError,
    );
  });

  test('paid → respuesta, con numéricos como int o String', () {
    final RecibopagosChargeResponse r = parse(res(-1, <String, Object?>{
      'order_id': 'V-1',
      'status_paid': 'paid',
      'authorization_code': 'A1',
      'card_last_digits': '4242',
      'payment_method': 'DEBITO',
      'installments': '3',
      'gratuity': 500,
      'paid_amount': 13000,
      'terminal_serial': null,
    }));
    expect(r.paidAmount, 13000);
    expect(r.gratuity, 500);
    expect(r.installments, 3);
    expect(r.terminalSerial, '');
    expect(r.transactionId, '');
  });

  test('RESULT_OK no es pago: cada status lanza su excepción', () {
    Map<Object?, Object?> s(String v) =>
        res(-1, <String, Object?>{'status_paid': v});
    expect(() => parse(s('cancel')),
        throwsA(isA<RecibopagosCancelledException>()));
    expect(() => parse(s('timeout')),
        throwsA(isA<RecibopagosTimeoutException>()));
    expect(() => parse(s('rechazado')),
        throwsA(isA<RecibopagosRejectedException>()));
    expect(() => parse(s('failed')),
        throwsA(isA<RecibopagosFailedException>()));
    expect(() => parse(s('raro')),
        throwsA(isA<RecibopagosUnknownException>()));
    expect(() => parse(res(-1, null)),
        throwsA(isA<RecibopagosUnknownException>()));
  });

  test('-5 sin extras → cancelado', () {
    expect(() => parse(res(-5, null)),
        throwsA(isA<RecibopagosCancelledException>()
            .having((e) => e.resultCode, 'resultCode', -5)));
    expect(() => parse(res(0, <String, Object?>{'status_paid': ''})),
        throwsA(isA<RecibopagosCancelledException>()));
  });

  test('paid exige RESULT_OK', () {
    expect(
      () => parse(res(-5, <String, Object?>{
        'status_paid': 'paid',
        'order_id': 'V-1',
        'paid_amount': 12500,
      })),
      throwsA(isA<RecibopagosUnknownException>()),
    );
  });

  test('respuesta real del Sunmi: order_id propio de RP y CREDIT', () {
    // Capturada por ReciboPagos el 2026-10-08 con el APK demo de ParkingCash.
    final RecibopagosChargeResponse r = RecibopagosClient.parseResult(
      res(-1, <String, Object?>{
        'status': 'paid',
        'estado': -1,
        'payment_method': 'CREDIT',
        'terminal_serial': 'P3G8261KJ0595',
        'status_paid': 'paid',
        'gratuity': 0,
        'transaction_id': '13059918803',
        'card_last_digits': '8597',
        'unique_identifier': '13059918803',
        'order_id': '01a11cea-bc2f-72c4-b1e3-8e2793842317',
        'authorization_code': '816434',
        'paid_amount': 560,
        'installments': 0,
      }),
      sentAmount: 560,
    );
    expect(r.orderId, '01a11cea-bc2f-72c4-b1e3-8e2793842317');
    expect(r.paymentType, RecibopagosPaymentType.credit);
    expect(r.transactionId, '13059918803');
    expect(r.paidAmount, 560);
  });

  test('paymentType normaliza CREDIT/CREDITO/DEBIT/DEBITO', () {
    RecibopagosPaymentType? t(String m) => RecibopagosChargeResponse.fromExtras(
            <String, Object?>{'payment_method': m}).paymentType;
    expect(t('CREDIT'), RecibopagosPaymentType.credit);
    expect(t('CREDITO'), RecibopagosPaymentType.credit);
    expect(t('debit'), RecibopagosPaymentType.debit);
    expect(t('DEBITO'), RecibopagosPaymentType.debit);
    expect(t(''), isNull);
  });

  test('paid exige monto válido y consistente con monto + propina', () {
    expect(
      () => parse(res(-1, <String, Object?>{
        'status_paid': 'paid',
        'order_id': 'V-1',
      })),
      throwsA(isA<RecibopagosUnknownException>()),
    );
    expect(
      () => parse(res(-1, <String, Object?>{
        'status_paid': 'paid',
        'order_id': 'V-1',
        'paid_amount': 13001,
        'gratuity': 500,
      })),
      throwsA(isA<RecibopagosUnknownException>()),
    );
  });

  test('lastCharge aplana filas key/value y filas con columnas', () {
    final RecibopagosLastCharge kv = RecibopagosLastCharge.fromRows(
      <Map<String, Object?>>[
        <String, Object?>{'key': 'order_id', 'value': 'V-1'},
        <String, Object?>{'key': 'status_paid', 'value': 'paid'},
      ],
    );
    expect(kv.orderId, 'V-1');
    expect(kv.isPaid, isTrue);

    final RecibopagosLastCharge cols = RecibopagosLastCharge.fromRows(
      <Map<String, Object?>>[
        <String, Object?>{'order_id': 'V-2', 'status_paid': 'cancel', 'result_code': -5},
      ],
    );
    expect(cols.orderId, 'V-2');
    expect(cols.isPaid, isFalse);
    expect(cols.resultCode, '-5');
  });

  group('MethodChannel', () {
    const MethodChannel ch = MethodChannel(recibopagosChannelName);
    final TestDefaultBinaryMessenger m =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => m.setMockMethodCallHandler(ch, null));

    test('charge envía extras y parsea; MFN-04 → no instalada', () async {
      MethodCall? sent;
      m.setMockMethodCallHandler(ch, (MethodCall c) async {
        sent = c;
        return res(-1, <String, Object?>{
          'status_paid': 'paid',
          'order_id': 'V-1',
          'paid_amount': 1000,
        });
      });
      final RecibopagosClient rp = RecibopagosClient(channel: 'DTEx');
      final RecibopagosChargeResponse r = await rp.charge(
        const RecibopagosChargeRequest(amount: 1000, orderId: 'V-1'),
      );
      expect(r.paidAmount, 1000);
      expect(sent!.method, 'charge');
      expect((sent!.arguments as Map)['extras']['monto'], 1000);

      m.setMockMethodCallHandler(ch, (MethodCall c) async {
        throw PlatformException(code: 'MFN-04');
      });
      expect(
        rp.charge(const RecibopagosChargeRequest(amount: 1, orderId: 'V-1')),
        throwsA(isA<RecibopagosNotInstalledException>()),
      );
      expect(await rp.isInstalled(), isFalse);
    });
  });

  test('mock: aprobado eco del monto y -5 sin modo intent', () async {
    final RecibopagosChargeResponse r = await RecibopagosClient(
      mode: RecibopagosMode.mock,
      mockDelay: Duration.zero,
    ).charge(const RecibopagosChargeRequest(amount: 777, orderId: 'V-1'));
    expect(r.paidAmount, 777);
    expect(r.orderId, 'V-1');

    expect(
      RecibopagosClient(
        mode: RecibopagosMode.mock,
        mockDelay: Duration.zero,
        mockOutcome: RecibopagosMockOutcome.notInIntentMode,
      ).charge(const RecibopagosChargeRequest(amount: 1, orderId: 'V-1')),
      throwsA(isA<RecibopagosCancelledException>()),
    );
  });
}
