import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'app_state.dart';
import 'config.dart';
import 'engine.dart';
import 'models.dart';

/// Saatin yanındaki (bildirim alanı) MF Lab simgesi.
/// Sağ tıklayınca kurulu servisleri, durumlarını ve hızlı işlemleri gösterir.
/// Simge ve menü Windows tarafında (windows/runner/flutter_window.cpp) çizilir.
class TrayService {
  TrayService(this.state);
  final AppState state;

  static const _channel = MethodChannel('mflab/tray');

  final Map<int, Future<void> Function()> _actions = {};
  Timer? _timer;
  bool _ready = false;
  bool _refreshing = false;
  bool _lastBusy = false;
  bool _hadCatalog = false;

  Future<void> init() async {
    if (!Platform.isWindows) return;
    _channel.setMethodCallHandler(_onCall);
    try {
      _ready = (await _channel.invokeMethod<bool>('init', {
            'tooltip': '${AppConfig.appName} v${AppConfig.appVersion}',
          })) ??
          false;
    } on MissingPluginException {
      return;
    }
    if (!_ready) return;
    state.addListener(_onState);
    _timer = Timer.periodic(const Duration(seconds: 12), (_) => refresh());
    await refresh();
  }

  void dispose() {
    _timer?.cancel();
    state.removeListener(_onState);
  }

  /// Katalog yüklenince ve her işlem (başlat/durdur/kur) bitince menüyü yeniler.
  void _onState() {
    final loaded = state.catalog != null;
    final finished = _lastBusy && !state.busy;
    final first = loaded && !_hadCatalog;
    _lastBusy = state.busy;
    _hadCatalog = loaded;
    if (finished || first) refresh();
  }

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'menuClick':
        final action = _actions[call.arguments as int];
        if (action != null) await action();
      case 'beforeMenu':
        unawaited(refresh());
    }
  }

  // ------------------------------------------------------------------ menü

  Future<void> refresh() async {
    final cat = state.catalog;
    if (!_ready || cat == null || _refreshing) return;
    _refreshing = true;
    try {
      final dockerUp = await Engine.dockerRunning();
      final services = <_Svc>[];
      for (final c in cat.courses) {
        for (final id in c.packages) {
          final p = cat.packages[id];
          if (p == null || !p.isDocker) continue;
          if (!await Engine.isInstalled(c, p)) continue;
          services.add(_Svc(c, p, dockerUp && await Engine.isRunning(c, p)));
        }
      }
      await _publish(services);
    } catch (_) {
      // Tepsi menüsü yenilenemezse sessizce eski menüyle devam et.
    } finally {
      _refreshing = false;
    }
  }

  int _nextId = 1;

  Map<String, Object> _item(String label, Future<void> Function()? onTap,
      {bool enabled = true}) {
    final id = _nextId++;
    if (onTap != null) _actions[id] = onTap;
    return {'type': 'item', 'id': id, 'label': label, 'enabled': enabled && onTap != null};
  }

  Map<String, Object> _sep() => {'type': 'sep'};

  /// Uzun süren işlemleri günlük panelinde gösterecek şekilde çalıştırır.
  Future<void> _task(Future<void> Function() job) async {
    if (state.busy) return;
    state.logs.clear();
    await state.runTask(job);
  }

  Future<void> _publish(List<_Svc> services) async {
    _actions.clear();
    _nextId = 1;
    final running = services.where((s) => s.running).toList();

    final menu = <Map<String, Object>>[
      _item('${AppConfig.appName} v${AppConfig.appVersion}', null, enabled: false),
      _sep(),
    ];

    if (services.isEmpty) {
      menu.add(_item('Kurulu servis yok', null, enabled: false));
    }
    for (final s in services) {
      final c = s.course;
      final p = s.pkg;
      final children = <Map<String, Object>>[
        if (!s.running)
          _item('▶  Başlat', () => _task(() => Engine.start(c, p, state.log)))
        else
          _item('■  Durdur', () => _task(() => Engine.stop(c, p, state.log))),
        _sep(),
        if (s.running)
          for (final l in p.links)
            _item('${l.name} sayfasını aç',
                () => Engine.openUrl(Engine.mapText(c.id, p.id, l.url))),
        _item('VS Code\'da aç',
            () => Engine.openInVsCode(Engine.workspaceDir(c))),
        _item('Çalışma klasörünü aç',
            () => Engine.openFolder(Engine.workspaceDir(c))),
        if (s.running)
          _item('Terminal aç', () => Engine.openContainerTerminal(c, p)),
      ];
      menu.add({
        'type': 'submenu',
        'label': '${s.running ? '●' : '○'}  ${c.name} — ${s.running ? 'Çalışıyor' : 'Durdu'}',
        'enabled': true,
        'children': children,
      });
    }

    menu
      ..add(_sep())
      ..add(_item('Hepsini durdur (${running.length})', running.isEmpty
          ? null
          : () => _task(() async {
                for (final s in running) {
                  await Engine.stop(s.course, s.pkg, state.log);
                }
              })))
      ..add(_item('MF Lab\'ı aç', () => _channel.invokeMethod('show')))
      ..add(_sep())
      ..add(_item('Çıkış (servisler çalışmaya devam eder)',
          () => _channel.invokeMethod('quit')));

    await _channel.invokeMethod('setMenu', menu);
    await _channel.invokeMethod('setCloseToTray', {'value': running.isNotEmpty});
    await _channel.invokeMethod('setTooltip', {
      'text': running.isEmpty
          ? '${AppConfig.appName} — çalışan servis yok'
          : '${AppConfig.appName} — ${running.length} servis çalışıyor',
    });
  }
}

class _Svc {
  _Svc(this.course, this.pkg, this.running);
  final Course course;
  final LabPackage pkg;
  final bool running;
}
