# recibopagos_app2app

Plugin Flutter (Android) para cobrar con la app **ReciboPagos POS** instalada
en el mismo equipo, vía Intent (App To App). Sin red de por medio.

**Documentación oficial de la integración:**
https://recibopagos.com/desarrolladores/app-to-app

## Requisitos

- Android, con la app `com.recibopagos.pos` instalada.
- El equipo en **modo intent**, activado desde el panel de ReciboPagos. Si no
  lo está, la app rechaza el cobro y devuelve cancelado (`resultCode -5`).
- No hay que tocar el manifest de la app: el plugin declara el `<queries>`
  necesario para Android 11+.

## Instalación

```yaml
dependencies:
  recibopagos_app2app:
    git:
      url: https://github.com/morello-cl/recibopagos_app2app.git
      ref: v0.1.0
```

## Uso

```dart
import 'package:recibopagos_app2app/recibopagos_app2app.dart';

final rp = RecibopagosClient(channel: 'DTEx'); // mode: production por defecto

if (!await rp.isInstalled()) {
  // ofrecer otro medio de pago
}

try {
  final r = await rp.charge(const RecibopagosChargeRequest(
    amount: 12500,          // pesos enteros, > 0
    orderId: 'VENTA-12345', // siempre: llave de conciliación
    // paymentType: RecibopagosPaymentType.debit,
    // exempt: true,        // venta exenta de IVA
    // skipKeypad: true,    // por defecto: directo al cobro
  ));
  // Aprobado. r.paidAmount incluye propina (r.gratuity).
  // Solo ahora se emite la boleta.
} on RecibopagosCancelledException {
  // Cancelado o equipo sin modo intent (ReciboPagos no distingue ambos).
} on RecibopagosTimeoutException {
  // Caducó (el cobro expira a los 5 minutos).
} on RecibopagosRejectedException {
  // Rechazado por el emisor.
} on RecibopagosFailedException {
  // Falla en la app ReciboPagos.
} on RecibopagosNotInstalledException {
  // App no instalada.
} on RecibopagosUnknownException {
  // Estado incierto: NO asumir que no se cobró. Conciliar (ver abajo).
}
```

`charge()` retorna **solo** si `status_paid == "paid"`. Un `RESULT_OK` de
Android no significa que se pagó.

### Conciliación

Si nuestra app muere mientras se cobra, el resultado se pierde. Al volver,
con una venta pendiente:

```dart
final last = await rp.lastCharge();
if (last != null && last.orderId == pendiente.orderId && last.isPaid) {
  // el cobro se hizo: cerrar la venta sin volver a cobrar
}
```

`lastCharge()` lee el ContentProvider de solo lectura
`content://com.recibopagos.pos.provider/prefs`.

### Modos

| Modo         | Qué hace |
|--------------|----------|
| `production` | Cobra contra la app real. |
| `debug`      | Igual, y loggea extras enviados y recibidos (`dart:developer`). |
| `mock`       | No toca Android. Simula `mockOutcome` (`approved`, `cancelled`, `timeout`, `rejected`, `failed`, `notInIntentMode`) tras `mockDelay`. |

## Mapeo con la doc

| Request            | Extra            | Tipo    |
|--------------------|------------------|---------|
| `amount`           | `monto`          | int     |
| `orderId`          | `orden_id`       | String  |
| `transactionId`    | `id_transaction` | String  |
| `paymentType`      | `tipo`           | `credito` / `debito` |
| `exempt`           | `exempt`         | int 0/1 |
| `skipKeypad`       | `exit_wallet`    | boolean |
| `channel` (cliente)| `channel`        | String  |

Respuesta: `order_id`, `status_paid`, `transaction_id`, `authorization_code`,
`card_last_digits`, `payment_method`, `installments`, `gratuity`,
`paid_amount`, `terminal_serial`. Los numéricos se leen tolerantes (int o
String) y los strings ausentes llegan como `''`. Los extras crudos quedan en
`raw` para soporte.

## Pruebas

```
flutter test
```

Plan de trabajo y preguntas abiertas: [PLANNING.md](PLANNING.md).
