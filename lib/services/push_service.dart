import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../main.dart';
import 'auth_service.dart';

/// Push-уведомления: Firebase Cloud Messaging + локальный показ в foreground.
/// Токены устройств хранятся в таблице `push_tokens`.
class PushService {
  static final _messaging = FirebaseMessaging.instance;
  static final _local = FlutterLocalNotificationsPlugin();

  static const channelId = 'luxe_messages';
  static bool _localReady = false;

  /// Инициализация. Вызывать после Supabase.initialize и после входа.
  static Future<void> init() async {
    try {
      await Firebase.initializeApp();

      // Плагин уведомлений обязан быть инициализирован ДО создания канала,
      // иначе на Android createNotificationChannel молча не срабатывает.
      await _initLocalNotifications();
      await _ensureAndroidChannel();

      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Android 13+ требует отдельного разрешения в рантайме
      await _requestAndroidPermission();

      final token = await _messaging.getToken();
      if (token != null) await saveToken(token);

      _messaging.onTokenRefresh.listen((t) => saveToken(t));

      // Сообщение пришло, пока приложение открыто
      FirebaseMessaging.onMessage.listen(_onForeground);

      // Нажали на уведомление
      FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);

      // Уведомление запустило приложение из закрытого состояния
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _onOpened(initial);

      debugPrint('Push: разрешение=${settings.authorizationStatus}, токен=${token != null}');
    } catch (e) {
      // Firebase не настроен (нет google-services.json или платформа не поддерживается)
      debugPrint('Push: инициализация пропущена — $e');
    }
  }

  /// Сохранить токен текущего устройства за пользователем.
  static Future<void> saveToken(String token) async {
    await supabase.from('push_tokens').upsert({
      'user_id': AuthService.myId,
      'token': token,
      'platform': _platform(),
    });
  }

  static Future<void> _initLocalNotifications() async {
    if (_localReady) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _local.initialize(settings,
        onDidReceiveNotificationResponse: (response) {
      debugPrint('Push: нажата кнопка уведомления');
    });
    _localReady = true;
  }

  /// Android 13+ (API 33): разрешение на показ уведомлений.
  static Future<void> _requestAndroidPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Push: запрос прав на уведомления пропущен — $e');
    }
  }

  /// Канал уведомлений. Без него Android 8+ не покажет входящие push.
  static Future<void> _ensureAndroidChannel() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          'luxe_messages',
          'Сообщения',
          description: 'Уведомления о новых сообщениях',
          importance: Importance.high,
        ),
      );
    } catch (e) {
      debugPrint('Push: канал уведомлений не создан — $e');
    }
  }

  static String _platform() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      default:
        return 'other';
    }
  }

  static Future<void> _onForeground(RemoteMessage msg) async {
    final title = msg.notification?.title ?? 'Новое сообщение';
    final body = msg.notification?.body ?? '';
    debugPrint('Push: уведомление пришло в приложении — $title / $body');

    // Плагин мог не инициализироваться (например, вход до Firebase)
    await _initLocalNotifications();

    await _local.show(
      msg.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          PushService.channelId,
          'Сообщения',
          channelDescription: 'Уведомления о новых сообщениях и звонках',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(msg.data),
    );
  }

  static void _onOpened(RemoteMessage msg) {
    debugPrint('Push: уведомление открыто, чат ${msg.data['chat_id']}');
  }
}