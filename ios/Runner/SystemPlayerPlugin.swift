import AVFoundation
import Flutter
import UIKit
import VideoToolbox

/// System player (AVPlayer) used instead of mpv for HDR / Dolby Vision videos
/// on iOS (and optionally for every on-demand video). mpv renders into an
/// 8-bit Flutter texture and its HDR output never matched AVPlayer, so these
/// videos are handed to AVPlayer and shown in a native platform view.
///
/// Dart side: `lib/plugin/pl_player/system_player.dart`.
final class SystemPlayerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  static let channelName = "piliplus/system_player"
  static let viewType = "piliplus/system_player_view"

  private static weak var shared: SystemPlayerPlugin?
  private var sessions: [Int: SystemPlayerSession] = [:]
  private var nextId = 1
  private var eventSink: FlutterEventSink?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SystemPlayerPlugin()
    shared = instance
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    FlutterEventChannel(name: "\(channelName)/events", binaryMessenger: registrar.messenger())
      .setStreamHandler(instance)
    registrar.register(SystemPlayerViewFactory(), withId: viewType)
  }

  static func session(_ id: Int) -> SystemPlayerSession? { shared?.sessions[id] }

  /// Platform views by session id, for PiP (see PipPlugin).
  private static var views: [Int: WeakView] = [:]
  private final class WeakView {
    weak var value: SystemPlayerPlatformView?
    init(_ value: SystemPlayerPlatformView) { self.value = value }
  }

  static func register(view: SystemPlayerPlatformView, for id: Int) {
    views = views.filter { $0.value.value != nil }
    views[id] = WeakView(view)
  }

  static func playerLayer(for id: Int) -> AVPlayerLayer? {
    views[id]?.value?.playerLayer
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func emit(_ id: Int, _ type: String, _ payload: [String: Any] = [:]) {
    var event = payload
    event["id"] = id
    event["type"] = type
    eventSink?(event)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let id = args["id"] as? Int ?? 0
    switch call.method {
    case "create":
      let newId = nextId
      nextId += 1
      sessions[newId] = SystemPlayerSession { [weak self] type, payload in
        self?.emit(newId, type, payload)
      }
      result(newId)
    case "load":
      guard let session = sessions[id] else { return result(nil) }
      session.load(args) { error in result(error) }
    case "play":
      sessions[id]?.play()
      result(nil)
    case "pause":
      sessions[id]?.player.pause()
      result(nil)
    case "seek":
      let ms = args["ms"] as? Int ?? 0
      sessions[id]?.seek(ms: ms) { result(nil) }
    case "setRate":
      sessions[id]?.setRate(Float(args["rate"] as? Double ?? 1))
      result(nil)
    case "setVolume":
      sessions[id]?.player.volume = Float(args["volume"] as? Double ?? 1)
      result(nil)
    case "info":
      result(sessions[id]?.info() ?? [:])
    case "screenshot":
      guard let session = sessions[id] else { return result(nil) }
      session.screenshot { data in
        result(data.map { FlutterStandardTypedData(bytes: $0) })
      }
    case "dispose":
      sessions.removeValue(forKey: id)?.dispose()
      result(nil)
    case "supportsHardwareDecode":
      result(Self.supportsHardwareDecode(args["codec"] as? String ?? ""))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// AVPlayer has no software fallback for AV1 (or HEVC on very old devices).
  static func supportsHardwareDecode(_ codec: String) -> Bool {
    let type: CMVideoCodecType
    switch codec.prefix(4) {
    case "av01": type = kCMVideoCodecType_AV1
    case "hev1", "hvc1", "dvh1", "dvhe": type = kCMVideoCodecType_HEVC
    default: return true
    }
    return VTIsHardwareDecodeSupported(type)
  }
}

final class SystemPlayerSession: NSObject {
  /// `load` result when it was cancelled; not an error to show.
  static let cancelled = "cancelled"
  /// `load` result for a source known not to work; mpv plays it, no message.
  static let unsupported = "unsupported"
  let player = AVPlayer()
  private let emit: (String, [String: Any]) -> Void
  private var loader: SystemPlayerPlaylistLoader?
  private var timeObserver: Any?
  private var observations: [NSKeyValueObservation] = []
  private var itemObservers: [NSObjectProtocol] = []
  private var rate: Float = 1
  private var loadTask: Task<Void, Never>?
  private var lastPlaying: Bool?
  private var lastBuffering: Bool?
  // Shown in the playback info panel.
  private var videoInfo: SystemPlayerHLS.TrackInfo?
  private var audioInfo: SystemPlayerHLS.TrackInfo?
  private var videoURL: URL?
  private var audioURL: URL?
  private var frameRate: Double?
  /// Catches failures AVPlayer does not report as errors, so mpv can take over.
  private var watchdog: Timer?

  init(emit: @escaping (String, [String: Any]) -> Void) {
    self.emit = emit
    super.init()
    player.automaticallyWaitsToMinimizeStalling = true
    // Receivers cannot load the custom-scheme playlists; AirPlay casting has
    // its own entry on the cast page (AirPlayPlugin).
    player.allowsExternalPlayback = false
    player.appliesMediaSelectionCriteriaAutomatically = true
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(value: 1, timescale: 5), queue: .main
    ) { [weak self] time in
      self?.reportPosition(time)
    }
    observations.append(
      player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
        DispatchQueue.main.async { self?.reportStatus() }
      })
  }

  func load(_ args: [String: Any], completion: @escaping (String?) -> Void) {
    loadTask?.cancel()
    guard let video = Self.track(args["video"]) else { return completion("bad video") }
    let audio = Self.track(args["audio"])
    let headers = args["headers"] as? [String: String] ?? [:]
    let frameRate = args["frameRate"] as? Double
    let startMs = args["startMs"] as? Int ?? 0
    loadTask = Task { @MainActor in
      do {
        let asset: AVAsset
        let loader: SystemPlayerPlaylistLoader?
        let videoInfo: SystemPlayerHLS.TrackInfo
        let audioInfo: SystemPlayerHLS.TrackInfo?
        if video.url.isFileURL {
          (asset, videoInfo, audioInfo) = try await SystemPlayerLocal.makeAsset(
            video: video.url, audio: audio?.url)
          loader = nil
        } else {
          (asset, loader, videoInfo, audioInfo) =
            try await SystemPlayerPlaylistLoader.makeAsset(
              video: video, audio: audio, frameRate: frameRate, headers: headers)
        }
        if Task.isCancelled { return }
        self.loader = loader
        self.videoInfo = videoInfo
        self.audioInfo = audioInfo
        self.videoURL = video.url
        self.audioURL = audio?.url
        self.frameRate = frameRate
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 30
        self.observe(item)
        self.player.replaceCurrentItem(with: item)
        self.startWatchdog(item)
        if startMs > 0 {
          await self.player.seek(
            to: CMTime(value: CMTimeValue(startMs), timescale: 1000),
            toleranceBefore: .zero, toleranceAfter: .zero)
        }
        completion(nil)
      } catch {
        // Superseded by another load, or the page closed while loading.
        if Task.isCancelled || (error as? URLError)?.code == .cancelled {
          return completion(SystemPlayerSession.cancelled)
        }
        if case SystemPlayerLocalError.hev1 = error {
          return completion(SystemPlayerSession.unsupported)
        }
        completion(Self.describe(error, item: nil))
      }
    }
  }

  /// Short error text shown to the user, e.g. "CoreMedia -12927 · HTTP 403".
  static func describe(_ error: Error?, item: AVPlayerItem?) -> String {
    var parts: [String] = []
    func add(_ e: NSError) {
      parts.append("\(e.domain.replacingOccurrences(of: "ErrorDomain", with: "")) \(e.code)")
    }
    if let e = error as NSError? {
      add(e)
      if let underlying = e.userInfo[NSUnderlyingErrorKey] as? NSError { add(underlying) }
    }
    // The access/error log has the HTTP status of failed segment requests.
    if let event = item?.errorLog()?.events.last {
      if event.errorStatusCode != 0 { parts.append("\(event.errorStatusCode)") }
      if let comment = event.errorComment, !comment.isEmpty { parts.append(comment) }
    }
    if parts.isEmpty, let error { parts.append("\(error)") }
    return String((parts.isEmpty ? "unknown" : parts.joined(separator: " · ")).prefix(160))
  }

  private static func track(_ value: Any?) -> DashTrack? {
    guard let map = value as? [String: Any], let s = map["url"] as? String,
      let url = URL(string: s)
    else { return nil }
    return DashTrack(
      url: url, indexEnd: map["indexEnd"] as? Int ?? 65535,
      bandwidth: map["bandwidth"] as? Int ?? 1)
  }

  private func observe(_ item: AVPlayerItem) {
    for o in itemObservers { NotificationCenter.default.removeObserver(o) }
    itemObservers.removeAll()
    observations = observations.prefix(1).map { $0 }  // keep timeControlStatus
    observations.append(
      item.observe(\.status, options: [.new]) { [weak self] item, _ in
        DispatchQueue.main.async {
          guard let self else { return }
          if item.status == .readyToPlay {
            let d = item.duration
            if d.isNumeric { self.emit("duration", ["ms": Int(d.seconds * 1000)]) }
          } else if item.status == .failed {
            self.emit("error", ["message": Self.describe(item.error, item: item)])
          }
        }
      })
    observations.append(
      item.observe(\.presentationSize, options: [.new]) { [weak self] item, _ in
        let s = item.presentationSize
        if s.width > 0 {
          DispatchQueue.main.async {
            self?.emit("size", ["width": Int(s.width), "height": Int(s.height)])
          }
        }
      })
    let center = NotificationCenter.default
    itemObservers.append(
      center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main)
      { [weak self] _ in self?.emit("completed", [:]) })
    itemObservers.append(
      center.addObserver(
        forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
      ) { [weak self] n in
        let error = n.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey]
        self?.emit("error", ["message": Self.describe(error as? Error, item: item)])
      })
  }

  private func reportPosition(_ time: CMTime) {
    guard let item = player.currentItem, time.isNumeric else { return }
    var buffered = 0.0
    for value in item.loadedTimeRanges {
      let r = value.timeRangeValue
      if r.start <= time, time <= r.end { buffered = r.end.seconds }
    }
    emit("position", ["ms": Int(time.seconds * 1000), "bufferedMs": Int(buffered * 1000)])
  }

  private func reportStatus() {
    let playing = player.timeControlStatus != .paused
    let buffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
    if playing != lastPlaying {
      lastPlaying = playing
      emit("playing", ["value": playing])
    }
    if buffering != lastBuffering {
      lastBuffering = buffering
      emit("buffering", ["value": buffering])
    }
  }

  /// The current frame as PNG. Frames are taken in the decoder's own format
  /// (no conversion that could fail on device) and HDR is tone mapped to SDR
  /// by Core Image, so saved screenshots look right in Photos.
  func screenshot(completion: @escaping (Data?) -> Void) {
    guard let item = player.currentItem else { return completion(nil) }
    let output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
    item.add(output)
    // Only attached for the screenshot; a paused player renders no new frame
    // into a new output, so re-seek to the same time to get one.
    let time = item.currentTime()
    let paused = player.rate == 0
    if paused {
      player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    var attempts = 0
    func poll() {
      attempts += 1
      let now = output.itemTime(forHostTime: CACurrentMediaTime())
      let buffer =
        output.copyPixelBuffer(forItemTime: paused ? time : now, itemTimeForDisplay: nil)
        ?? (paused ? output.copyPixelBuffer(forItemTime: now, itemTimeForDisplay: nil) : nil)
      if let buffer {
        item.remove(output)
        DispatchQueue.global(qos: .userInitiated).async {
          let data = Self.png(from: buffer)
          DispatchQueue.main.async { completion(data) }
        }
      } else if attempts < 80 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
      } else {
        item.remove(output)
        NSLog("SystemPlayer: screenshot got no frame")
        completion(nil)
      }
    }
    poll()
  }

  static func png(from buffer: CVPixelBuffer) -> Data? {
    let image = CIImage(cvPixelBuffer: buffer, options: [.toneMapHDRtoSDR: true])
    return CIContext().pngRepresentation(
      of: image, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
  }

  /// What the playback info panel shows while this player is in use.
  func info() -> [String: Any] {
    var m: [String: Any] = [
      "rate": Double(player.rate),
      "volume": Double(player.volume),
      "eligibleForHDR": AVPlayer.eligibleForHDRPlayback,
    ]
    if let v = videoInfo {
      m["videoCodecs"] = v.codecs
      m["supplementalCodecs"] = v.supplementalCodecs
      m["videoRange"] = v.videoRange ?? "SDR"
      m["codedWidth"] = v.width
      m["codedHeight"] = v.height
    }
    m["audioCodecs"] = audioInfo?.codecs
    m["videoUrl"] = videoURL?.absoluteString
    m["audioUrl"] = audioURL?.absoluteString
    m["frameRate"] = frameRate
    guard let item = player.currentItem else { return m }
    let size = item.presentationSize
    if size.width > 0 {
      m["width"] = Int(size.width)
      m["height"] = Int(size.height)
    }
    if let track = item.tracks.first(where: { $0.assetTrack?.mediaType == .video }),
      track.currentVideoFrameRate > 0
    {
      m["currentFrameRate"] = Double(track.currentVideoFrameRate)
    }
    if let event = item.accessLog()?.events.last {
      m["indicatedBitrate"] = event.indicatedBitrate
      m["observedBitrate"] = event.observedBitrate
      m["droppedFrames"] = event.numberOfDroppedVideoFrames
    }
    return m
  }

  func play() {
    if let item = player.currentItem, item.currentTime() >= item.duration, item.duration.isNumeric {
      player.seek(to: .zero)
    }
    player.playImmediately(atRate: rate)
  }

  func setRate(_ rate: Float) {
    self.rate = rate
    if #available(iOS 16.0, *) { player.defaultRate = rate }
    if player.rate != 0 { player.rate = rate }
  }

  func seek(ms: Int, completion: @escaping () -> Void) {
    player.seek(
      to: CMTime(value: CMTimeValue(ms), timescale: 1000),
      toleranceBefore: CMTime(value: 1, timescale: 10), toleranceAfter: CMTime(value: 1, timescale: 10)
    ) { _ in DispatchQueue.main.async(execute: completion) }
  }

  /// AVPlayer can stay "loading" forever without failing, or play the audio
  /// while it cannot decode the video. Both are reported as errors so the
  /// Dart side falls back to mpv.
  private func startWatchdog(_ item: AVPlayerItem) {
    watchdog?.invalidate()
    let started = Date()
    var playedFrom: CMTime?
    watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
      guard let self, self.player.currentItem === item else { return timer.invalidate() }
      switch item.status {
      case .failed:
        timer.invalidate()
      case .unknown:
        // Waiting for the user is not a failure; only count while playback is wanted.
        if self.player.timeControlStatus != .paused,
          Date().timeIntervalSince(started) > 20
        {
          timer.invalidate()
          self.emit("error", ["message": "加载超时"])
        }
      case .readyToPlay:
        if item.presentationSize.width > 0 { return timer.invalidate() }
        guard self.player.timeControlStatus == .playing else { return }
        let now = item.currentTime()
        guard let from = playedFrom else { playedFrom = now; return }
        if (now - from).seconds > 4 {
          timer.invalidate()
          self.emit("error", ["message": "无法解码视频画面"])
        }
      @unknown default:
        break
      }
    }
  }

  func dispose() {
    loadTask?.cancel()
    watchdog?.invalidate()
    watchdog = nil
    if let timeObserver { player.removeTimeObserver(timeObserver) }
    timeObserver = nil
    for o in itemObservers { NotificationCenter.default.removeObserver(o) }
    itemObservers.removeAll()
    observations.removeAll()
    player.pause()
    player.replaceCurrentItem(with: nil)
    loader = nil
  }
}

