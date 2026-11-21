import Foundation
import Network

/// Serves the HLS playlists of an AirPlay cast to the receiver over Wi-Fi.
///
/// The receiver loads everything itself, and it cannot read the private-scheme
/// playlists the system player uses (SystemPlayerPlaylistLoader). bilibili's
/// TV play URLs need no Referer, so the receiver can fetch their DASH files
/// directly: only the small playlists built from them come from the phone,
/// and the media segments still come straight from the CDN.
///
/// The playlists hold signed CDN URLs that carry the user's id, so they are
/// served on Wi-Fi only, under a random path, and only until the cast ends
/// or is replaced (`stop()`). Anything else gets a 404.
///
/// Sendable: its mutable state is only used on `queue`.
final class AirPlayPlaylistServer: @unchecked Sendable {
  enum Failure: Error {
    /// No IPv4 address on Wi-Fi, e.g. cellular only, or peer-to-peer AirPlay.
    case noWiFi
    case listenerFailed
  }

  /// Unguessable first path component.
  private let token: String
  /// Playlists by request path, e.g. "/<token>/master.m3u8".
  private let playlists: [String: Data]
  private let onReceiverFetch: ((String) -> Void)?
  private let queue = DispatchQueue(label: "piliplus.airplay-playlists")
  // Only used on `queue`.
  private var listener: NWListener?
  private var started: CheckedContinuation<UInt16, Error>?
  private var connections: [ObjectIdentifier: NWConnection] = [:]
  private var stopped = false
  /// The address served on. This phone's own AVPlayer connects from it too.
  private var address: IPv4Address?

  /// A request head larger than this is not a playlist request.
  private static let maxHeadLength = 8 * 1024
  private static let maxConnections = 16
  /// Closes connections that send no complete request in time.
  private static let idleTimeout: TimeInterval = 10

  /// `playlists` by file name, as `SystemPlayerPlaylistLoader.makePlaylists`
  /// returns them; the master refers to the others by relative path.
  /// `onReceiverFetch` gets, on the main queue, the file name of each
  /// playlist a receiver (any client but this phone) fetches, e.g.
  /// fallback.m3u8 when it plays that variant.
  init(playlists: [String: String], onReceiverFetch: ((String) -> Void)? = nil) {
    let token = UUID().uuidString
    self.token = token
    self.playlists = Dictionary(
      uniqueKeysWithValues: playlists.map { ("/\(token)/\($0.key)", Data($0.value.utf8)) })
    self.onReceiverFetch = onReceiverFetch
  }

