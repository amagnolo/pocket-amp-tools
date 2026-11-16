package io.github.vitoramaral10.pocketamptools

import android.app.Activity
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // The text to write and who waits for it, while Android's save dialog
    // is open.
    // shortcut: lost if Android kills the app behind the dialog (the save
    // then reports nothing chosen); keep it in saved state if that shows up.
    private var pendingSave: Pair<String, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // A paired pedal reconnects to the phone on its own and then stops
        // advertising, so scans miss it: list what Android has paired instead.
        MethodChannel(messenger, "pocket_amp/bluetooth")
            .setMethodCallHandler { call, result ->
                if (call.method != "bonded") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
                    result.success(adapter.bondedDevices.map {
                        mapOf("id" to it.address, "name" to (it.name ?: ""))
                    })
                } catch (e: SecurityException) {
                    result.success(emptyList<Map<String, String>>())
                }
            }
        // file_selector has no save dialog on Android: ask the system's own,
        // so the file can go to Downloads, a cloud drive or another app.
        MethodChannel(messenger, "pocket_amp/files")
            .setMethodCallHandler { call, result ->
                if (call.method != "save") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingSave != null) {
                    result.error("busy", "A save dialog is already open.", null)
                    return@setMethodCallHandler
                }
                pendingSave = call.argument<String>("text")!! to result
                startActivityForResult(
                    Intent(Intent.ACTION_CREATE_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE)
                        .setType("application/json")
                        .putExtra(Intent.EXTRA_TITLE, call.argument<String>("name")),
                    SAVE_REQUEST,
                )
            }
    }

    @Deprecated("FlutterActivity is not a ComponentActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_REQUEST) {
            return
        }
        val (text, result) = pendingSave ?: return
        pendingSave = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            // "wt" truncates a file picked to be replaced.
            contentResolver.openOutputStream(uri, "wt")!!.use { it.write(text.toByteArray()) }
            result.success(uri.toString())
        } catch (e: Exception) {
            result.error("write", e.message, null)
        }
    }

    private companion object {
        const val SAVE_REQUEST = 4201
    }
}