// MARK: - Platform view

final class SystemPlayerViewFactory: NSObject, FlutterPlatformViewFactory {
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?)
    -> FlutterPlatformView
  {
    let id = (args as? [String: Any])?["id"] as? Int ?? 0
    return SystemPlayerPlatformView(sessionId: id)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class SystemPlayerLayerView: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }
  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

final class SystemPlayerPlatformView: NSObject, FlutterPlatformView {
  private let content = SystemPlayerLayerView()
  private var observers: [NSObjectProtocol] = []

  var playerLayer: AVPlayerLayer { content.playerLayer }

  init(sessionId: Int) {
    super.init()
    SystemPlayerPlugin.register(view: self, for: sessionId)
    content.backgroundColor = .black
    content.isUserInteractionEnabled = false
    // Flutter sizes this view to the video's aspect ratio (FittedBox).
    content.playerLayer.videoGravity = .resize
    let player = SystemPlayerPlugin.session(sessionId)?.player
    content.playerLayer.player = player
    // A player attached to a layer is paused when the app goes to the
    // background; detach it so "continue playing in background" keeps audio.
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
      ) { [weak self] _ in
        guard let self else { return }
        // In PiP (or about to enter it automatically) the layer must keep
        // its player, AVKit handles background playback then.
        if #available(iOS 15.0, *),
          PlayerLayerPipSession.engagedLayer === self.content.playerLayer
        {
          return
        }
        self.content.playerLayer.player = nil
      })
    observers.append(
      center.addObserver(
        forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.content.playerLayer.player = player })
  }

  deinit {
    for o in observers { NotificationCenter.default.removeObserver(o) }
  }

  func view() -> UIView { content }
}
