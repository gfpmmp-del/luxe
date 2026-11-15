import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    LuxeCallAudio.shared.register(messenger: engineBridge.applicationRegistrar.messenger())
  }
}

/// Аудиосессия звонков.
///
/// flutter_webrtc сам выставляет категорию `.playAndRecord` и режим
/// `.voiceChat`, но не активирует сессию — активацию он оставляет своему
/// аудио-модулю. На iOS этот момент иногда теряется: звонок соединяется,
/// а звука нет ни в одну сторону. Поэтому сессию поднимаем явно.
///
/// Категорию на ходу не меняем: переключение `.playback` ⇄ `.playAndRecord`
/// во время звонка убивает удалённый звук (flutter-webrtc #2036).
/// Маршрут «динамик/наушник» меняется только через overrideOutputAudioPort.
final class LuxeCallAudio: NSObject {
  static let shared = LuxeCallAudio()

  /// Номер поколения звонка. Поздняя деактивация старого звонка не должна
  /// выключить сессию нового, если пользователь перезвонил сразу же.
  private var generation = 0

  private var channel: FlutterMethodChannel?

  /// Идёт ли звонок прямо сейчас. Нужен, чтобы после системного
  /// прерывания (входящий телефонный звонок, будильник, Siri) вернуть
  /// сессию только во время разговора.
  private var inCall = false

  private override init() {
    super.init()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance()
    )
  }

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "luxe/call_audio",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handle(call, result: result)
    }
    self.channel = channel
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "start":
        let args = call.arguments as? [String: Any]
        try start(speaker: args?["speaker"] as? Bool ?? false)
        result(nil)
      case "activate":
        try AVAudioSession.sharedInstance().setActive(true)
        result(nil)
      case "speaker":
        let args = call.arguments as? [String: Any]
        try setSpeaker(args?["on"] as? Bool ?? false)
        result(nil)
      case "end":
        end()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(
        code: "call_audio",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  /// Категория и режим — под голосовой звонок; затем активация.
  ///
  /// `.defaultToSpeaker` не ставим намеренно: с ним система всегда
  /// выбирает динамик, и вернуться на разговорный динамик телефона
  /// (наушник) уже нельзя — `.none` всё равно оставляет динамик.
  private func start(speaker: Bool) throws {
    generation += 1
    inCall = true
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord,
      mode: .voiceChat,
      options: [.allowBluetooth]
    )
    try session.setActive(true)
    if speaker {
      try session.overrideOutputAudioPort(.speaker)
    } else {
      try session.overrideOutputAudioPort(.none)
    }
  }

  private func setSpeaker(_ on: Bool) throws {
    try AVAudioSession.sharedInstance()
      .overrideOutputAudioPort(on ? .speaker : .none)
  }

  /// После системного прерывания iOS гасит сессию. Если разговор ещё
  /// идёт и система разрешает продолжить — поднимаем её обратно.
  @objc private func handleInterruption(_ notification: Notification) {
    guard inCall,
          let info = notification.userInfo,
          let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          AVAudioSession.InterruptionType(rawValue: raw) == .ended
    else { return }

    let options = AVAudioSession.InterruptionOptions(
      rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
    )
    if options.contains(.shouldResume) {
      try? AVAudioSession.sharedInstance().setActive(true)
    }
  }

  /// Отпускаем сессию не сразу: WebRTC гасит свой аудио-модуль
  /// асинхронно, и мгновенный `setActive(false)` может вернуть ошибку
  /// «busy», оставив микрофон занятым.
  private func end() {
    generation += 1
    inCall = false
    let token = generation
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      guard self.generation == token else { return }
      try? AVAudioSession.sharedInstance().setActive(
        false,
        options: .notifyOthersOnDeactivation
      )
    }
  }
}