  /// Starts listening on a random port on Wi-Fi and returns the master
  /// playlist's URL, e.g. http://192.168.1.20:52014/<token>/master.m3u8.
  func start() async throws -> URL {
    guard let host = Self.wifiIPv4() else { throw Failure.noWiFi }
    let parameters = NWParameters.tcp
    parameters.requiredInterfaceType = .wifi
    let listener = try NWListener(using: parameters)
    listener.newConnectionHandler = { [weak self] connection in
      guard let self else { return connection.cancel() }
      self.accept(connection)
    }
    listener.stateUpdateHandler = { [weak self, weak listener] state in
      switch state {
      case .ready:
        self?.finishStarting(
          listener?.port.map { .success($0.rawValue) } ?? .failure(Failure.listenerFailed))
      case .failed, .cancelled:
        self?.finishStarting(.failure(Failure.listenerFailed))
      default:
        break
      }
    }
    let port: UInt16 = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        queue.async {
          // stop() came first.
          if self.stopped { return continuation.resume(throwing: CancellationError()) }
          self.started = continuation
          self.listener = listener
          self.address = IPv4Address(host)
          listener.start(queue: self.queue)
        }
      }
    } onCancel: {
      stop()
    }
    guard let url = URL(string: "http://\(host):\(port)/\(token)/master.m3u8") else {
      throw Failure.listenerFailed
    }
    return url
  }

  /// Stops listening and closes open connections. Safe to call repeatedly.
  func stop() {
    queue.async {
      self.stopped = true
      self.listener?.cancel()
      self.listener = nil
      self.finishStarting(.failure(CancellationError()))
      for connection in self.connections.values { connection.cancel() }
      self.connections.removeAll()
    }
  }

  /// Answers `start()` once; later listener states are ignored.
  private func finishStarting(_ result: Result<UInt16, Error>) {
    started?.resume(with: result)
    started = nil
  }

  // MARK: HTTP

  private func accept(_ connection: NWConnection) {
    guard !stopped, connections.count < Self.maxConnections else { return connection.cancel() }
    let id = ObjectIdentifier(connection)
    connections[id] = connection
    connection.stateUpdateHandler = { [weak self] state in
      switch state {
      case .failed, .cancelled:
        self?.connections[id] = nil
      default:
        break
      }
    }
    connection.start(queue: queue)
    queue.asyncAfter(deadline: .now() + Self.idleTimeout) { connection.cancel() }
    receive(connection, head: Data())
  }

  private func receive(_ connection: NWConnection, head: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxHeadLength) {
      [weak self] data, _, isComplete, error in
      guard let self, !self.stopped else { return connection.cancel() }
      var head = head
      if let data { head.append(data) }
      if let end = head.range(of: Data("\r\n\r\n".utf8)) {
        self.respond(connection, head: head[..<end.lowerBound])
      } else if error != nil || isComplete || head.count > Self.maxHeadLength {
        connection.cancel()
      } else {
        self.receive(connection, head: head)
      }
    }
  }

  /// One response per connection: playlists are tiny, so there is nothing
  /// to gain from keep-alive.
  private func respond(_ connection: NWConnection, head: Data) {
    let lines = String(decoding: head, as: UTF8.self).components(separatedBy: "\r\n")
    let parts = lines[0].split(separator: " ")
    var body: Data?
    var method = ""
    var path = ""
    if parts.count == 3 {
      method = String(parts[0])
      path = String(
        parts[1].split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])
      if method == "GET" || method == "HEAD" { body = playlists[path] }
    }
    let name = (path as NSString).lastPathComponent
    let receiver = !isThisPhone(connection.endpoint)
    // Which playlist and who asked (the receiver or this phone), without the
    // path: it would let anyone reading the log fetch the signed URLs.
    let agent = lines.first { $0.lowercased().hasPrefix("user-agent:") }?.dropFirst(11)
    NSLog(
      "AirPlay playlists: %@ %@ %@ %@ (%@)", String(method.prefix(8)), body == nil ? "-" : name,
      body == nil ? "404" : "200", receiver ? "receiver" : "phone",
      agent.map { String($0.trimmingCharacters(in: .whitespaces).prefix(120)) } ?? "no user agent")
    if body != nil, method == "GET", receiver, let onReceiverFetch {
      DispatchQueue.main.async { onReceiverFetch(name) }
    }
    var header: String
    if let body {
      header =
        "HTTP/1.1 200 OK\r\nContent-Type: application/vnd.apple.mpegurl\r\n"
        + "Content-Length: \(body.count)\r\n"
    } else {
      header = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n"
    }
    header += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
    var response = Data(header.utf8)
    if let body, method == "GET" { response.append(body) }
    connection.send(
      content: response, contentContext: .finalMessage, isComplete: true,
      completion: .contentProcessed { _ in connection.cancel() })
  }

  /// Whether a client connected from this phone: its own AVPlayer reads the
  /// playlists too (from the address served on), and a receiver cannot use
  /// that address.
  private func isThisPhone(_ endpoint: NWEndpoint) -> Bool {
    guard case .hostPort(let host, _) = endpoint else { return false }
    func ours(_ a: IPv4Address) -> Bool { a == address || a.isLoopback }
    switch host {
    case .ipv4(let a): return ours(a)
    case .ipv6(let a): return a.isLoopback || a.asIPv4.map(ours) == true  // IPv4-mapped
    default: return false
    }
  }

  // MARK: Wi-Fi address

  /// `_IOWR('i', 173, struct ifreq)` from <sys/sockio.h>; Swift does not
  /// import the macro.
  private static let getFunctionalType: UInt =
    0xC000_0000 | (UInt(MemoryLayout<ifreq>.size & 0x1fff) << 16)
    | (UInt(UInt8(ascii: "i")) << 8) | 173

  /// The IPv4 address of the Wi-Fi interface, by interface type rather than
  /// name (en0 is not always Wi-Fi). AWDL (peer-to-peer AirPlay) has no IPv4
  /// address, so then there is none.
  static func wifiIPv4() -> String? {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0, let first = list else { return nil }
    defer { freeifaddrs(list) }
    let fd = socket(AF_INET, SOCK_DGRAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let ifa = entry.pointee
      let flags = Int32(ifa.ifa_flags)
      guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
        flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0
      else { continue }
      var request = ifreq()
      withUnsafeMutableBytes(of: &request.ifr_name) { name in
        _ = strlcpy(name.baseAddress!.assumingMemoryBound(to: CChar.self), ifa.ifa_name, name.count)
      }
      guard ioctl(fd, getFunctionalType, &request) == 0,
        request.ifr_ifru.ifru_functional_type == UInt32(IFRTYPE_FUNCTIONAL_WIFI_INFRA)
      else { continue }
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      guard
        getnameinfo(
          addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0,
          NI_NUMERICHOST) == 0
      else { continue }
      return String(cString: host)
    }
    return nil
  }
}
