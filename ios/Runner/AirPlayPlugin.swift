import AVKit
import Flutter
import UIKit

/// AirPlay casting. The receiver (Apple TV, Mac, AirPlay 2 TV) downloads the
/// video itself, so it gets the same progressive MP4 URL as DLNA casting
/// (bilibili's TV play URL, no Referer needed).
///
/// No player screen is shown: the system device list opens over the cast
/// page, an AVPlayer without a layer plays to the chosen receiver, and its
/// state is reported to the cast page, which is the remote control.
///
/// Dart side: `lib/utils/ios/airplay_helper.dart`.
final class AirPlayPlugin: NSObject, FlutterPlugin, AVRoutePickerViewDelegate {
  private let channel: FlutterMethodChannel
  private var player: AVPlayer?
  private var timeObserver: Any?
  private var observations: [NSKeyValueObservation] = []
  private var routeObserver: NSObjectProtocol?
  private var picker: AVRoutePickerView?
  private var title: String?
  /// Paused from the cast page; a route change must not resume it.
  private var pausedByUser = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "piliplus/airplay", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AirPlayPlugin(channel: channel), channel: channel)
  }

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "start":
      guard let s = args["url"] as? String, let url = URL(string: s) else {
        return result(FlutterError(code: "ARGS", message: "url is required", details: nil))
      }
      start(
        url: url, title: args["title"] as? String,
        startMs: (args["startMs"] as? NSNumber)?.int64Value ?? 0)
      result(nil)
    case "play":
      pausedByUser = false
      player?.play()
      result(nil)
    case "pause":
      pausedByUser = true
      player?.pause()
      result(nil)
    case "seek":
      let ms = (args["ms"] as? NSNumber)?.int64Value ?? 0
      player?.seek(to: CMTime(value: ms, timescale: 1000))
      result(nil)
    case "stop":
      stop()
      result(nil)
    case "state":
      result(state())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Session

  private func start(url: URL, title: String?, startMs: Int64) {
    stop()
    self.title = title
    pausedByUser = false
    let item = AVPlayerItem(url: url)
    if let title {
      let metadata = AVMutableMetadataItem()
      metadata.identifier = .commonIdentifierTitle
      metadata.value = title as NSString
      metadata.extendedLanguageTag = "und"
      item.externalMetadata = [metadata]  // shown on the receiver
    }
    let player = AVPlayer(playerItem: item)
    player.allowsExternalPlayback = true
    player.usesExternalPlaybackWhileExternalScreenIsActive = true
    if startMs > 0 {
      player.seek(to: CMTime(value: startMs, timescale: 1000))
    }
    self.player = player

    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(value: 1, timescale: 2), queue: .main
    ) { [weak self] _ in self?.sendState() }
    observations = [
      player.observe(\.timeControlStatus) { [weak self] _, _ in
        DispatchQueue.main.async { self?.sendState() }
      },
      player.observe(\.isExternalPlaybackActive) { [weak self] _, _ in
        DispatchQueue.main.async { self?.sendState() }
      },
    ]
    routeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.routeChanged() }

    if Self.airPlayDevice() != nil {
      // Already connected (e.g. from Control Center): play there right away.
      player.play()
    } else {
      showPicker()
    }
    sendState()
  }

  private func stop() {
    if let timeObserver { player?.removeTimeObserver(timeObserver) }
    timeObserver = nil
    observations.removeAll()
    if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
    routeObserver = nil
    let wasActive = player != nil
    player?.pause()
    player?.replaceCurrentItem(with: nil)  // ends playback on the receiver
    player = nil
    if wasActive { sendState() }
  }

  private func routeChanged() {
    guard let player else { return }
    if Self.airPlayDevice() != nil {
      if player.rate == 0, !pausedByUser {
        player.play()
      }
    } else if player.rate != 0 || player.isExternalPlaybackActive {
      // Switched back to the phone: end the cast instead of playing here.
      stop()
    }
    sendState()
  }

  private static func airPlayDevice() -> String? {
    AVAudioSession.sharedInstance().currentRoute.outputs
      .first { $0.portType == .airPlay }?.portName
  }

  private func state() -> [String: Any] {
    guard let player, let item = player.currentItem else { return ["active": false] }
    let duration = item.duration
    var state: [String: Any] = [
      "active": true,
      "connected": Self.airPlayDevice() != nil,
      "playing": player.timeControlStatus != .paused,
      "positionMs": Int(max(0, item.currentTime().seconds) * 1000),
      "durationMs": duration.isNumeric ? Int(duration.seconds * 1000) : 0,
    ]
    if let device = Self.airPlayDevice() { state["device"] = device }
    if let title { state["title"] = title }
    if let error = item.error { state["error"] = error.localizedDescription }
    return state
  }

  private func sendState() {
    channel.invokeMethod("state", arguments: state())
  }

  // MARK: Device list

  private func showPicker() {
    guard let window = Self.keyWindow() else { return }
    let picker = self.picker ?? AVRoutePickerView()
    if self.picker == nil {
      picker.prioritizesVideoDevices = true
      picker.delegate = self
      // Present but invisible: the device list is anchored to it.
      picker.alpha = 0.011
      picker.isUserInteractionEnabled = false
      self.picker = picker
    }
    if picker.superview !== window {
      window.addSubview(picker)
    }
    let inset = window.safeAreaInsets
    picker.frame = CGRect(
      x: window.bounds.width - inset.right - 44, y: inset.top, width: 44, height: 44)
    // AVRoutePickerView has no API to open its menu; tapping its button does.
    func button(in view: UIView) -> UIButton? {
      if let button = view as? UIButton { return button }
      for subview in view.subviews {
        if let button = button(in: subview) { return button }
      }
      return nil
    }
    button(in: picker)?.sendActions(for: .touchUpInside)
  }

  func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
    // Closed without choosing an AirPlay device: cancel the cast. The route
    // change can arrive slightly after the list closes.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
      guard let self, self.player != nil else { return }
      if Self.airPlayDevice() == nil { self.stop() }
    }
  }

  private static func keyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first { $0.isKeyWindow }
  }
}
