import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'config.dart';
import 'models.dart';

typedef Log = void Function(String);

class InstallResult {
  InstallResult(this.ok, {this.help});
  final bool ok;
  final HelpEntry? help;
}

class Engine {
  static String courseDir(Course c) => '${AppConfig.baseDir}\\${c.id}';
  static String workspaceDir(Course c) =>
      '${courseDir(c)}\\${c.workspaceName}';
  static String stackDir(Course c, LabPackage p) =>
      '${courseDir(c)}\\.stack\\${p.id}';

  // ---------------------------------------------------------------- process

  static Future<ProcessResult> run(String cmd, List<String> args,
      {String? cwd}) {
    return Process.run(cmd, args,
        workingDirectory: cwd,
        runInShell: true,
        stdoutEncoding: systemEncoding,
        stderrEncoding: systemEncoding);
  }

  /// Komutu çalıştırır, çıktıyı canlı olarak [log]'a akıtır ve tüm çıktıyı döner.
  static Future<(int, String)> stream(String cmd, List<String> args,
      {String? cwd, required Log log}) async {
    final buf = StringBuffer();
    final proc = await Process.start(cmd, args,
        workingDirectory: cwd, runInShell: true);
    final done = <Future<void>>[];
    for (final s in [proc.stdout, proc.stderr]) {
      final c = Completer<void>();
      done.add(c.future);
      s.transform(systemEncoding.decoder).listen((d) {
        buf.write(d);
        final t = d.trim();
        if (t.isNotEmpty) log(t);
      }, onDone: c.complete, onError: (_) => c.complete());
    }
    await Future.wait(done);
    final code = await proc.exitCode;
    return (code, buf.toString());
  }

