package cl.mufin.recibopagos_app2app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/**
 * Puente Flutter ↔ app ReciboPagos POS.
 *
 * Doc oficial: https://recibopagos.com/desarrolladores/app-to-app
 *
 * Es deliberadamente "tonto": arma el Intent con los extras que llegan desde
 * Dart y devuelve el `Bundle` de respuesta completo, sin interpretarlo. El
 * veredicto del cobro (`status_paid`) se decide en Dart.
 *
 * Métodos:
 *  - `isInstalled(): Boolean` — la app RP está instalada y resuelve la action.
 *  - `charge(extras: Map): {resultCode: Int, extras: Map?}`
 *  - `lastCharge(): List<Map>?` — filas del ContentProvider de respaldo.
 *
 * Errores: `MFN-03` sin actividad, `MFN-04` no instalada, `MFN-05` otro cobro
 * en curso, `MFN-06` falla al lanzar, `MFN-07` falla al leer el provider y
 * `MFN-08` un entero no cabe en el tipo Int requerido por ReciboPagos.
 */
class RecibopagosApp2appPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null
    private var pendingResult: Result? = null

    override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
        context = b.applicationContext
        channel = MethodChannel(b.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(b: ActivityPluginBinding) = attach(b)
    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) = attach(b)
    override fun onDetachedFromActivity() = detach()
    override fun onDetachedFromActivityForConfigChanges() = detach()

    private fun attach(b: ActivityPluginBinding) {
        binding = b
        activity = b.activity
        b.addActivityResultListener(this)
    }

    private fun detach() {
        binding?.removeActivityResultListener(this)
        binding = null
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isInstalled" -> result.success(isInstalled())
            "charge" -> charge(call.argument<Map<String, Any?>>("extras") ?: emptyMap(), result)
            "lastCharge" -> lastCharge(result)
            else -> result.notImplemented()
        }
    }

    private fun paymentIntent() = Intent(ACTION).setPackage(PACKAGE)

    private fun isInstalled(): Boolean = try {
        context.packageManager.queryIntentActivities(paymentIntent(), 0).isNotEmpty()
    } catch (e: Throwable) {
        false
    }

    private fun charge(extras: Map<String, Any?>, result: Result) {
        val act = activity ?: return result.error("MFN-03", "Plugin not attached to an activity", null)
        if (pendingResult != null) {
            return result.error("MFN-05", "Another ReciboPagos charge is already in progress", null)
        }
        if (!isInstalled()) {
            return result.error("MFN-04", "ReciboPagos app '$PACKAGE' not installed", null)
        }

        // Los tipos importan: la app RP lee `monto`/`exempt` como Int y
        // `exit_wallet` como Boolean. Dart entrega Int/Long según magnitud.
        val intent = paymentIntent()
        for ((k, v) in extras) {
            when (v) {
                is Int -> intent.putExtra(k, v)
                is Long -> {
                    if (v !in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) {
                        return result.error("MFN-08", "Extra '$k' is outside Android Int range", null)
                    }
                    intent.putExtra(k, v.toInt())
                }
                is Boolean -> intent.putExtra(k, v)
                is String -> intent.putExtra(k, v)
                null -> {}
                else -> intent.putExtra(k, v.toString())
            }
        }

        pendingResult = result
        try {
            act.startActivityForResult(intent, REQUEST_CODE)
        } catch (e: Throwable) {
            pendingResult = null
            result.error("MFN-06", e.message ?: "Failed to start ReciboPagos", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val res = pendingResult ?: return true
        pendingResult = null
        res.success(mapOf("resultCode" to resultCode, "extras" to data?.extras?.toMap()))
        return true
    }

    private fun lastCharge(result: Result) {
        try {
            val cursor = context.contentResolver.query(Uri.parse(PROVIDER_URI), null, null, null, null)
            result.success(cursor?.use { it.toRows() })
        } catch (e: Throwable) {
            result.error("MFN-07", e.message ?: "Failed to read ReciboPagos provider", null)
        }
    }

    companion object {
        private const val CHANNEL_NAME = "cl.mufin.recibopagos_app2app"
        private const val ACTION = "com.recibopagos.pos.sibus-payment"
        private const val PACKAGE = "com.recibopagos.pos"
        private const val PROVIDER_URI = "content://com.recibopagos.pos.provider/prefs"
        private const val REQUEST_CODE = 0x5250 // "RP"
    }
}

/** Vuelca el Bundle a tipos que el StandardMessageCodec sabe serializar. */
@Suppress("DEPRECATION")
private fun Bundle.toMap(): Map<String, Any?> = keySet().associateWith { key ->
    when (val v = get(key)) {
        null, is String, is Int, is Long, is Boolean, is Double -> v
        is Float -> v.toDouble()
        is Short -> v.toInt()
        else -> v.toString()
    }
}

private fun Cursor.toRows(): List<Map<String, Any?>> {
    val rows = mutableListOf<Map<String, Any?>>()
    while (moveToNext()) {
        rows += columnNames.indices.associate { i ->
            columnNames[i] to when (getType(i)) {
                Cursor.FIELD_TYPE_INTEGER -> getLong(i)
                Cursor.FIELD_TYPE_FLOAT -> getDouble(i)
                Cursor.FIELD_TYPE_NULL -> null
                Cursor.FIELD_TYPE_BLOB -> null
                else -> getString(i)
            }
        }
    }
    return rows
}
