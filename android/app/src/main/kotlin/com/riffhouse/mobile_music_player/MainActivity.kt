package com.riffhouse.mobile_music_player

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {

    private val UPDATE_CHANNEL = "com.riffhouse/app_update"
    private val FILES_CHANNEL = "com.riffhouse/files"
    private val SAVE_FILE_REQUEST = 4201

    // A "save file" request waiting for the user to pick a location.
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSaveBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Saving a file (the listening-data backup) where the user chooses.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILES_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                if (bytes == null || pendingSaveResult != null) {
                    result.error("SAVE_FAILED", "Nothing to save, or a save is already open", null)
                    return@setMethodCallHandler
                }
                try {
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = call.argument<String>("mimeType") ?: "application/octet-stream"
                        putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "backup")
                    }
                    pendingSaveResult = result
                    pendingSaveBytes = bytes
                    startActivityForResult(intent, SAVE_FILE_REQUEST)
                } catch (e: Exception) {
                    pendingSaveResult = null
                    pendingSaveBytes = null
                    result.error("SAVE_FAILED", e.message, null)
                }
            }

        // In-app updates: hands a downloaded APK to the system package installer.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallPackages" -> {
                        // Before Android 8 there is no per-app permission to check.
                        val allowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls()
                        result.success(allowed)
                    }
                    "openInstallPermissionSettings" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                        Uri.parse("package:$packageName")
                                    )
                                )
                            }
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("SETTINGS_FAILED", e.message, null)
                        }
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("INVALID_PATH", "Path must not be null", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = File(path).canonicalFile
                            // Only APKs this app downloaded into its own cache may be installed.
                            val cacheRoot = cacheDir.canonicalFile.absolutePath + File.separator
                            if (!file.absolutePath.startsWith(cacheRoot) || !file.exists()) {
                                result.error("INVALID_PATH", "APK is not in the app cache", null)
                                return@setMethodCallHandler
                            }
                            val uri = FileProvider.getUriForFile(
                                this, "$packageName.fileprovider", file
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != SAVE_FILE_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingSaveResult
        val bytes = pendingSaveBytes
        pendingSaveResult = null
        pendingSaveBytes = null
        if (result == null) return

        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null || bytes == null) {
            result.success(false) // Cancelled
            return
        }
        try {
            val stream = contentResolver.openOutputStream(uri)
                ?: throw java.io.IOException("Could not open the chosen file")
            stream.use { it.write(bytes) }
            result.success(true)
        } catch (e: Exception) {
            result.error("SAVE_FAILED", e.message, null)
        }
    }
}
