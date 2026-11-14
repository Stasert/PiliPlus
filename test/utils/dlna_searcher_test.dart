import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/utils/dlna_searcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('subnet sweep covers the /24 of a private address except itself', () {
    final hosts = DlnaSearcher.subnetHosts([InternetAddress('192.168.1.23')]);
    final ips = hosts.map((e) => e.address).toList();
    expect(ips, hasLength(253));
    expect(ips.first, '192.168.1.1');
    expect(ips.last, '192.168.1.254');
    expect(ips, isNot(contains('192.168.1.23')));
    expect(ips, isNot(contains('192.168.1.0')));
    expect(ips, isNot(contains('192.168.1.255')));
  });

  test('public addresses are never swept and subnets are deduplicated', () {
    expect(DlnaSearcher.subnetHosts([InternetAddress('8.8.8.8')]), isEmpty);
    final hosts = DlnaSearcher.subnetHosts([
      InternetAddress('10.0.0.5'),
      InternetAddress('10.0.0.6'),
      InternetAddress('172.20.10.2'),
      InternetAddress('192.168.0.9'),
    ]);
    final ips = hosts.map((e) => e.address).toList();
    // 10.0.0.0/24 without both own addresses, plus 172.20.10.0/24; the third
    // subnet is dropped because at most two are swept.
    expect(ips, hasLength(252 + 253));
    expect(ips, containsAll(['10.0.0.1', '172.20.10.1']));
    expect(ips, isNot(contains('10.0.0.6')));
    expect(ips, isNot(contains('192.168.0.1')));
  });

  test('cellular and VPN interfaces are skipped', () {
    expect(DlnaSearcher.isLanInterfaceName('en0'), isTrue);
    expect(DlnaSearcher.isLanInterfaceName('bridge100'), isTrue);
    expect(DlnaSearcher.isLanInterfaceName('wlan0'), isTrue);
    for (final name in ['pdp_ip0', 'utun3', 'ipsec0', 'awdl0', 'llw0']) {
      expect(DlnaSearcher.isLanInterfaceName(name), isFalse, reason: name);
    }
  });

  test('unicast search request names the target host', () {
    final text = utf8.decode(
      DlnaSearcher.searchRequest('ssdp:all', host: '192.168.1.5:1900'),
    );
    expect(text, startsWith('M-SEARCH * HTTP/1.1\r\n'));
    expect(text, contains('HOST: 192.168.1.5:1900\r\n'));
    expect(text, contains('MAN: "ssdp:discover"\r\n'));
    expect(text, endsWith('\r\n\r\n'));
  });
}
