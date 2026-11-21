import AVKit
import Flutter
import UIKit

/// AirPlay casting. The receiver (Apple TV, Mac, AirPlay 2 TV) downloads the
/// video itself, from bilibili's TV play URLs, which need no Referer.
///
/// When the TV API offers DASH files (HDR, Dolby Vision, 4K, ...), the
/// receiver gets the HLS playlists the system player builds from them, served
/// from the phone over Wi-Fi (AirPlayPlaylistServer); the media still comes
/// from the CDN. Otherwise, or when the receiver cannot play that, it gets the
/// same progressive MP4 as DLNA casting (SDR, at most 720P).
///
/// No player screen is shown: the system device list opens over the cast
/// page, an AVPlayer without a layer plays to the chosen receiver, and its
/// state is reported to the cast page, which is the remote control.
///
/// The DASH stream only goes on that player once a receiver is connected:
/// AVPlayer buffers an item even while paused, so the phone itself would
/// download the stream while the device list is open (35 MB of a 1080P
/// stream in 10 s), and bilibili's CDN answers 403 once the same signed URLs
/// have been pulled a few times. For the same reason the Dart side fetches
/// new DASH URLs for every cast. The MP4 goes on the player right away, as
/// it always has.
///
/// Dart side: `lib/utils/ios/airplay_helper.dart`.
final class AirPlayPlugin: NSObject, FlutterPlugin, AVRoutePickerViewDelegate {
  /// The DASH stream to cast instead of the MP4.
  private struct Dash {
    let video: DashTrack
    let audio: DashTrack?
    let frameRate: Double?
    /// A second variant for receivers that cannot play `video`, e.g. HDR10
    /// next to Dolby Vision.
    let fallback: DashTrack?
    let fallbackFrameRate: Double?
    let quality: String?
    let fallbackQuality: String?
  }

  /// What to put on the player.
  private struct Cast {
    let asset: AVAsset
    let quality: String?
    let isDash: Bool
  }

  /// Fetching the DASH stream's URLs (Dart side) and building its playlists
  /// take a few small requests; past this the MP4 is cast instead.
  private static let prepareTimeout: TimeInterval = 15
  /// Seconds the DASH stream may take to start playing once a receiver is
  /// connected; after that the MP4 is cast instead.
  private static let startTimeout = 15

  private let channel: FlutterMethodChannel
  private var player: AVPlayer?
  private var timeObserver: Any?
  private var observations: [NSKeyValueObservation] = []
  private var itemObservations: [NSKeyValueObservation] = []
  private var itemObservers: [NSObjectProtocol] = []
  private var routeObserver: NSObjectProtocol?
  private var picker: AVRoutePickerView?
  private var title: String?
  /// Paused from the cast page; a route change must not resume it.
  private var pausedByUser = false
  private var mp4URL: URL?
  private var mp4Quality: String?
  private var startMs: Int64 = 0
  /// Quality of what is being cast, for the cast page.
  private var quality: String?
  /// Counts start() calls, so that a DASH stream sent for an earlier cast is
  /// ignored.
  private var session = 0
  /// From start() until the DASH stream is ready or given up on: while the
  /// Dart side fetches it, then while its playlists are built (`preparing`).
  private var awaitingDash = false
  private var preparing: Task<Void, Never>?
  /// The DASH stream, ready while no receiver is connected yet.
  private var pending: Cast?
  /// Serves the playlists while the DASH stream is being cast.
  private var server: AirPlayPlaylistServer?
  /// The quality shown once the receiver plays the DASH stream's fallback
  /// variant, see `receiverFetched`.
  private var fallbackLabel: String?
  private var castingDash = false
  private var dashStarted = false
  private var watchdog: Timer?

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
      result(
        start(
          url: url, quality: args["quality"] as? String,
          withDash: args["withDash"] as? Bool == true,
          title: args["title"] as? String,
          startMs: (args["startMs"] as? NSNumber)?.int64Value ?? 0))
    case "dash":
      // Late, or for an earlier cast: ignored.
      if (args["session"] as? NSNumber)?.intValue == session, awaitingDash, preparing == nil {
        dashArrived(Self.dash(args["dash"]))
      }
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

