# recibopagos_app2app — Plan de trabajo

Plugin Flutter (solo Android) para cobrar con la app **ReciboPagos POS** en el
mismo equipo vía Intent. Consumidores: **DTEx** y **ParkingCash**.

Fuente: https://recibopagos.com/desarrolladores/app-to-app (extraído 2026-10-03).
Base de código: `../tuu_app_to_app` (mismo patrón Intent + `startActivityForResult`).

---

## 1. Contrato ReciboPagos (resumen de la doc)

**Lanzamiento**

| Item     | Valor                                   |
|----------|-----------------------------------------|
| Action   | `com.recibopagos.pos.sibus-payment`     |
| Package  | `com.recibopagos.pos`                   |
| Patrón   | `startActivityForResult` / `onActivityResult` |

**Extras de entrada**

| Extra            | Tipo    | Oblig. | Nota |
|------------------|---------|--------|------|
| `monto`          | int     | sí     | Pesos enteros. Sin él o en 0 la app abre normal. |
| `orden_id`       | String  | no     | Vuelve como `order_id`. |
| `tipo`           | String  | no     | `credito` / `debito` (sugerido). |
| `id_transaction` | String  | no     | Id de nuestro sistema. |
| `channel`        | String  | no     | Identifica a la app que llama. |
| `exempt`         | int     | no     | 1 = exenta de IVA; 0/ausente = afecta. |
| `exit_wallet`    | boolean | no     | `true` salta la calculadora. |

El cobro caduca a los **5 minutos**.

**Respuesta**

- `resultCode -1` (RESULT_OK): el flujo terminó con datos. **No implica pago.**
- `resultCode -5`: cancelado, rechazado o **equipo no está en modo intent**.
- Veredicto real: `status_paid` → solo `paid` es aprobado. Otros: `cancel`,
  `timeout`, `rechazado`, `failed`.
- Extras al aprobar: `order_id`, `status_paid`, `transaction_id`,
  `authorization_code`, `card_last_digits`, `payment_method` (CREDITO/DEBITO),
  `installments` (0 = contado), `gratuity`, `paid_amount` (int, incluye
  propina), `terminal_serial`.
- En aprobado ningún string es null; en cancelado no hay garantías.

**Canal de respaldo (ContentProvider, solo lectura)**

`content://com.recibopagos.pos.provider/prefs` (y `/prefs/<key>`). Expone
`order_id`, `status_paid`, `estado`, `result_code`, `transaction_id`.

**Requisito operativo:** el equipo debe estar en **modo intent** (se activa en
el panel de ReciboPagos).

---

## 2. Preguntas abiertas para ReciboPagos

Bloquean detalles, no el arranque (se implementa tolerante y se ajusta):

1. Tipo exacto de `installments`, `gratuity`, `transaction_id`,
   `terminal_serial` (¿int o String?). Solo `paid_amount` está documentado como int.
2. Esquema del cursor del ContentProvider: ¿una fila key/value o una fila con
   columnas? ¿Requiere permiso de lectura? ¿Refleja solo el último cobro?
3. ¿Existe build de desarrollo/sandbox (otro package) y comercio de pruebas?
4. ¿`-5` distingue de algún modo "no está en modo intent" de "cancelado"?
5. ¿Anulación/devolución vía Intent? (No documentado → se asume solo por API o
   no soportado; fuera del alcance v0.1).
6. ¿La app RP imprime voucher? ¿Emite boleta propia? (DTEx emite su DTE; hay
   que evitar doble documento.)
7. Modelos de terminal soportados (¿Sunmi, Nexgo?).

---

## 3. Diseño del plugin

Copia reducida de `tuu_app_to_app`. Sin JSON: los extras son primitivos.

