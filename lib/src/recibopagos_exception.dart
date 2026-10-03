/// Error de un cobro ReciboPagos. Toda falla de [RecibopagosClient.charge]
/// es una subclase de esta.
sealed class RecibopagosException implements Exception {
  final String message;

  /// `status_paid` devuelto por ReciboPagos, si vino.
  final String? statusPaid;

  /// `resultCode` de Android (-1 OK, -5 cancelado / sin modo intent).
  final int? resultCode;

  /// Extras crudos de la respuesta, para logs y soporte.
  final Map<String, Object?> raw;

  const RecibopagosException(
    this.message, {
    this.statusPaid,
    this.resultCode,
    this.raw = const <String, Object?>{},
  });

  @override
  String toString() =>
      '$runtimeType($message, status: $statusPaid, resultCode: $resultCode)';
}

/// Cancelado por el cajero/cliente, o `resultCode -5`. **También** cubre el
/// equipo sin modo intent activo: la doc no distingue ambos casos.
class RecibopagosCancelledException extends RecibopagosException {
  const RecibopagosCancelledException(super.message,
      {super.statusPaid, super.resultCode, super.raw});
}

/// El cobro caducó (`status_paid == "timeout"`).
class RecibopagosTimeoutException extends RecibopagosException {
  const RecibopagosTimeoutException(super.message,
      {super.statusPaid, super.resultCode, super.raw});
}

/// Rechazado por el emisor (`status_paid == "rechazado"`).
class RecibopagosRejectedException extends RecibopagosException {
  const RecibopagosRejectedException(super.message,
      {super.statusPaid, super.resultCode, super.raw});
}

/// Falla en la app ReciboPagos (`status_paid == "failed"`).
class RecibopagosFailedException extends RecibopagosException {
  const RecibopagosFailedException(super.message,
      {super.statusPaid, super.resultCode, super.raw});
}

/// La app ReciboPagos no está instalada en el equipo.
class RecibopagosNotInstalledException extends RecibopagosException {
  const RecibopagosNotInstalledException(super.message);
}

/// Cualquier otro caso: status desconocido, `order_id` que no coincide,
/// error nativo. **No asumir que no se cobró**: conciliar con
/// [RecibopagosClient.lastCharge] o el panel de ReciboPagos.
class RecibopagosUnknownException extends RecibopagosException {
  /// Código nativo `MFN-xx`, si el error vino del plugin Android.
  final String? code;

  const RecibopagosUnknownException(super.message,
      {this.code, super.statusPaid, super.resultCode, super.raw});
}
