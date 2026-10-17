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

    /**
     * Разрешено ли телефону ставить файлы из этого приложения.
     *
     * Старый PackageManager.canInstallPackages() в новых SDK вырезан,
     * поэтому на Android 11+ спрашиваем canRequestPackageInstalls().
     * На 8–10 проверять нечем — там установщик сам спросит разрешение.
     */
    private fun canInstallPackages(): Boolean = when {
        android.os.Build.VERSION.SDK_INT >= 30 ->
            packageManager.canRequestPackageInstalls()
        else -> true
    }

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
                            // Android 8+ не даст поставить файл, пока
                            // для этого приложения не разрешено ставить
                            // из неизвестных источников. Ловим это
                            // здесь: иначе установщик откроется и
                            // молча закроется.
                            if (android.os.Build.VERSION.SDK_INT >= 26 && !canInstallPackages()) {
                                result.error(
                                    "not_allowed",
                                    "Приложению не разрешено устанавливать файлы",
                                    null
                                )
                                return@setMethodCallHandler
                            }
                            val uri: Uri = FileProvider.getUriForFile(
                                this, "$packageName.fileprovider", file
                            )
                            val intent = Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            // Если установщика на телефоне нет — сообщаем
                            // честно, а не роняем exception.
                            if (intent.resolveActivity(packageManager) == null) {
                                result.error(
                                    "no_installer",
                                    "На телефоне нет приложения для установки",
                                    null
                                )
                                return@setMethodCallHandler
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("install_failed", e.message, null)
                        }
                    }

                    // Экран «Установка из неизвестных источников» именно
                    // для этого приложения: в общих настройках телефона
                    // его ещё надо найти глазами.
                    "openAppSettings" -> {
                        try {
                            val intent =
                                if (android.os.Build.VERSION.SDK_INT >= 26) {
                                    Intent(
                                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                        Uri.parse("package:$packageName")
                                    )
                                } else {
                                    Intent(
                                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                        Uri.fromParts("package", packageName, null)
                                    )
                                }
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            if (intent.resolveActivity(packageManager) != null) {
                                startActivity(intent)
                            } else {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                        Uri.fromParts("package", packageName, null)
                                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                            }
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
