import 'package:PiliPlus/utils/ios/native_tab_bar.dart';

import 'dart:async';
import 'dart:io' show Platform;

import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/loading_widget/loading_widget.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/dlna_searcher.dart';
import 'package:PiliPlus/utils/dlna_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/ios/airplay_helper.dart';
import 'package:PiliPlus/utils/permission_handler.dart';
import 'package:dlna_dart/dlna.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class DLNAPage extends StatefulWidget {
  const DLNAPage({super.key});

  @override
  State<DLNAPage> createState() => _DLNAPageState();
}

class _DLNAPageState extends State<DLNAPage> {
  final _searcher = DlnaSearcher();
  final Map<String, DLNADevice> _deviceList = {};
  late final _url = Get.parameters['url']!;
  late final _title = Get.parameters['title'];

  Timer? _timer;
  bool _isSearching = false;
  PermissionStatus? _permissionStatus;
  String? _searchError;
  DLNADevice? _lastDevice;
  String? _lastDeviceKey;

  @override
  void initState() {
    super.initState();
    _onSearch(isInit: true);
    // An AirPlay cast keeps running after leaving this page, like DLNA.
    if (Platform.isIOS) AirPlayHelper.refresh();
  }

  Future<void> _onSearch({bool isInit = false}) async {
    if (_isSearching) return;
    _isSearching = true;
    _permissionStatus = null;
    _searchError = null;
    if (!isInit && mounted) {
      _lastDevice = null;
      _deviceList.clear();
      setState(() {});
    }
    try {
      // PiliPlus targets API 37; older systems do not require this permission.
      if (Platform.isAndroid && DeviceUtils.sdkInt >= 37) {
        final status = await Permission.accessLocalNetwork.request();
        if (!mounted) return;
        _permissionStatus = status;
        if (!status.isGranted) return;
      }
      final deviceManager = await _searcher.start();
      if (!mounted) return;
      _timer = Timer(const Duration(seconds: 20), _searcher.stop);
      await for (final deviceList in deviceManager.devices.stream) {
        if (mounted) {
          _deviceList.addAll(deviceList);
          setState(() {});
        }
      }
    } catch (e) {
      _searchError = '搜索设备失败，请检查网络后重试\n$e';
    } finally {
      _timer?.cancel();
      _timer = null;
      _searcher.stop();
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _searcher.stop();
    _lastDevice = null;
    _lastDeviceKey = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return SimpleScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !IOSNativeTabBar.hasNativeBack(context),
        title: const Text('投屏'),
        actions: [
          IconButton(
            tooltip: '搜索',
            onPressed: _onSearch,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Only the last sliver gets ViewSliverSafeArea's bottom padding.
          if (Platform.isIOS)
            SliverSafeArea(top: false, bottom: false, sliver: _buildAirPlay()),
          if (_isSearching) linearLoading,
          ViewSliverSafeArea(sliver: _buildBody(colorScheme)),
        ],
      ),
    );
  }

  /// AirPlay sits above the DLNA devices: the system lists AirPlay devices
  /// itself, so there is nothing to search for here.
  Widget _buildAirPlay() {
    return SliverToBoxAdapter(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder(
            valueListenable: AirPlayHelper.state,
            builder: (context, state, _) => state == null
                ? ListTile(
                    leading: const Icon(Icons.airplay),
                    title: const Text('AirPlay'),
                    subtitle: const Text('Apple TV、Mac 或支持 AirPlay 的电视'),
                    onTap: _startAirPlay,
                  )
                : _AirPlayPanel(state: state),
          ),
          const Divider(height: 1),
          const ListTile(dense: true, title: Text('局域网投屏（DLNA）')),
        ],
      ),
    );
  }

  void _startAirPlay() {
    final position =
        PlPlayerController.instance?.currentPosition ?? Duration.zero;
    _lastDevice?.pause();
    PlPlayerController.pauseIfExists();
    AirPlayHelper.start(url: _url, title: _title, start: position);
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (!_isSearching && _deviceList.isEmpty) {
      if (_permissionStatus case final status? when !status.isGranted) {
        final permanentlyDenied = status.isPermanentlyDenied;
        return HttpError(
          errMsg: permanentlyDenied
              ? '局域网权限未授权，请在系统设置中允许附近的设备，返回后点击搜索'
              : '需要局域网权限才能搜索投屏设备',
          btnText: permanentlyDenied ? '前往设置' : '授予权限',
          onReload: permanentlyDenied ? openAppSettings : _onSearch,
        );
      }
      final lastError = _searcher.lastError;
      return HttpError(
        errMsg:
            _searchError ??
            (_searcher.noLan
                ? '没有设备\n没有找到局域网连接，请连接和电视相同的 Wi-Fi'
                : lastError == null
                ? '没有设备'
                : '没有设备\n搜索时出错：$lastError'),
        onReload: _onSearch,
      );
    }
    if (_deviceList.isNotEmpty) {
      final keys = _deviceList.keys.toList();
      return SliverList.builder(
        itemCount: keys.length,
        itemBuilder: (context, index) {
          final key = keys[index];
          final device = _deviceList[key]!;
          final isCurr = key == _lastDeviceKey;
          return ListTile(
            title: Text(
              device.info.friendlyName,
              style: isCurr ? TextStyle(color: colorScheme.primary) : null,
            ),
            subtitle: Text(key),
            onTap: () async {
              if (isCurr) return;
              normalizeLegacyDlnaControlUrls(device);
              _lastDevice?.pause();
              _lastDevice = device;
              _lastDeviceKey = key;
              setState(() {});
              await device.setUrl(_url, title: _title ?? '');
              await device.play();
            },
          );
        },
      );
    }
    return const SliverToBoxAdapter();
  }
}

/// Remote control for the running AirPlay cast.
class _AirPlayPanel extends StatefulWidget {
  const _AirPlayPanel({required this.state});

  final AirPlayState state;

  @override
  State<_AirPlayPanel> createState() => _AirPlayPanelState();
}

class _AirPlayPanelState extends State<_AirPlayPanel> {
  /// Slider value while dragging, in seconds.
  double? _dragging;

  static String _format(Duration d) =>
      DurationUtils.formatDuration(d.inSeconds);

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final colorScheme = ColorScheme.of(context);
    final total = state.duration.inSeconds.toDouble();
    final position = _dragging ?? state.position.inSeconds.toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Icon(Icons.airplay, color: colorScheme.primary),
          title: Text(
            state.connected
                ? '正在投放到 ${state.device ?? 'AirPlay 设备'}'
                : '请选择 AirPlay 设备',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colorScheme.primary),
          ),
          subtitle: state.error != null
              ? Text('播放失败：${state.error}')
              : state.title == null
              ? null
              : Text(
                  state.title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: TextButton(
            onPressed: AirPlayHelper.stop,
            child: Text(state.connected ? '停止投屏' : '取消'),
          ),
        ),
        if (state.connected)
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 16, bottom: 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: state.playing ? '暂停' : '播放',
                  onPressed: state.playing
                      ? AirPlayHelper.pause
                      : AirPlayHelper.play,
                  icon: Icon(
                    state.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: total > 0 ? position.clamp(0, total) : 0,
                    max: total > 0 ? total : 1,
                    onChanged: total > 0
                        ? (value) => setState(() => _dragging = value)
                        : null,
                    onChangeEnd: (value) {
                      AirPlayHelper.seek(Duration(seconds: value.round()));
                      setState(() => _dragging = null);
                    },
                  ),
                ),
                Text(
                  '${_format(Duration(seconds: position.round()))} / '
                  '${_format(state.duration)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.outline,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
