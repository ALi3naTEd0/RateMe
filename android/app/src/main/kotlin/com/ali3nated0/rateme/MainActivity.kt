package com.ali3nated0.rateme

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.rateme/media_scanner"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFile" -> {
                    val filePath = call.argument<String>("path")
                    if (filePath != null) {
                        scanFile(filePath)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Path cannot be null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun scanFile(path: String) {
        MediaScannerConnection.scanFile(
            applicationContext,
            arrayOf(path),
            null
        ) { _, _ -> 
            // Optional callback when scan completes
        }
    }
}
