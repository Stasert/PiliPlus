import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dlna_dart/dlna.dart';
import 'package:flutter/foundation.dart';

/// SSDP device search that does not give up when part of multicast fails.
///
/// `DLNAManager` from dlna_dart joins the multicast group on every network
/// interface, cellular and VPN included, and aborts the whole search if any
/// one join or the bind of port 1900 fails. Then nothing is ever sent, so iOS
/// does not even show the local network prompt. Here only LAN interfaces are
/// joined, each one on its own, port 1900 may be shared, and the NOTIFY
/// listener is optional. If multicast still does not work (or finds nothing
/// on iOS), the search request is also sent by unicast to every host in the
/// local /24 subnet, which needs no multicast entitlement.
class DlnaSearcher {
  static const _ssdpPort = 1900;
  static final _ssdpGroup = InternetAddress('239.255.255.250');
  static const _renderer = 'urn:schemas-upnp-org:device:MediaRenderer:1';
  static const _avTransport = 'urn:schemas-upnp-org:service:AVTransport:1';

  RawDatagramSocket? _client;
  RawDatagramSocket? _listener;
  final List<StreamSubscription<RawSocketEvent>> _subscriptions = [];
  Timer? _sender;
  DeviceManager? _deviceManager;
  List<InternetAddress> _lanHosts = const [];
  bool _multicastFailed = false;
  Object? _lastError;
  bool _noLan = false;
  bool _sweeping = false;
  bool _sendFailed = false;
  int _round = 0;

  /// Skips multicast entirely, to exercise the iOS fallback on other systems.
  @visibleForTesting
  static bool unicastOnly = false;

  bool _isCurrent(DeviceManager dm) => identical(_deviceManager, dm);

  /// The latest network error of the last search, for the "no device" page.
  Object? get lastError => _lastError;

  /// The last search found no Wi-Fi or other LAN connection (e.g. 4G only).
  bool get noLan => _noLan;

  Future<DeviceManager> start() async {
    stop();
    _round = 0;
    _multicastFailed = false;
    _lastError = null;
    _noLan = false;
    final dm = DeviceManager();
    _deviceManager = dm;
    try {
      // Replies to M-SEARCH come back by unicast to this socket.
      final client = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      if (!_isCurrent(dm)) {
        client.close();
        return dm;
      }
      _client = client;
      _subscriptions.add(_listen(client, dm));

      if (unicastOnly) {
        _multicastFailed = true;
      } else {
        await _startListener(dm);
        if (!_isCurrent(dm)) return dm;
      }

      _lanHosts = await _findLanHosts();
      _noLan = _lanHosts.isEmpty;
      if (!_isCurrent(dm)) return dm;

      _search();
      _sender = Timer.periodic(const Duration(seconds: 2), (_) => _search());
      return dm;
    } catch (_) {
      if (_isCurrent(dm)) stop();
      rethrow;
    }
  }

