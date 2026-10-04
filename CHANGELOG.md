# Changelog

## Sin publicar

- Exige `RESULT_OK`, `status_paid == "paid"`, `order_id` coincidente y monto
  consistente antes de aprobar un cobro.
- Rechaza órdenes vacías y montos que no caben en el `Int` requerido por Android.

## 0.1.0 — 2026-10-03

- Versión inicial según https://recibopagos.com/desarrolladores/app-to-app
- `RecibopagosClient.isInstalled()`, `charge()`, `lastCharge()` (ContentProvider de respaldo).
- Éxito solo con `status_paid == "paid"`; excepciones tipadas para cancel, timeout, rechazado, failed y no instalada.
- Verificación de `order_id` devuelto contra el enviado.
- Modos `production`, `debug`, `mock`.
