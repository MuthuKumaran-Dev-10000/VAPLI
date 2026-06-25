package com.lubeindicator.myapp

import android.media.MediaScannerConnection
import android.content.Intent
import androidx.core.content.FileProvider
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.lubeindicator.vapli/media_scanner"
    private val OPEN_FILE_CHANNEL = "com.lubeindicator.vapli/open_file"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Media scanner channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "scanFile") {
                val path = call.argument<String>("path")
                if (path != null) {
                    MediaScannerConnection.scanFile(context, arrayOf(path), null) { _, _ -> }
                    result.success(true)
                } else {
                    result.error("INVALID_PATH", "Path is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
        // Open file/folder channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OPEN_FILE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        try {
                            val file = java.io.File(path)
                            val uri = FileProvider.getUriForFile(this, "${applicationContext.packageName}.fileprovider", file)
                            val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension) ?: "*/*"
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, mime)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(intent, "Open with"))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_ERROR", e.localizedMessage, null)
                        }
                    } else {
                        result.error("INVALID_PATH", "Path is null", null)
                    }
                }
                "openFolder" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        try {
                            val folder = java.io.File(path)
                            val uri = FileProvider.getUriForFile(this, "${applicationContext.packageName}.fileprovider", folder)
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "resource/folder")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(intent, "Open folder with"))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_ERROR", e.localizedMessage, null)
                        }
                    } else {
                        result.error("INVALID_PATH", "Path is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