```
recibopagos_app2app/
  pubspec.yaml                       # name: recibopagos_app2app, solo android
  lib/recibopagos_app2app.dart       # exports
  lib/src/recibopagos_client.dart    # cliente, modos, mock, parseo del resultado
  lib/src/models.dart                # request, response, lastCharge, paymentType
  lib/src/recibopagos_exception.dart # sealed
  android/src/main/AndroidManifest.xml        # <queries> package
  android/src/main/kotlin/cl/mufin/recibopagos_app2app/RecibopagosApp2appPlugin.kt
  test/recibopagos_client_test.dart
  README.md                          # guía de integración
  CHANGELOG.md
```

**API Dart**

```dart
final rp = RecibopagosClient(
  mode: RecibopagosMode.production,
  channel: 'DTEx',
);

if (!await rp.isInstalled()) return;

try {
  final r = await rp.charge(RecibopagosChargeRequest(
    amount: 12500,
    orderId: 'VENTA-12345',   // siempre se envía: es la llave de conciliación
    paymentType: RecibopagosPaymentType.debit, // opcional
    exempt: false,
    skipKeypad: true,         // exit_wallet
  ));
  // r.authorizationCode, r.cardLastDigits, r.paidAmount, r.gratuity, ...
} on RecibopagosCancelledException {   // -5 o status 'cancel'
} on RecibopagosTimeoutException {     // status 'timeout'
} on RecibopagosRejectedException {    // status 'rechazado'
} on RecibopagosFailedException {      // status 'failed'
} on RecibopagosNotInstalledException {
} on RecibopagosException {            // catch-all (status desconocido, nativo)
}

// Conciliación tras un cierre inesperado:
final last = await rp.lastCharge(); // lee el ContentProvider, null si no hay
```

`charge()` solo retorna si `status_paid == 'paid'` **y** `order_id` coincide con
el enviado; si no coincide lanza `RecibopagosUnknownException` (protege contra
leer un resultado ajeno).

**Kotlin (MethodChannel `cl.mufin.recibopagos_app2app`)**

- `isInstalled()` → `packageManager.getPackageInfo("com.recibopagos.pos")`.
- `charge(args)` → `Intent(ACTION).setPackage(PKG)` + extras con el tipo exacto
  (`monto` Int, `exempt` Int, `exit_wallet` Boolean). Retorna
  `{resultCode, extras}` donde `extras` es el `Bundle` completo volcado a
  `Map<String, Any?>` (preserva tipos; el parseo tolerante vive en Dart).
- `lastCharge()` → `contentResolver.query(...)` volcado a lista de mapas.
- Errores nativos `MFN-03..07` (sin activity, no instalada, en curso,
  falla al lanzar, falla al leer el provider).
- Manifest: `<queries>` con `<package android:name="com.recibopagos.pos"/>`
  (basta para ver tanto la activity como el provider).

**Parseo tolerante en Dart:** cada extra se lee como `Object?` y se convierte
(`int.tryParse` / `toString`) con valor por defecto, según el aviso de la doc.

**Modo mock:** comportamientos `approve`, `cancel`, `timeout`, `reject`,
`fail`, `notInIntentMode` (-5), con delay configurable. Para desarrollar sin POS.

---

## 4. Fases

### Fase 0 — Preparación (0,5 día)
- [x] `git init`, repo público `github.com/morello-cl/recibopagos_app2app`
      (mismo esquema que `nexgo_smartpos`, consumido por tag).
- [ ] Enviar preguntas de la sección 2 a ReciboPagos.
- [ ] Conseguir terminal con app RP y modo intent activo.

### Fase 1 — Plugin (1–1,5 días)
- [x] Scaffold a partir de `tuu_app_to_app`.
- [x] Kotlin: `isInstalled`, `charge`, `lastCharge`.
- [x] Dart: request/response, excepciones, cliente, mock.
- [x] Tests unitarios (`MethodChannel` mockeado).
- [x] `README.md`, `CHANGELOG.md`, tag `v0.1.0`.

