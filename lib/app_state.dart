import 'package:flutter/foundation.dart';

import 'engine.dart';
import 'models.dart';

/// Uygulamanın ortak durumu: katalog, kurulum günlüğü, güncelleme bilgisi.
class AppState extends ChangeNotifier {
  Catalog? catalog;
  UpdateInfo? update;
  bool updateDismissed = false;
  bool checkedUpdate = false;

  final logs = <String>[];
  bool busy = false;
  HelpEntry? lastHelp;
  Course? finishedCourse;
  bool logVisible = false;

  Future<void> init() async {
    catalog = await Catalog.load();
    notifyListeners();
    await checkUpdate();
  }

  Future<void> checkUpdate() async {
    update = await Engine.checkUpdate();
    updateDismissed = false;
    checkedUpdate = true;
    notifyListeners();
  }

  void dismissUpdate() {
    updateDismissed = true;
    notifyListeners();
  }

  void log(String m) {
    logs.add(m);
    logVisible = true;
    notifyListeners();
  }

  void clearLog() {
    logs.clear();
    logVisible = false;
    lastHelp = null;
    notifyListeners();
  }

  void hideLog() {
    logVisible = false;
    notifyListeners();
  }

  void _begin() {
    busy = true;
    logs.clear();
    lastHelp = null;
    finishedCourse = null;
    logVisible = true;
    notifyListeners();
  }

  void _end() {
    busy = false;
    notifyListeners();
  }

  /// Seçilen paketleri sırayla kurar: önce araçlar, sonra Docker paketleri.
  Future<void> install(Course course, Set<String> selected) async {
    final cat = catalog!;
    _begin();
    final pkgs = selected
        .map((id) => cat.packages[id])
        .whereType<LabPackage>()
        .toList()
      ..sort((a, b) => (a.isDocker ? 1 : 0).compareTo(b.isDocker ? 1 : 0));

    var dockerOk = true;
    var vscodeOk = false;
    var allOk = true;

    for (final p in pkgs) {
      log('\n=== ${p.name} ===');
      log('Neden kuruyoruz? ${p.why}');
      for (final s in p.steps) {
        log('• $s');
      }
      if (p.isDocker) {
        if (!dockerOk) {
          log('Docker kurulu olmadığı için bu paket atlandı.');
          allOk = false;
          continue;
        }
        final r = await Engine.installDocker(cat, course, p, log);
        if (!r.ok) {
          allOk = false;
          lastHelp = r.help;
          break;
        }
      } else {
        final ok = await Engine.ensureTool(p, log);
        if (p.id == 'docker' && !ok) dockerOk = false;
        if (p.id == 'vscode') vscodeOk = ok;
        if (!ok) allOk = false;
      }
    }

    if (vscodeOk) await Engine.installExtensions(course.extensions, log);

    final done = pkgs.where((p) => !p.isDocker || dockerOk).toList();
    if (allOk || done.any((p) => p.isDocker)) {
      await Engine.createShortcuts(course, done, log);
    }

    if (allOk) {
      finishedCourse = course;
      log('\n🎉 Hazır! Ders ortamın kuruldu.');
    } else {
      log('\nBazı adımlar tamamlanmadı. Yukarıdaki açıklamaları oku, sorunu giderip tekrar "Kur"a bas.');
    }
    _end();
  }

  Future<void> runTask(Future<void> Function() task) async {
    busy = true;
    notifyListeners();
    try {
      await task();
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
