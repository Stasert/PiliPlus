import 'dart:async';

/// A page command rendered by the system's vertical toolbar.
class NativePageAction {
  const NativePageAction({
    required this.id,
    required this.title,
    this.count,
    this.selected = false,
    this.enabled = true,
    this.badge,
    this.selectedColor,
    this.standalone = false,
    this.symbol,
    this.image,
    this.group,
  });

  final String id;
  final String title;
  final String? count;
  final bool selected;
  final bool enabled;
  final String? badge;
  final int? selectedColor;
  final bool standalone;
  final String? symbol;
  final String? image;
  final String? group;

  Map<String, Object> toMap() => {
    'id': id,
    'title': title,
    'count': ?count,
    'selected': selected,
    'enabled': enabled,
    'badge': ?badge,
    'selectedColor': ?selectedColor,
    if (standalone) 'standalone': true,
    'symbol': ?symbol,
    'image': ?image,
    'group': ?group,
  };
}

/// Player chrome is route-owned, so overlays and stacked videos cannot leak it.
class NativeVideoChrome {
  const NativeVideoChrome({
    required this.controlsVisible,
    required this.fullScreen,
    required this.locked,
    this.frame,
    this.collapsed = false,
    this.paused = false,
  });

  final bool controlsVisible;
  final bool fullScreen;
  final bool locked;
  final Map<String, double>? frame;
  final bool collapsed;
  final bool paused;

  bool get visible => !fullScreen;

  Map<String, Object> toMap() => {
    'controlsVisible': controlsVisible,
    'fullScreen': fullScreen,
    'locked': locked,
    'collapsed': collapsed,
    'paused': paused,
    'frame': ?frame,
  };
}

typedef NativePageActionHandler = FutureOr<void> Function(String id);

class _PageCommands {
  _PageCommands(
    this.token,
    this.actions,
    this.handler,
    this.video,
    this.homeTools,
  );

  final int token;
  final List<NativePageAction> actions;
  final NativePageActionHandler handler;
  final NativeVideoChrome? video;
  final bool homeTools;
}

/// Keeps commands attached to their page, including when details are stacked.
/// Owner tokens reject taps already queued by a previous native toolbar.
class NativePageActionRegistry {
  NativePageActionRegistry({required this.onChanged});

  final void Function(Map<String, Object> state) onChanged;
  final Map<Object, _PageCommands> _pages = {};
  Object? _topPage;
  NativeVideoChrome? _initialVideo;
  int _nextToken = 0;

  void setTopPage(Object? page, {NativeVideoChrome? initialVideo}) {
    _topPage = page;
    _initialVideo = initialVideo;
    _publish();
  }

  void register({
    required Object page,
    required List<NativePageAction> actions,
    required NativePageActionHandler handler,
    NativeVideoChrome? video,
    bool homeTools = false,
  }) {
    final token = _pages[page]?.token ?? ++_nextToken;
    _pages[page] = _PageCommands(
      token,
      List.unmodifiable(actions),
      handler,
      video,
      homeTools,
    );
    if (page == _topPage) _publish();
  }

  void unregister(Object page) {
    _pages.remove(page);
    if (page == _topPage) _publish();
  }

  void _publish() {
    final commands = _pages[_topPage];
    onChanged({
      'owner': commands?.token ?? 0,
      'video': (commands?.video ?? _initialVideo)?.toMap() ?? false,
      'homeTools': commands?.homeTools ?? false,
      'items': [
        for (final action in commands?.actions ?? <NativePageAction>[])
          action.toMap(),
      ],
    });
  }

  Future<void> handle({required int owner, required String id}) async {
    final commands = _pages[_topPage];
    if (commands == null || commands.token != owner) return;
    if (commands.video case final video? when !video.visible) return;
    if (!commands.actions.any((action) => action.id == id && action.enabled)) {
      return;
    }
    await commands.handler(id);
  }
}