### Fase 2 — Validación en terminal real (0,5–1 día)
Matriz mínima (cada caso registra el `Bundle` crudo para responder la sección 2):
- [ ] Aprobado débito y crédito (monto bajo), con y sin `exit_wallet`.
- [ ] Aprobado con propina y con cuotas.
- [ ] Cancelado por el cajero; botón back.
- [ ] Rechazado (tarjeta sin fondos / tarjeta de prueba).
- [ ] Timeout (dejar caducar).
- [ ] Equipo **sin** modo intent → `-5`.
- [ ] Matar nuestra app durante el cobro → al reabrir, `lastCharge()` concilia.
- [ ] Venta exenta (`exempt: 1`).
- [ ] Anotar sobre `transaction_id`: formato (¿uuid, numérico, alfanumérico?),
      si es estable y único por transacción (de eso depende que sirva para
      reversar) y si es distinto de `authorization_code`. En ParkingCash el
      largo sí importa: pasado 32, el INSERT en `pago_con_tarjeta` falla
      (PostgreSQL `22001`) y el pago no se registra.
- [ ] Ajustar el parseo con los tipos reales y publicar `v0.1.1` si cambia.

### Fase 3 — Integración DTEx (1 día)

**En espera** (decisión de Marco, 2026-10-04). La sesión dtex_app tiene el
resumen de integración y no ha tocado el repo.

- [ ] Dependencia por git + tag (o `path` mientras se desarrolla).
- [ ] `RecibopagosPayService` análogo a `KushkiPayService` (sin credenciales:
      solo `channel` y modo).
- [ ] `step2_page.dart`: agregar RP al auto-routing actual
      (Kushki / Haulmer) con detección por `isInstalled()`. No hay prioridad
      que definir: cada equipo pertenece a un solo proveedor (definido por
      Marco), así que se cobra con el que esté instalado.
- [ ] Usar `paid_amount` (incluye propina) y `exempt` coherente con el tipo de DTE.
- [ ] Conciliación al volver a primer plano con venta pendiente → `lastCharge()`.
- [ ] Página de pruebas en `lib/src/pages/dev/` (como `kushki_test_page`).

**Backend (Tomahawk), informado por su sesión el 2026-10-03:**
- `proveedores_pago`: fila `recibopagos` / `ReciboPagos` / **`liquida_mufin=0`**
  **aplicada en producción** el 2026-10-03 (Tomahawk v7.57.0, `860cb0e`).
  ReciboPagos deposita directo al comercio; 0 filas en `tarifas_comision`.
- `dte_payment.servicio` = **`recibopagos`** (definido por Marco: llaves en
  minúscula). Los valores históricos (`Haulmer`, `SUMUP`, `Kushki`, `RedPay`)
  no se tocan.
- `payment_method` `CREDITO`/`DEBITO` ya se normaliza bien en
  `tarifa-resolver.js`; no hay que tocar nada.
- **`transaction_id` va siempre por `POST /api/dtes/v6`**
  (`transaction_reference` char(36)), **nunca por `card_sequence`**, mida lo
  que mida. `secuencia` ya mezcla dos significados (Haulmer `sequenceNumber`,
  uuid de Kushki), y un largo medido un día no es un contrato: varchar(24)
  trunca sin error ni log (bug v7.55.0). Regla vigente: lo que no cabe se
  descarta entero y queda completo en el log, nunca se trunca.
- `paid_amount` incluye la propina: no usarlo como base de comisión.
- Alta de equipos: `controllers/customers.js` fija el prefijo `NEWPOS:8210:` en
  `serial_tid` y dos triggers recalculan `sn`. Un terminal RP dado de alta por
  ahí queda con la marca equivocada (ya pasa con 1.862 equipos).
- No usar `payment_processor_accounts` (modelo Compraquí): App To App no tiene
  alianza ni webhook.
- **Cuotas:** solo informativas (definido por Marco). Como MUFIN no liquida
  ReciboPagos, `installments` no entra al cálculo de comisión.

