package com.luxe.luxe

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Установка обновления прямо из приложения.
 *
 * Android не даёт обновиться молча — системный установщик всегда
 * спрашивает подтверждение. Но хотя бы один тап вместо пяти:
 * скачали, поставили, приложились.
 */
class MainActivity : FlutterActivity() {

    private val channel = "luxe/update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Скачанный APK открыть в установщике.
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("no_path", "Не указан путь к файлу", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = File(path)
                            if (!file.exists()) {
                                result.error("no_file", "Файл не найден: $path", null)
                                return@setMethodCallHandler
                            }
                            val uri: Uri = FileProvider.getUriForFile(
                                this, "$packageName.fileprovider", file
                            )
                            val intent = Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("install_failed", e.message, null)
                        }
                    }

                    // Если установщик молча блокируется — ведём в настройки
                    // приложения, где разрешают ставить из неизвестных источников.
                    "openAppSettings" -> {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.fromParts("package", packageName, null)
                                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("settings_failed", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
