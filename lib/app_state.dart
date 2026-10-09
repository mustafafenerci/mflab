import 'dart:io';

import 'package:flutter/material.dart';
import 'config.dart';

import 'engine.dart';
import 'models.dart';
import 'settings.dart';

/// Uygulamanın ortak durumu: katalog, ayarlar, kurulum günlüğü, güncelleme bilgisi.
class AppState extends ChangeNotifier {
  Catalog? catalog;
  UpdateInfo? update;
  bool updateDismissed = false;
  bool checkedUpdate = false;

  AppSettings settings = AppSettings();

  ThemeMode get themeMode => settings.themeMode;
  String get studentName => settings.studentName;
  String get studentNumber => settings.studentNumber;
  String? get lastCourseId => settings.lastCourseId;

  void cycleTheme() {
    if (settings.themeMode == ThemeMode.system) {
      settings.themeMode = ThemeMode.light;
    } else if (settings.themeMode == ThemeMode.light) {
      settings.themeMode = ThemeMode.dark;
    } else {
      settings.themeMode = ThemeMode.system;
    }
    settings.save();
    notifyListeners();
  }

  void setStudentInfo(String name, String number) {
    settings.studentName = name;
    settings.studentNumber = number;
    settings.save();
    notifyListeners();
  }

  void setLastCourse(String courseId) {
    if (settings.lastCourseId != courseId) {
      settings.lastCourseId = courseId;
      settings.save();
    }
  }

  final logs = <String>[];
  bool busy = false;
  HelpEntry? lastHelp;
  Course? finishedCourse;
  bool installFailed = false;
  String? currentCourseName;
  bool logVisible = false;

  Future<void> init() async {
    settings = await AppSettings.load();
    await Engine.loadPortMaps();
    await Engine.refreshPath();
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
    installFailed = false;
    notifyListeners();
  }

  /// Yapay zekâ asistanına yapıştırılacak, Türkçe ve kendi kendine yeten sorun özeti.
  String buildAiPrompt() {
    final tail = logs.length > 150 ? logs.sublist(logs.length - 150) : logs;
    return '''Ben bir üniversite öğrencisiyim ve ders ortamımı "${AppConfig.appName}" (sürüm ${AppConfig.appVersion}) uygulamasıyla Docker üzerinden kurmaya çalışıyorum.
Ders: ${currentCourseName ?? '-'}
İşletim sistemi: ${Platform.operatingSystemVersion}

Kurulum başarısız oldu veya hata verdi. Aşağıdaki kurulum günlüğüne bakıp:
1. Sorunun ne olduğunu basit bir Türkçe ile anlat,
2. Windows'ta adım adım nasıl çözeceğimi söyle,
3. Çözümden sonra uygulamada tekrar "Kur"a basmam yeterli mi, belirt.

--- Kurulum günlüğü ---
${tail.join('\n')}
--- Günlük sonu ---''';
  }

  void hideLog() {
    logVisible = false;
    notifyListeners();
  }

  void _begin() {
    busy = true;
    logs.clear();
    lastHelp = null;
    installFailed = false;
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
    currentCourseName = course.name;
    try {
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
        settings.courseInstallDates[course.id] = DateTime.now().toIso8601String();
        settings.save();
        log('\n🎉 Hazır! Ders ortamın kuruldu.');
      } else {
        installFailed = true;
        log('\nBazı adımlar tamamlanmadı. Yukarıdaki açıklamaları oku, sorunu giderip tekrar "Kur"a bas.');
      }
    } catch (e) {
      installFailed = true;
      log('\n✖ Beklenmeyen bir hata oluştu: $e');
    } finally {
      _end();
    }
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