### Fase 4 — Integración ParkingCash (sesión remota, 1 día)
- [ ] Dependencia `git: {url: ..., ref: v0.1.x}` (patrón de `nexgo_smartpos`).
- [ ] Entregar a la sesión remota: `README.md` + este plan.
- [ ] Integrar en el flujo de pago de salida; misma conciliación por `order_id`.
- [ ] Revisar convivencia con `virtualpos_app2app` (selección de adquirente).

**Registro en `pago_con_tarjeta`, informado por parkingcash_web el 2026-10-03.**
Para que el backoffice lo reporte sin cambios:
- `tarjeta_tipo`: mapear `CREDITO` → `'Tarjeta de Crédito'` y `DEBITO` →
  `'Tarjeta de Débito'` (literales exactos). Si llega `CREDITO` tal cual, el
  pago se cuenta como efectivo/otro.
- `servicio` = `'recibopagos'`, en minúscula. Marco lo confirmó también para
  esta tabla, aunque sea el único valor en minúscula: un solo identificador
  por proveedor. **No convertir a mayúscula al escribir**; la presentación se
  resuelve aparte. Nunca
  `'MercadoPago'` ni `'QR-RECOVER'`: esos valores marcan el pago como QR/Web.
  Confirmado: el backoffice no requiere cambios (solo `routes/qr-web.js`
  compara `servicio`, contra `MercadoPago`/`QR-RECOVER`).
- **`abono_al_comercio_id` queda NULL**: ReciboPagos abona directo al
  comercio, igual que Haulmer (definido por Marco). El abono hoy es *opt-in*
  (solo `MercadoPago` y `QR-RECOVER`), así que no hay que cambiar nada.
- `placas_tot_monto` = estacionamiento **sin** propina
  (`paid_amount - gratuity`). No hay columna para la propina.
- `secuencia` ← `transaction_id`, `autorizacion` ← `authorization_code`,
  `tarjeta` ← `'****' + card_last_digits`.
- `origen_pago` distinto de `'web'` (cobro presencial).
- Largos (producción p5inapp): `servicio` varchar(**12**) ('recibopagos' = 11,
  ninguna variante más larga cabe), `autorizacion` varchar(32), `tarjeta_tipo`
  varchar(64), `tarjeta` varchar(24), `secuencia` varchar(32).
- Todas NOT NULL salvo `abono_al_comercio_id`: enviar `''`, nunca null (el
  plugin ya entrega `''` para strings ausentes).
- PostgreSQL no trunca: un valor más largo falla con `22001` y aborta el INSERT
  completo, así que el pago no se registra.
- Equipos: `equipos.equipo_marca` es texto libre (máx. 24); "ReciboPagos" se
  puede cargar hoy desde /equipments.
- Con el primer pago real de prueba, enviar el `placas_id` a parkingcash_web
  para verificar los reportes.

### Fase 5 — Piloto y cierre
- [ ] Piloto en 1 equipo por app; revisar conciliación contra el panel RP.
- [ ] Tag final y actualizar refs en ambas apps.

**Estimación total:** ~4–5 días de desarrollo, sin contar las respuestas de
ReciboPagos ni la disponibilidad del equipo.

---

## 5. Riesgos

| Riesgo | Mitigación |
|--------|------------|
| `RESULT_OK` interpretado como pagado | El plugin solo retorna éxito con `status_paid == 'paid'`. |
| `-5` ambiguo (cancelado vs. sin modo intent) | Mensaje al cajero que mencione ambas causas; validar en Fase 2. |
| App matada por el SO durante el cobro → cobro sin venta registrada | `orden_id` siempre enviado + `lastCharge()` al reanudar. |
| Tipos de extras no documentados | Volcado genérico del `Bundle` + parseo tolerante en Dart. |
| Doble documento tributario (RP + DTEx) | Pregunta 6 antes de producción. |
| Visibilidad de package/provider en Android 11+ | `<queries>` en el manifest del plugin (se mergea solo). |

Fuera de alcance v0.1: anulaciones/devoluciones, iOS, webhooks/API.
