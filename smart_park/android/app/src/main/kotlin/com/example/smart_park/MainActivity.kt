package com.example.smart_park

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Full brightness while a QR ticket is on screen, so gate scanners
        // can read it; "false" hands brightness back to the system.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "smartpark/screen")
            .setMethodCallHandler { call, result ->
                if (call.method != "setMaxBrightness") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val on = call.arguments as? Boolean ?: false
                val attrs = window.attributes
                attrs.screenBrightness = if (on) {
                    WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL
                } else {
                    WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                }
                window.attributes = attrs
                result.success(null)
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "smartpark/downloads")
            .setMethodCallHandler { call, result ->
                if (call.method != "save") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val name = call.argument<String>("name")
                val mime = call.argument<String>("mime")
                val bytes = call.argument<ByteArray>("bytes")
                if (name == null || mime == null || bytes == null) {
                    result.error("bad_args", "name, mime and bytes are required", null)
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
                    checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
                    PackageManager.PERMISSION_GRANTED
                ) {
                    result.error("no_permission", "Storage permission is needed", null)
                    return@setMethodCallHandler
                }
                try {
                    result.success(saveToDownloads(name, mime, bytes))
                } catch (e: Exception) {
                    result.error("save_failed", e.message, null)
                }
            }
    }

    /** Writes [bytes] to Downloads/SmartPark and returns the file's display name. */
    private fun saveToDownloads(name: String, mime: String, bytes: ByteArray): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/SmartPark")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Could not create the file")
            try {
                resolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("Could not open the file")
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                throw e
            }
            return name
        }
        @Suppress("DEPRECATION")
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "SmartPark",
        )
        dir.mkdirs()
        var file = File(dir, name)
        var n = 1
        while (file.exists()) {
            file = File(dir, "${name.substringBeforeLast('.')} ($n).${name.substringAfterLast('.')}")
            n++
        }
        file.writeBytes(bytes)
        return file.name
    }
}
