# Changelog

## 0.1.2 — 2026-10-08

- Ya no exige que `order_id` devuelto coincida con el enviado: en un Sunmi real
  ReciboPagos responde con un uuid v7 propio, y el chequeo rechazaba pagos
  aprobados como `RecibopagosUnknownException`.
- `RecibopagosChargeResponse.paymentType` normaliza `payment_method`
  (`CREDIT`/`CREDITO`/`DEBIT`/`DEBITO`). El equipo real envía `CREDIT`.
- El mock devuelve `CREDIT`/`DEBIT` como el equipo real.

## 0.1.1 — 2026-10-08

- Exige `RESULT_OK`, `status_paid == "paid"`, `order_id` coincidente y monto
  consistente antes de aprobar un cobro.
- Rechaza órdenes vacías y montos que no caben en el `Int` requerido por Android.

## 0.1.0 — 2026-10-03

- Versión inicial según https://recibopagos.com/desarrolladores/app-to-app
- `RecibopagosClient.isInstalled()`, `charge()`, `lastCharge()` (ContentProvider de respaldo).
- Éxito solo con `status_paid == "paid"`; excepciones tipadas para cancel, timeout, rechazado, failed y no instalada.
- Verificación de `order_id` devuelto contra el enviado.
- Modos `production`, `debug`, `mock`.