  /// Listens for NOTIFY announcements on the SSDP port. Optional: devices are
  /// still found through M-SEARCH replies when this is not allowed.
  Future<void> _startListener(DeviceManager dm) async {
    RawDatagramSocket? listener;
    try {
      try {
        listener = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          _ssdpPort,
        );
      } on SocketException {
        // Another socket already holds the SSDP port; share it if allowed.
        listener = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          _ssdpPort,
          reusePort: !Platform.isWindows,
        );
      }
      if (!_isCurrent(dm)) {
        listener.close();
        return;
      }
      await _joinMulticast(listener);
      _listener = listener;
      _subscriptions.add(_listen(listener, dm));
    } catch (e) {
      listener?.close();
      _multicastFailed = true;
      _lastError = e;
      if (kDebugMode) debugPrint('DLNA: multicast listener unavailable: $e');
    }
  }

  Future<void> _joinMulticast(RawDatagramSocket socket) async {
    final interfaces = await _ipv4Interfaces();
    Object? lastError;
    var joined = false;
    for (final interface in interfaces) {
      if (interface.addresses.isEmpty) continue;
      try {
        if (Platform.isIOS) {
          // https://github.com/dart-lang/sdk/issues/42250
          socket.setRawOption(
            RawSocketOption(
              RawSocketOption.levelIPv4,
              12, // IP_ADD_MEMBERSHIP
              Uint8List.fromList(
                _ssdpGroup.rawAddress + interface.addresses.first.rawAddress,
              ),
            ),
          );
        } else {
          socket.joinMulticast(_ssdpGroup, interface);
        }
        joined = true;
      } catch (e) {
        lastError = e;
        if (kDebugMode) debugPrint('DLNA: join on ${interface.name}: $e');
      }
    }
    if (joined) return;
    if (Platform.isIOS) {
      throw lastError ?? const SocketException('no LAN interface');
    }
    socket.joinMulticast(_ssdpGroup);
  }

  StreamSubscription<RawSocketEvent> _listen(
    RawDatagramSocket socket,
    DeviceManager dm,
  ) {
    return socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      while (true) {
        final d = socket.receive();
        if (d == null) break;
        try {
          dm.onMessage(String.fromCharCodes(d.data).trim());
        } catch (_) {}
      }
    }, onError: _onSendError);
  }

  /// Failed sends are reported on the socket stream, not thrown by `send`.
  void _onSendError(Object e) {
    // Most likely multicast is blocked or the local network permission is
    // missing; fall back to (or keep retrying) the unicast sweep.
    _sendFailed = true;
    _multicastFailed = true;
    _lastError = e;
    if (kDebugMode) debugPrint('DLNA: send failed: $e');
  }

  Future<void> _search() async {
    final client = _client;
    if (client == null) return;
    final round = _round++;

    final List<String> targets;
    if (round == 0) {
      targets = const ['ssdp:all', _renderer, _avTransport];
    } else {
      targets = switch (round % 5) {
        0 => const ['ssdp:all'],
        1 || 3 => const [_renderer],
        _ => const [_avTransport],
      };
    }

    for (var i = 0; i < targets.length && !unicastOnly; i++) {
      if (!identical(_client, client)) return;
      try {
        client.send(
          searchRequest(targets[i], host: '${_ssdpGroup.address}:$_ssdpPort'),
          _ssdpGroup,
          _ssdpPort,
        );
      } catch (e) {
        _onSendError(e);
      }
      if (i < targets.length - 1) {
        await Future.delayed(const Duration(milliseconds: 30));
      }
    }

    // Fallback only: when multicast failed, or on iOS when it found nothing
    // after ~6s (iOS may drop multicast sends without reporting an error).
    // A full sweep is ~250 small packets, so do it every third round.
    final foundNothing = _deviceManager?.deviceList.isEmpty ?? true;
    final fallback =
        _multicastFailed || (Platform.isIOS && foundNothing && round >= 3);
    if (fallback && round % 3 == 0) {
      await _sweep(client);
    }
  }

  /// Sends a unicast M-SEARCH to every host in the local subnet.
  Future<void> _sweep(RawDatagramSocket client) async {
    if (_sweeping || _lanHosts.isEmpty) return;
    _sweeping = true;
    _sendFailed = false;
    try {
      var sent = 0;
      for (final host in _lanHosts) {
        if (!identical(_client, client)) return;
        try {
          client.send(
            searchRequest(_renderer, host: '${host.address}:$_ssdpPort'),
            host,
            _ssdpPort,
          );
        } catch (e) {
          _onSendError(e);
        }
        if (++sent % 32 == 0) {
          await Future.delayed(const Duration(milliseconds: 10));
          // Usually the local network permission is not granted (yet), e.g.
          // while iOS shows its prompt. Stop; the next round tries again.
          if (_sendFailed) return;
        }
      }
    } finally {
      _sweeping = false;
    }
  }

  static Future<List<NetworkInterface>> _ipv4Interfaces() async {
    final interfaces = await NetworkInterface.list(
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return interfaces.where((e) => isLanInterfaceName(e.name)).toList();
  }

  static Future<List<InternetAddress>> _findLanHosts() async {
    try {
      final own = [
        for (final interface in await _ipv4Interfaces()) ...interface.addresses,
      ];
      return subnetHosts(own);
    } catch (_) {
      return const [];
    }
  }

  void stop() {
    _sender?.cancel();
    _sender = null;
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    _client?.close();
    _client = null;
    _listener?.close();
    _listener = null;
    _deviceManager?.dispose();
    _deviceManager = null;
    _lanHosts = const [];
    _sweeping = false;
  }

  @visibleForTesting
  static List<int> searchRequest(String target, {required String host}) =>
      utf8.encode(
        'M-SEARCH * HTTP/1.1\r\n'
        'HOST: $host\r\n'
        'ST: $target\r\n'
        'MX: 1\r\n'
        'MAN: "ssdp:discover"\r\n\r\n',
      );

  /// Cellular, VPN and peer-to-peer interfaces never have TVs on them; iOS
  /// cellular addresses are often in 10.0.0.0/8 too, so filter by name.
  @visibleForTesting
  static bool isLanInterfaceName(String name) {
    const skipped = ['pdp_ip', 'utun', 'ipsec', 'awdl', 'llw', 'rmnet', 'tun'];
    return !skipped.any(name.startsWith);
  }

  /// Every other host in the /24 of each private IPv4 address. The real
  /// netmask is not available from dart:io; /24 covers home networks.
  @visibleForTesting
  static List<InternetAddress> subnetHosts(List<InternetAddress> own) {
    final seenPrefixes = <String>{};
    final ownAddresses = {for (final a in own) a.address};
    final hosts = <InternetAddress>[];
    for (final address in own) {
      if (address.type != InternetAddressType.IPv4) continue;
      final b = address.rawAddress;
      final isPrivate =
          b[0] == 10 ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168);
      if (!isPrivate) continue;
      final prefix = '${b[0]}.${b[1]}.${b[2]}';
      // At most two subnets, e.g. Wi-Fi plus a personal hotspot.
      if (seenPrefixes.length >= 2 || !seenPrefixes.add(prefix)) continue;
      for (var i = 1; i < 255; i++) {
        final ip = '$prefix.$i';
        if (!ownAddresses.contains(ip)) hosts.add(InternetAddress(ip));
      }
    }
    return hosts;
  }
}
