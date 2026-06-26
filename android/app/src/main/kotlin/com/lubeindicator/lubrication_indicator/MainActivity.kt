package com.lubeindicator.lubrication_indicator

import android.media.MediaScannerConnection
import android.content.Intent
import android.net.Uri
import android.os.StrictMode
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val MEDIA_SCAN_CHANNEL = "com.lubeindicator.vapli/media_scanner"
    private val OPEN_FOLDER_CHANNEL = "com.lubeindicator.vapli/open_folder"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Disable exposed File URI StrictMode checks
        val builder = StrictMode.VmPolicy.Builder()
        StrictMode.setVmPolicy(builder.build())

        // Media scanner channel (existing)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_SCAN_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "scanFile") {
                val path = call.argument<String>("path")
                if (path != null) {
                    MediaScannerConnection.scanFile(
                        context,
                        arrayOf(path),
                        null
                    ) { _, _ ->
                        // Scan completed
                    }
                    result.success(true)
                } else {
                    result.error("INVALID_PATH", "Path is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
        // Open folder channel (new)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OPEN_FOLDER_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "openFolder") {
                val folderPath = call.argument<String>("path")
                if (folderPath != null) {
                    try {
                        val folder = File(folderPath)
                        val uri = Uri.fromFile(folder)
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "vnd.android.document/directory")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(Intent.createChooser(intent, "Open folder"))
                        result.success(true)
                    } catch (e: Exception) {
                        // Fallback to * / * if vnd.android.document/directory fails
                        try {
                            val folder = File(folderPath)
                            val uri = Uri.fromFile(folder)
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "*/*")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(intent, "Open folder"))
                            result.success(true)
                        } catch (e2: Exception) {
                            result.error("OPEN_ERROR", e2.localizedMessage, null)
                        }
                    }
                } else {
                    result.error("INVALID_PATH", "Folder path is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