  static Future<bool> commandOk(String command) async {
    try {
      final parts = command.split(' ');
      final r = await run(parts.first, parts.skip(1).toList());
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> dockerInstalled() => commandOk('docker --version');
  static Future<bool> dockerRunning() => commandOk('docker info');

  static Future<void> openUrl(String url) async {
    await run('cmd', ['/c', 'start', '', url]);
  }

  static Future<void> openFolder(String path) async {
    await Directory(path).create(recursive: true);
    await Process.start('explorer', [path], runInShell: true);
  }

  static Future<void> openInVsCode(String path) async {
    await Directory(path).create(recursive: true);
    await run('code', [path]);
  }

  static String _q(String s) => '"$s"';

  // -------------------------------------------------------------- help/errs

  static HelpEntry? helpFor(Catalog cat, String output) {
    final low = output.toLowerCase();
    for (final h in cat.help) {
      if (h.match.any((m) => low.contains(m.toLowerCase()))) return h;
    }
    return null;
  }

  // ------------------------------------------------------------------ tools

  static Future<bool> ensureTool(LabPackage p, Log log) async {
    log('${p.name} kontrol ediliyor...');
    if (await commandOk(p.check!)) {
      log('✔ ${p.name} kurulu.');
      return true;
    }
    log('✖ ${p.name} bulunamadı. İndirme sayfası açılıyor: ${p.downloadUrl}');
    log('Kurulumu bitirdikten sonra bu uygulamada "Kur" düğmesine tekrar bas.');
    await openUrl(p.downloadUrl!);
    return false;
  }

  static Future<void> installExtensions(List<String> ids, Log log) async {
    if (ids.isEmpty) return;
    if (!await commandOk('code --version')) {
      log('VS Code komutu bulunamadı, eklentiler atlandı.');
      return;
    }
    log('VS Code eklentileri kuruluyor...');
    for (final e in ids) {
      final r = await run('code', ['--install-extension', e, '--force']);
      log(r.exitCode == 0 ? '  ✔ $e' : '  ✖ $e kurulamadı');
    }
  }

  // ----------------------------------------------------------------- docker

  static Future<InstallResult> installDocker(
      Catalog cat, Course course, LabPackage p, Log log) async {
    if (!await dockerInstalled()) {
      log('✖ Docker bulunamadı. Önce Docker Desktop kurulmalı.');
      return InstallResult(false);
    }
    if (!await dockerRunning()) {
      log('Docker çalışmıyor, Docker Desktop başlatılmaya çalışılıyor...');
      await _tryStartDockerDesktop();
      var ok = false;
      for (var i = 0; i < 24 && !ok; i++) {
        await Future.delayed(const Duration(seconds: 5));
        ok = await dockerRunning();
        if (!ok) log('Docker bekleniyor... (${(i + 1) * 5} sn)');
      }
      if (!ok) {
        log('✖ Docker başlamadı.');
        return InstallResult(false,
            help: helpFor(cat, 'error during connect docker daemon'));
      }
    }

    final stack = stackDir(course, p);
    final ws = workspaceDir(course);
    await Directory(stack).create(recursive: true);
    await Directory(ws).create(recursive: true);

    await File('$stack\\compose.yml')
        .writeAsString(await rootBundle.loadString(p.compose!));
    await File('$stack\\.env')
        .writeAsString('WORKSPACE=${ws.replaceAll('\\', '/')}\n');
    if (p.buildContext != null) {
      final dir = Directory('$stack\\php-web');
      await dir.create(recursive: true);
      await File('${dir.path}\\Dockerfile')
          .writeAsString(await rootBundle.loadString(p.buildContext!));
    }
    await _seedWorkspace(course, ws);

    log('Konteynerler indiriliyor ve başlatılıyor (ilk seferde birkaç dakika sürebilir)...');
    var (code, out) =
        await stream('docker', ['compose', 'up', '-d'], cwd: stack, log: log);
    if (code != 0 && p.buildContext != null) {
      log('Hazır imaj indirilemedi, imaj bu bilgisayarda derleniyor (5-10 dk sürebilir)...');
      (code, out) = await stream(
          'docker', ['compose', 'up', '-d', '--build'],
          cwd: stack, log: log);
    }
    if (code != 0) {
      log('✖ Kurulum başarısız (kod $code).');
      return InstallResult(false, help: helpFor(cat, out));
    }
    log('✔ ${p.name} hazır.');
    log(p.info);
    return InstallResult(true);
  }

  static Future<void> _tryStartDockerDesktop() async {
    final candidates = [
      r'C:\Program Files\Docker\Docker\Docker Desktop.exe',
      '${Platform.environment['LOCALAPPDATA']}\\Programs\\Docker\\Docker\\Docker Desktop.exe',
    ];
    for (final c in candidates) {
      if (await File(c).exists()) {
        await Process.start(c, [], mode: ProcessStartMode.detached);
        return;
      }
    }
  }

  static Future<void> _seedWorkspace(Course c, String ws) async {
    if (c.workspaceName == 'htdocs') {
      final f = File('$ws\\index.php');
      if (!await f.exists() && (await Directory(ws).list().isEmpty)) {
        await f.writeAsString('<?php\n'
            'echo "<h1>MF Lab çalışıyor!</h1>";\n'
            'echo "<p>PHP sürümü: " . phpversion() . "</p>";\n'
            r'try { $pdo = new PDO("mysql:host=db;dbname=mflab", "root", "root"); '
            'echo "<p>MariaDB bağlantısı: başarılı ✔</p>"; } '
            'catch (Exception \$e) { echo "<p>MariaDB bağlantısı: " . \$e->getMessage() . "</p>"; }\n');
      }
    } else if (c.workspaceName == 'proje') {
      final f = File('$ws\\index.html');
      if (!await f.exists() && (await Directory(ws).list().isEmpty)) {
        await f.writeAsString('<!DOCTYPE html>\n<html lang="tr">\n<head>\n'
            '  <meta charset="UTF-8">\n  <title>İlk Sayfam</title>\n</head>\n'
            '<body>\n  <h1>Merhaba MF Lab!</h1>\n</body>\n</html>\n');
      }
    }
  }

  static Future<bool> isRunning(Course c, LabPackage p) async {
    final dir = stackDir(c, p);
    if (!await File('$dir\\compose.yml').exists()) return false;
    final r = await run('docker', ['compose', 'ps', '--status', 'running', '-q'],
        cwd: dir);
    return r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty;
  }

  static Future<bool> isInstalled(Course c, LabPackage p) async =>
      File('${stackDir(c, p)}\\compose.yml').exists();

  static Future<void> start(Course c, LabPackage p, Log log) async {
    await stream('docker', ['compose', 'up', '-d'],
        cwd: stackDir(c, p), log: log);
  }

  static Future<void> stop(Course c, LabPackage p, Log log) async {
    await stream('docker', ['compose', 'stop'], cwd: stackDir(c, p), log: log);
  }

  /// Konteyner loglarını (son 60 satır) ekrana akıtır.
  static Future<void> showLogs(Course c, LabPackage p, Log log) async {
    log('\n=== ${p.name} Son Loglar ===');
    await stream('docker', ['compose', 'logs', '--tail', '60'],
        cwd: stackDir(c, p), log: log);
  }

  /// Öğrencinin sistem durumunu (Docker, WSL, RAM, Disk, Araçlar) tarar.
  static Future<void> diagnoseSystem(Log log) async {
    log('\n=== 🔍 MF Lab Sistem & Donanım Tanısı ===');

    // 1. Docker
    final dInst = await dockerInstalled();
    final dRun = await dockerRunning();
    log(dRun
        ? '✔ Docker: Çalışıyor (Engine hazır)'
        : dInst
            ? '⚠️ Docker: Kurulu fakat şu an ÇALIŞMIYOR. Docker Desktop\'ı açmalısın.'
            : '✖ Docker: Kurulu DEĞİL.');

    // 2. WSL
    final wsl = await commandOk('wsl --status');
    log(wsl ? '✔ WSL: Hazır ve aktif' : '⚠️ WSL: Bilgi alınamadı (Windows Home için WSL2 gerekebilir).');

    // 3. VS Code & Git
    final code = await commandOk('code --version');
    log(code ? '✔ VS Code: Kurulu' : 'ℹ VS Code: Bulunamadı (Web tasarımı / kodlama için önerilir).');
    final git = await commandOk('git --version');
    log(git ? '✔ Git: Kurulu' : 'ℹ Git: Bulunamadı (Laravel/Composer için önerilir).');

    // 4. Disk & RAM
    try {
      final r = await run('powershell', [
        '-NoProfile',
        '-Command',
        r"$c = Get-PSDrive C; $free = [math]::Round($c.Free / 1GB, 1); "
        r"$mem = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1); "
        r"Write-Output ('RAM: ' + $mem + ' GB | C: Bos Alan: ' + $free + ' GB')"
      ]);
      if (r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty) {
        log('✔ Donanım: ${(r.stdout as String).trim()}');
      }
    } catch (_) {}

    log('===========================================\n'
        'İpucu: Sorun yaşarsan yukarıdaki metni sağ üstteki "Kopyala" butonuyla hocana iletebilirsin.');
  }

  /// Konteynerleri siler; [removeVolumes] true ise veritabanı verileri de silinir.
  static Future<void> remove(Course c, LabPackage p, Log log,
      {bool removeVolumes = false}) async {
    final args = ['compose', 'down'];
    if (removeVolumes) args.add('-v');
    await stream('docker', args, cwd: stackDir(c, p), log: log);
  }

  /// Masaüstündeki `MF Lab - ders adı` kısayol klasörünü siler.
  static Future<void> removeDesktopShortcuts(Course course, Log log) async {
    final sb = StringBuffer()
      ..writeln(r"$desktop = [Environment]::GetFolderPath('Desktop')")
      ..writeln(
          "\$dir = Join-Path \$desktop '${_ps('MF Lab - ${course.name}')}'")
      ..writeln(r'if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }');

    final tmp = File('${Directory.systemTemp.path}\\mflab_rm_shortcuts.ps1');
    await tmp.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(sb.toString())]);
    final r = await run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      tmp.path
    ]);
    if (r.exitCode == 0) {
      log('✔ Masaüstündeki "${course.name}" kısayolları temizlendi.');
    }
  }

  /// Ders bittiğinde ortamı temizler / kaldırır.
  static Future<void> uninstallCourse({
    required Catalog catalog,
    required Course course,
    required bool removeVolumes,
    required bool removeWorkspace,
    required bool removeShortcuts,
    required Log log,
  }) async {
    log('\n=== ${course.name} Ortamı Temizleniyor ===');
    for (final id in course.packages) {
      final p = catalog.packages[id];
      if (p != null && p.isDocker) {
        log('${p.name} konteynerleri durdurulup kaldırılıyor...');
        await remove(course, p, log, removeVolumes: removeVolumes);
        final stack = Directory(stackDir(course, p));
        if (await stack.exists()) {
          try {
            await stack.delete(recursive: true);
          } catch (_) {}
        }
      }
    }

    if (removeShortcuts) {
      await removeDesktopShortcuts(course, log);
    }

    if (removeWorkspace) {
      final ws = Directory(workspaceDir(course));
      if (await ws.exists()) {
        log('Çalışma klasörün siliniyor: ${ws.path}');
        try {
          await ws.delete(recursive: true);
          log('✔ Kod klasörü temizlendi.');
        } catch (e) {
          log('✖ Kod klasörü silinemedi: $e');
        }
      }
    } else {
      log('ℹ Kodların korundu: ${workspaceDir(course)}');
    }

    final cDir = Directory(courseDir(course));
    if (await cDir.exists()) {
      try {
        final list = await cDir.list().toList();
        if (list.isEmpty) await cDir.delete();
      } catch (_) {}
    }

    log('🎉 "${course.name}" ortamı başarıyla kaldırıldı / temizlendi.');
  }

  static Future<void> runAction(
      Course c, LabPackage p, PackageAction a, String? name, Log log) async {
    final cmd = a.command.replaceAll('{name}', name ?? '');
    log('Çalıştırılıyor: $cmd');
    final (code, _) = await stream(
        'docker',
        ['compose', 'exec', '-T', a.service, 'sh', '-c', cmd],
        cwd: stackDir(c, p),
        log: log);
    if (code == 0 && a.afterInfo != null) {
      log('✔ ${a.afterInfo!.replaceAll('{name}', name ?? '')}');
    } else if (code != 0) {
      log('✖ İşlem başarısız (kod $code).');
    }
  }

  // -------------------------------------------------------------- shortcuts

  static String _ps(String s) => s.replaceAll("'", "''");

  static Future<String> _ensureIcon() async {
    final path = '${AppConfig.baseDir}\\mflab.ico';
    await Directory(AppConfig.baseDir).create(recursive: true);
    final data = await rootBundle.load('assets/images/app_icon.ico');
    await File(path).writeAsBytes(data.buffer.asUint8List());
    return path;
  }

  /// Masaüstünde `MF Lab - ders adı` klasörü ve içinde kısayollar oluşturur.
  static Future<void> createShortcuts(
      Course course, List<LabPackage> pkgs, Log log) async {
    final icon = await _ensureIcon();
    final ws = workspaceDir(course);
    await Directory(ws).create(recursive: true);
    final hasCode = pkgs.any((p) => p.id == 'vscode');

    final sb = StringBuffer()
      ..writeln(r"$desktop = [Environment]::GetFolderPath('Desktop')")
      ..writeln(
          "\$dir = Join-Path \$desktop '${_ps('MF Lab - ${course.name}')}'")
      ..writeln(r'New-Item -ItemType Directory -Force $dir | Out-Null')
      ..writeln(r'$sh = New-Object -ComObject WScript.Shell')
      ..writeln(r'function Lnk($name, $target, $arguments, $style) {')
      ..writeln(r'  $l = $sh.CreateShortcut((Join-Path $dir ($name + ".lnk")))')
      ..writeln(r'  $l.TargetPath = $target')
      ..writeln(r'  if ($arguments) { $l.Arguments = $arguments }')
      ..writeln(r'  if ($style) { $l.WindowStyle = $style }')
      ..writeln("  \$l.IconLocation = '${_ps(icon)}'")
      ..writeln(r'  $l.Save()')
      ..writeln(r'}')
      ..writeln(
          "Lnk '${_ps(course.workspaceName)} klasörü' '${_ps(ws)}' \$null \$null");
    if (hasCode) {
      sb.writeln(
          "Lnk 'VS Code ile aç' 'cmd.exe' '/c code \"${_ps(ws)}\"' 7");
    }
    for (final p in pkgs) {
      for (final l in p.links) {
        sb.writeln(
            "Set-Content -Path (Join-Path \$dir '${_ps(l.name)}.url') -Value \"[InternetShortcut]`nURL=${_ps(l.url)}`nIconFile=${_ps(icon)}`nIconIndex=0\"");
      }
    }

    final tmp = File('${Directory.systemTemp.path}\\mflab_shortcuts.ps1');
    await tmp.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(sb.toString())]);
    final r = await run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      tmp.path
    ]);
    log(r.exitCode == 0
        ? '✔ Masaüstüne "MF Lab - ${course.name}" klasörü ve kısayollar eklendi.'
        : '✖ Kısayollar oluşturulamadı: ${r.stderr}');
  }

  // ----------------------------------------------------------------- advanced features

  /// Belirtilen portların dolu olup olmadığını yerel olarak test eder.
  static Future<List<int>> findConflictingPorts(List<int> ports) async {
    final conflicts = <int>[];
    for (final port in ports) {
      try {
        final socket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
        await socket.close();
      } catch (_) {
        conflicts.add(port);
      }
    }
    return conflicts;
  }

  /// Konteyner içinde etkileşimli terminal (bash / sh) penceresi açar.
  static Future<void> openContainerTerminal(
      Course course, LabPackage pkg, {String service = 'web'}) async {
    final stack = stackDir(course, pkg);
    final compose = '$stack\\compose.yml';
    final script = 'Write-Host "==============================================" -ForegroundColor Cyan; '
        'Write-Host "  MF Lab: ${pkg.name} - ($service)" -ForegroundColor Yellow; '
        'Write-Host "  Konteyner ici calisma dizini: /var/www/html veya /" -ForegroundColor Gray; '
        'Write-Host "  Cikmak icin: exit yazin" -ForegroundColor Gray; '
        'Write-Host "==============================================" -ForegroundColor Cyan; '
        'docker compose -f "$compose" exec -it $service bash; '
        'if (\$LASTEXITCODE -ne 0) { docker compose -f "$compose" exec -it $service sh }';

    await Process.start('cmd.exe', [
      '/c',
      'start',
      'powershell',
      '-NoExit',
      '-Command',
      script,
    ], runInShell: true);
  }

  /// Windows dosya seçici penceresi açar (OpenFileDialog).
  static Future<String?> pickFile({
    required String title,
    required String filterName,
    required String extension,
  }) async {
    final cmd = 'Add-Type -AssemblyName System.Windows.Forms; '
        '\$f = New-Object System.Windows.Forms.OpenFileDialog; '
        '\$f.Title = "${_ps(title)}"; '
        '\$f.Filter = "${_ps(filterName)} (*.$extension)|*.$extension|Tum Dosyalar (*.*)|*.*"; '
        'if (\$f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output \$f.FileName }';

    final r = await run('powershell', ['-NoProfile', '-Command', cmd]);
    if (r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty) {
      return (r.stdout as String).trim();
    }
    return null;
  }

  /// Veritabanı yedeğini masaüstüne .sql dosyası olarak aktarır.
  static Future<String?> backupDatabase(Course c, LabPackage p, Log log) async {
    final stack = stackDir(c, p);
    final now = DateTime.now();
    final timeStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final fileName = 'mflab_${c.id}_yedek_$timeStr.sql';

    final rDesk = await run('powershell', ['-NoProfile', '-Command', r"[Environment]::GetFolderPath('Desktop')"]);
    final desktop = (rDesk.stdout as String).trim();
    final outPath = '$desktop\\$fileName';

    log('\n=== Veritabanı Yedeği Alınıyor ===');
    log('Hedef dosya: $outPath');

    String dumpCmd;
    if (p.id == 'web2-stack') {
      dumpCmd = 'docker compose -f "$stack\\compose.yml" exec -T db mariadb-dump -uroot -proot --all-databases > "${outPath.replaceAll('\\', '/')}"';
    } else {
      dumpCmd = 'docker compose -f "$stack\\compose.yml" exec -T postgres pg_dumpall -U postgres > "${outPath.replaceAll('\\', '/')}"';
    }

    final r = await run('cmd', ['/c', dumpCmd]);
    if (r.exitCode == 0 && await File(outPath).exists()) {
      log('✔ Veritabanı yedeği masaüstüne kaydedildi: $fileName');
      return outPath;
    } else {
      log('✖ Yedek alınamadı: ${r.stderr}');
      return null;
    }
  }

  /// Bilgisayardan seçilen bir .sql dosyasını veritabanına aktarır.
  static Future<bool> importDatabase(
      Course c, LabPackage p, String sqlFilePath, Log log) async {
    log('\n=== Veritabanı İçe Aktarılıyor ===');
    log('Kaynak dosya: $sqlFilePath');
    final stack = stackDir(c, p);

    String importCmd;
    if (p.id == 'web2-stack') {
      importCmd = 'type "${sqlFilePath.replaceAll('/', '\\')}" | docker compose -f "$stack\\compose.yml" exec -T db mariadb -uroot -proot mflab';
    } else {
      importCmd = 'type "${sqlFilePath.replaceAll('/', '\\')}" | docker compose -f "$stack\\compose.yml" exec -T postgres psql -U postgres postgres';
    }

    final r = await run('cmd', ['/c', importCmd]);
    if (r.exitCode == 0) {
      log('✔ .sql dosyası veritabanına başarıyla aktarıldı.');
      return true;
    } else {
      log('✖ İçe aktarma sırasında hata oluştu: ${r.stderr}');
      return false;
    }
  }

  /// Öğrencinin kodlarını + veritabanı yedeğini tek tıkla teslim Zip'ine dönüştürür.
  static Future<String?> exportHomeworkZip({
    required Course course,
    required Catalog catalog,
    required String studentName,
    required String studentNumber,
    required Log log,
  }) async {
    log('\n=== 📦 Ödev Teslim Paketi Oluşturuluyor ===');
    final cleanName = studentName.trim().replaceAll(RegExp(r'\s+'), '_').replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
    final cleanNo = studentNumber.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final zipName = '${cleanNo}_${cleanName}_${course.id}.zip';

    final rDesk = await run('powershell', ['-NoProfile', '-Command', r"[Environment]::GetFolderPath('Desktop')"]);
    final desktop = (rDesk.stdout as String).trim();
    final outZip = '$desktop\\$zipName';

    final tempDir = Directory('${Directory.systemTemp.path}\\mflab_hw_${DateTime.now().millisecondsSinceEpoch}');
    await tempDir.create(recursive: true);

    try {
      // 1. Öğrenci bilgi dosyası
      final infoFile = File('${tempDir.path}\\OGRENCI_BILGI.txt');
      await infoFile.writeAsString(
        'MF Lab - Odev Teslim Raporu\n'
        '====================================\n'
        'Ogrenci No: $studentNumber\n'
        'Ad Soyad: $studentName\n'
        'Ders: ${course.name}\n'
        'Tarih: ${DateTime.now()}\n'
        '====================================\n',
      );

      // 2. Kod klasörünü kopyala
      final ws = Directory(workspaceDir(course));
      if (await ws.exists()) {
        log('Proje kodları kopyalanıyor...');
        final copyScript = 'Copy-Item -Path "${_ps(ws.path)}\\*" -Destination "${_ps(tempDir.path)}\\kodlar" -Recurse -Force';
        await Directory('${tempDir.path}\\kodlar').create(recursive: true);
        await run('powershell', ['-NoProfile', '-Command', copyScript]);
      }

      // 3. Veritabanı varsa yedeğini al
      for (final id in course.packages) {
        final p = catalog.packages[id];
        if (p != null && p.isDocker) {
          final isUp = await isRunning(course, p);
          if (isUp) {
            log('Veritabanı yedeği pakete ekleniyor...');
            final sqlFile = '${tempDir.path}\\veritabani.sql';
            final stack = stackDir(course, p);
            String dumpCmd = p.id == 'web2-stack'
                ? 'docker compose -f "$stack\\compose.yml" exec -T db mariadb-dump -uroot -proot --all-databases > "${sqlFile.replaceAll('\\', '/')}"'
                : 'docker compose -f "$stack\\compose.yml" exec -T postgres pg_dumpall -U postgres > "${sqlFile.replaceAll('\\', '/')}"';
            await run('cmd', ['/c', dumpCmd]);
          }
        }
      }

      // 4. Zip oluştur
      log('Zip arşivi oluşturuluyor...');
      final zipScript = 'if (Test-Path "${_ps(outZip)}") { Remove-Item -Force "${_ps(outZip)}" }; '
          'Compress-Archive -Path "${_ps(tempDir.path)}\\*" -DestinationPath "${_ps(outZip)}" -Force';
      final r = await run('powershell', ['-NoProfile', '-Command', zipScript]);
      if (r.exitCode == 0 && await File(outZip).exists()) {
        log('🎉 Ödev paketi masaüstünde hazır: $zipName');
        return outZip;
      } else {
        log('✖ Zip oluşturulamadı: ${r.stderr}');
        return null;
      }
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// USB'den veya yerel dosyadan (.tar) imajları Docker'a yükler (çevrimdışı sınıf desteği).
  static Future<bool> importDockerTar(String tarPath, Log log) async {
    log('\n=== 📥 Çevrimdışı İmaj Yükleniyor (.tar) ===');
    log('Dosya: $tarPath');
    final (code, _) = await stream('docker', ['load', '-i', tarPath], log: log);
    if (code == 0) {
      log('✔ İmajlar başarıyla Docker\'a aktarıldı.');
      return true;
    } else {
      log('✖ İmaj yüklenemedi.');
      return false;
    }
  }

  // ----------------------------------------------------------------- update

  static List<int> _ver(String v) => v
      .replaceFirst(RegExp(r'^v'), '')
      .split('.')
      .map((e) => int.tryParse(e) ?? 0)
      .toList();

  static bool isNewer(String remote, String local) {
    final a = _ver(remote), b = _ver(local);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// GitHub'daki version.json'ı okur; yeni sürüm varsa döner.
  static Future<UpdateInfo?> checkUpdate() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      final req = await client.getUrl(Uri.parse(AppConfig.versionJsonUrl));
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final j = jsonDecode(body) as Map<String, dynamic>;
      final v = j['version'] as String;
      if (!isNewer(v, AppConfig.appVersion)) return null;
      return UpdateInfo(
        v,
        (j['url'] ?? AppConfig.releasesUrl) as String,
        (j['notes'] ?? '') as String,
        (j['mandatory'] ?? false) as bool,
      );
    } catch (_) {
      return null;
    }
  }
}
