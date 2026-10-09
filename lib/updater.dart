import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'config.dart';

/// Yeni sürümü GitHub Releases'tan indirir, SHA-256 ile doğrular ve sessizce kurar.
/// Uygulama içinden indirilen dosya "internetten indirildi" işareti taşımadığı için
/// Windows SmartScreen uyarısı da çıkmaz.
class Updater {
  static String setupName(String version) => 'MFLab-Setup-v$version.exe';

  static String downloadUrl(String version) =>
      '${AppConfig.repoUrl}/releases/download/v$version/${setupName(version)}';

  static String checksumUrl(String version) => '${downloadUrl(version)}.sha256';

  /// `<hash>  <dosya>` biçimindeki .sha256 içeriğinden özeti çıkarır.
  static String? parseChecksum(String text) {
    final m = RegExp(r'\b([a-fA-F0-9]{64})\b').firstMatch(text);
    return m?.group(1)?.toLowerCase();
  }

  static Future<String> _getText(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      return await res.transform(const SystemEncoding().decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  /// Kurulum dosyasını geçici klasöre indirir. [onProgress] 0..1 arası ilerleme verir.
  static Future<File> download(String version,
      {void Function(double progress)? onProgress}) async {
    final target = File('${Directory.systemTemp.path}\\${setupName(version)}');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(downloadUrl(version)));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('Kurulum dosyası indirilemedi (HTTP ${res.statusCode}).');
      }
      final total = res.contentLength;
      var received = 0;
      final sink = target.openWrite();
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
      return target;
    } finally {
      client.close(force: true);
    }
  }

  /// Dosyanın SHA-256 özeti. PowerShell'e bağlı değil: bazı bilgisayarlarda (PowerShell 7 kurulu
  /// olanlar, GitHub Actions) Windows PowerShell'in Get-FileHash komutu boş dönebiliyor.
  static Future<String?> sha256Of(File f) async {
    try {
      final digest = await sha256.bind(f.openRead()).first;
      return digest.toString();
    } catch (_) {
      return null;
    }
  }

  /// GitHub'daki beklenen özet ile indirilen dosyanın gerçek özeti.
  static Future<(String?, String?)> hashes(String version, File f) async {
    final expected = parseChecksum(await _getText(checksumUrl(version)));
    final actual = await sha256Of(f);
    return (expected, actual);
  }

  /// İndirilen dosyanın GitHub'daki .sha256 ile aynı olduğunu doğrular.
  static Future<bool> verify(String version, File f) async {
    final (expected, actual) = await hashes(version, f);
    return expected != null && actual != null && expected == actual;
  }

  /// Kurulumu sessizce başlatır ve uygulamayı kapatır; kurulum bitince MF Lab yeniden açılır.
  static Future<void> runInstallerAndQuit(File setup) async {
    await Process.start(
        setup.path, ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
        mode: ProcessStartMode.detached);
    try {
      await const MethodChannel('mflab/tray').invokeMethod('quit');
    } catch (_) {
      exit(0);
    }
  }
}