  private static func dash(_ value: Any?) -> Dash? {
    guard let map = value as? [String: Any], let video = SystemPlayerSession.track(map["video"])
    else { return nil }
    return Dash(
      video: video, audio: SystemPlayerSession.track(map["audio"]),
      frameRate: map["frameRate"] as? Double,
      fallback: SystemPlayerSession.track(map["fallback"]),
      fallbackFrameRate: map["fallbackFrameRate"] as? Double, quality: map["quality"] as? String,
      fallbackQuality: map["fallbackQuality"] as? String)
  }

  // MARK: Session

  /// Returns the session to send the DASH stream for ("dash"), or nil when
  /// the MP4 is cast without waiting for one.
  private func start(
    url: URL, quality: String?, withDash: Bool, title: String?, startMs: Int64
  ) -> Int? {
    stop()
    session += 1
    self.title = title
    pausedByUser = false
    mp4URL = url
    mp4Quality = quality
    self.startMs = startMs
    let player = AVPlayer()
    player.allowsExternalPlayback = true
    player.usesExternalPlaybackWhileExternalScreenIsActive = true
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

    var dashSession: Int?
    if withDash, #available(iOS 15.0, *) {
      // The device list opens meanwhile; a receiver is rarely chosen faster.
      awaitingDash = true
      dashSession = session
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.prepareTimeout) {
        [weak self, weak player] in
        guard let self, let player, self.player === player, self.awaitingDash else { return }
        self.preparing?.cancel()
        self.preparing = nil
        self.awaitingDash = false
        NSLog("AirPlay: the DASH stream took too long, casting the MP4")
        self.cast(Cast(asset: AVURLAsset(url: url), quality: quality, isDash: false))
      }
    } else {
      cast(Cast(asset: AVURLAsset(url: url), quality: quality, isDash: false))
    }

    if Self.airPlayDevice() != nil {
      // Already connected (e.g. from Control Center): play there right away.
      player.play()
    } else {
      showPicker()
    }
    sendState()
    return dashSession
  }

  /// Builds the playlists of `dash` and casts it, or the MP4 without one
  /// (e.g. the TV API request failed).
  private func dashArrived(_ dash: Dash?) {
    guard let player, let url = mp4URL else { return }
    guard let dash, #available(iOS 15.0, *) else {
      awaitingDash = false
      return cast(Cast(asset: AVURLAsset(url: url), quality: mp4Quality, isDash: false))
    }
    let session = self.session
    preparing = Task { @MainActor [weak self, weak player] in
      let prepared = await Self.prepare(dash) { [weak self] name in
        self?.receiverFetched(name, session: session)
      }
      guard let self, let player, !Task.isCancelled, self.player === player else {
        prepared?.server.stop()
        return
      }
      self.preparing = nil
      self.awaitingDash = false
      if let prepared {
        self.server = prepared.server
        if let fallback = dash.fallbackQuality {
          self.fallbackLabel = dash.quality.map { "\($0) / \(fallback)" } ?? fallback
        }
        self.cast(Cast(asset: prepared.asset, quality: dash.quality, isDash: true))
      } else {
        self.cast(Cast(asset: AVURLAsset(url: url), quality: self.mp4Quality, isDash: false))
      }
    }
  }

  /// Builds the playlists, serves them on Wi-Fi and checks that AirPlay can
  /// cast the result. Nil when the MP4 has to be cast instead.
  @available(iOS 15.0, *)
  private static func prepare(
    _ dash: Dash, onReceiverFetch: @escaping (String) -> Void
  ) async -> (asset: AVURLAsset, server: AirPlayPlaylistServer)? {
    // Without a Wi-Fi address (e.g. cellular only) no receiver can reach the
    // phone. One that is not on the same Wi-Fi network (peer-to-peer AirPlay)
    // cannot either; the watchdog catches that.
    guard AirPlayPlaylistServer.wifiIPv4() != nil else {
      NSLog("AirPlay: no Wi-Fi address, casting the MP4")
      return nil
    }
    var server: AirPlayPlaylistServer?
    do {
      // The TV play URLs need no headers, and the receiver sends none.
      let (playlists, video, _) = try await SystemPlayerPlaylistLoader.makePlaylists(
        video: dash.video, audio: dash.audio, frameRate: dash.frameRate, headers: [:],
        fallback: dash.fallback.map { ($0, dash.fallbackFrameRate) })
      // An unknown sample entry (e.g. encrypted) leaves CODECS out, and a
      // receiver would not play the stream anyway.
      guard video.codecs != nil else {
        NSLog("AirPlay: unknown video codec, casting the MP4")
        return nil
      }
      let s = AirPlayPlaylistServer(playlists: playlists, onReceiverFetch: onReceiverFetch)
      server = s
      let asset = AVURLAsset(url: try await s.start())
      // `variants` reads the master playlist from the server, so a phone that
      // cannot reach it (e.g. without local network access) casts the MP4
      // now; the compatibility check alone fetches nothing. In tests the
      // plain LAN address loaded without NSAllowsLocalNetworking; Info.plist
      // sets it anyway, as a harmless precaution.
      let (_, compatible) = try await asset.load(.variants, .isCompatibleWithAirPlayVideo)
      guard compatible else {
        NSLog("AirPlay: the DASH stream is not AirPlay compatible, casting the MP4")
        s.stop()
        return nil
      }
      return (asset, s)
    } catch {
      server?.stop()
      // Not the error itself: its description can hold the signed URL.
      let e = error as NSError
      NSLog("AirPlay: the DASH stream failed (%@ %ld), casting the MP4", e.domain, e.code)
      return nil
    }
  }

  /// Puts `cast` on the player. The DASH stream waits for a receiver to be
  /// connected (`routeChanged`): until then the phone would buffer it itself.
  private func cast(_ cast: Cast) {
    if cast.isDash, Self.airPlayDevice() == nil {
      pending = cast
      return sendState()
    }
    put(cast)
  }

  /// Puts `cast` on the player from the cast's start position, and plays it
  /// when a receiver is connected.
  private func put(_ cast: Cast) {
    guard let player else { return }
    pending = nil
    let item = AVPlayerItem(asset: cast.asset)
    if let title {
      let metadata = AVMutableMetadataItem()
      metadata.identifier = .commonIdentifierTitle
      metadata.value = title as NSString
      metadata.extendedLanguageTag = "und"
      item.externalMetadata = [metadata]  // shown on the receiver
    }
    quality = cast.quality
    castingDash = cast.isDash
    dashStarted = false
    observe(item)
    player.replaceCurrentItem(with: item)
    if startMs > 0 {
      player.seek(to: CMTime(value: startMs, timescale: 1000))
    }
    if cast.isDash { startWatchdog(item) }
    if Self.airPlayDevice() != nil, !pausedByUser { player.play() }
    sendState()
  }

  private func observe(_ item: AVPlayerItem) {
    for o in itemObservers { NotificationCenter.default.removeObserver(o) }
    itemObservations = [
      item.observe(\.status) { [weak self] item, _ in
        DispatchQueue.main.async {
          guard let self, self.player?.currentItem === item else { return }
          if item.status == .failed, self.castingDash {
            self.castMP4()
          } else {
            self.sendState()
          }
        }
      }
    ]
    itemObservers = [
      NotificationCenter.default.addObserver(
        forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
      ) { [weak self] _ in
        guard let self, self.player?.currentItem === item else { return }
        if self.castingDash { self.castMP4() } else { self.sendState() }
      }
    ]
  }

  /// A receiver fetched the playlist `name`. Only fallback.m3u8 tells which
  /// variant it plays: it fetches that one when it cannot play the main
  /// variant, or not at the bit rate it measures. AVPlayer also fetches
  /// video.m3u8 when it only plays the fallback, and does not fetch it again
  /// when it switches back, so from then on the cast page shows both
  /// qualities, e.g. 杜比视界 / HDR.
  private func receiverFetched(_ name: String, session: Int) {
    guard session == self.session, castingDash, name == "fallback.m3u8", let fallbackLabel,
      quality != fallbackLabel
    else { return }
    quality = fallbackLabel
    sendState()
  }

  /// A receiver that cannot play the DASH stream does not always fail the
  /// item, e.g. when it cannot reach the phone, and an audio-only AirPlay
  /// device (e.g. a HomePod) never takes the video: the phone then plays it
  /// itself. So the stream has to start playing on the receiver (external
  /// playback) soon after a receiver is connected, or the MP4 is cast.
  private func startWatchdog(_ item: AVPlayerItem) {
    watchdog?.invalidate()
    var waited = 0
    var playedFrom: CMTime?
    watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
      guard let self, let player = self.player, player.currentItem === item else {
        return timer.invalidate()
      }
      // Waiting for the user is not a failure.
      guard Self.airPlayDevice() != nil, !self.pausedByUser else {
        waited = 0
        playedFrom = nil
        return
      }
      if player.isExternalPlaybackActive, player.timeControlStatus == .playing {
        let now = item.currentTime()
        if let from = playedFrom {
          if (now - from).seconds >= 1 {
            self.dashStarted = true
            return timer.invalidate()
          }
        } else {
          playedFrom = now
        }
      }
      waited += 1
      if waited >= Self.startTimeout {
        timer.invalidate()
        NSLog("AirPlay: the DASH stream did not start, casting the MP4")
        self.castMP4()
      }
    }
  }

  /// The receiver cannot play the DASH stream: cast the MP4 instead, from
  /// where the DASH stream got to.
  private func castMP4() {
    guard castingDash, let player, let url = mp4URL else { return }
    watchdog?.invalidate()
    watchdog = nil
    server?.stop()
    server = nil
    fallbackLabel = nil
    let position = player.currentTime()
    if dashStarted, position.isNumeric, position.seconds > 0 {
      startMs = Int64(position.seconds * 1000)
    }
    cast(Cast(asset: AVURLAsset(url: url), quality: mp4Quality, isDash: false))
  }

  private func stop() {
    preparing?.cancel()
    preparing = nil
    awaitingDash = false
    pending = nil
    watchdog?.invalidate()
    watchdog = nil
    server?.stop()  // the playlists hold signed URLs: stop serving them
    server = nil
    fallbackLabel = nil
    castingDash = false
    quality = nil
    if let timeObserver { player?.removeTimeObserver(timeObserver) }
    timeObserver = nil
    observations.removeAll()
    itemObservations.removeAll()
    for o in itemObservers { NotificationCenter.default.removeObserver(o) }
    itemObservers.removeAll()
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
      if let pending {
        put(pending)
      } else if player.rate == 0, !pausedByUser {
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

  /// Also active before anything is on the player: while the DASH stream is
  /// prepared, and until a receiver is connected.
  private func state() -> [String: Any] {
    guard let player else { return ["active": false] }
    let item = player.currentItem
    let duration = item?.duration ?? .invalid
    var state: [String: Any] = [
      "active": true,
      "connected": Self.airPlayDevice() != nil,
      "playing": player.timeControlStatus != .paused,
      "positionMs": Int(max(0, item?.currentTime().seconds ?? 0) * 1000),
      "durationMs": duration.isNumeric ? Int(duration.seconds * 1000) : 0,
    ]
    if let device = Self.airPlayDevice() { state["device"] = device }
    if let title { state["title"] = title }
    if let quality { state["quality"] = quality }
    if let error = item?.error { state["error"] = error.localizedDescription }
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
