import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'config.dart';

/// Kullanıcı ayarlarını ve tercihlerini C:\MFLab\settings.json dosyasında kalıcı olarak saklar.
class AppSettings {
  AppSettings({
    this.themeMode = ThemeMode.system,
    this.studentName = '',
    this.studentNumber = '',
    this.lastCourseId,
    Map<String, String>? courseInstallDates,
  }) : courseInstallDates = courseInstallDates ?? {};

  ThemeMode themeMode;
  String studentName;
  String studentNumber;
  String? lastCourseId;
  final Map<String, String> courseInstallDates;

  static String get filePath => '${AppConfig.baseDir}\\settings.json';

  static Future<AppSettings> load() async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return AppSettings();
      }
      final str = await file.readAsString();
      final map = jsonDecode(str) as Map<String, dynamic>;

      var mode = ThemeMode.system;
      final modeStr = map['themeMode'] as String?;
      if (modeStr == 'light') mode = ThemeMode.light;
      if (modeStr == 'dark') mode = ThemeMode.dark;

      final dates = <String, String>{};
      if (map['courseInstallDates'] is Map) {
        (map['courseInstallDates'] as Map).forEach((k, v) {
          dates[k.toString()] = v.toString();
        });
      }

      return AppSettings(
        themeMode: mode,
        studentName: (map['studentName'] ?? '') as String,
        studentNumber: (map['studentNumber'] ?? '') as String,
        lastCourseId: map['lastCourseId'] as String?,
        courseInstallDates: dates,
      );
    } catch (_) {
      return AppSettings();
    }
  }

  Future<void> save() async {
    try {
      final dir = Directory(AppConfig.baseDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File(filePath);
      final modeStr = switch (themeMode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

      final data = {
        'themeMode': modeStr,
        'studentName': studentName,
        'studentNumber': studentNumber,
        'lastCourseId': lastCourseId,
        'courseInstallDates': courseInstallDates,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    } catch (_) {}
  }
}
