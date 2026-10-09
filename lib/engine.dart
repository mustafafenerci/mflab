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
      if (!await f.exists()) {
        await f.writeAsString(_htdocsPortalHtml);
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

  // ----------------------------------------------------------- projects & assignments

  /// Çalışma alanındaki (htdocs / proje) alt klasörleri listeler.
  static Future<List<ProjectItem>> getProjects(Course c) async {
    final ws = Directory(workspaceDir(c));
    if (!await ws.exists()) return [];
    final items = <ProjectItem>[];
    try {
      await for (final entity in ws.list(followLinks: false)) {
        if (entity is Directory) {
          final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (name.startsWith('.')) continue;
          final stat = await entity.stat();
          final isLaravel = await File('${entity.path}\\public\\index.php').exists();
          items.add(ProjectItem(
            name: name,
            path: entity.path,
            modified: stat.modified,
            isLaravel: isLaravel,
          ));
        }
      }
    } catch (_) {}
    items.sort((a, b) => b.modified.compareTo(a.modified));
    return items;
  }

  /// Yeni proje veya haftalık ödev klasörü oluşturur.
  static Future<String> createProject({
    required Course course,
    required String projectName,
    required String template, // 'blank', 'crud', 'laravel'
    required Log log,
  }) async {
    final clean = projectName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_').trim();
    if (clean.isEmpty) throw ArgumentError('Geçersiz proje adı');
    final ws = workspaceDir(course);
    final targetDir = Directory('$ws\\$clean');
    if (await targetDir.exists()) {
      throw StateError('"$clean" adında bir proje zaten var.');
    }
    await targetDir.create(recursive: true);

    if (template == 'crud') {
      final f = File('${targetDir.path}\\index.php');
      await f.writeAsString(r'''<?php
// MF Lab - Veritabanı (CRUD) Başlangıç Şablonu
$host = 'db';
$db   = 'mflab';
$user = 'root';
$pass = 'root';
$charset = 'utf8mb4';

$dsn = "mysql:host=$host;dbname=$db;charset=$charset";
$options = [
    PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
];

try {
    $pdo = new PDO($dsn, $user, $pass, $options);
    $pdo->exec("CREATE TABLE IF NOT EXISTS notlar_demo (
        id INT AUTO_INCREMENT PRIMARY KEY,
        baslik VARCHAR(100) NOT NULL,
        tarih TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )");
    
    if ($_SERVER['REQUEST_METHOD'] === 'POST' && !empty($_POST['baslik'])) {
        $stmt = $pdo->prepare("INSERT INTO notlar_demo (baslik) VALUES (?)");
        $stmt->execute([trim($_POST['baslik'])]);
        header("Location: index.php");
        exit;
    }
    
    $veriler = $pdo->query("SELECT * FROM notlar_demo ORDER BY id DESC")->fetchAll();
} catch (PDOException $e) {
    die("Veritabanı bağlantı hatası: " . $e->getMessage());
}
?>
<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="UTF-8">
  <title>CRUD Örneği</title>
  <style>
    body { font-family: sans-serif; background: #f1f5f9; padding: 30px; }
    .card { background: #fff; max-width: 600px; margin: 0 auto; padding: 24px; border-radius: 12px; box-shadow: 0 4px 6px rgba(0,0,0,0.05); }
    input[type=text] { width: 70%; padding: 8px 12px; border: 1px solid #cbd5e1; border-radius: 6px; }
    button { padding: 8px 16px; background: #0284c7; color: #fff; border: none; border-radius: 6px; cursor: pointer; }
    ul { list-style: none; padding: 0; margin-top: 20px; }
    li { padding: 10px; border-bottom: 1px solid #e2e8f0; display: flex; justify-content: space-between; }
  </style>
</head>
<body>
  <div class="card">
    <h2>✔ MariaDB Veritabanı CRUD Şablonu</h2>
    <p>Bağlantı durumu: <b>Başarılı (db:3306)</b></p>
    <hr style="margin: 16px 0; border: 0; border-top: 1px solid #e2e8f0;">
    <form method="POST">
      <input type="text" name="baslik" placeholder="Yeni bir not yazın..." required>
      <button type="submit">Ekle</button>
    </form>
    <ul>
      <?php foreach ($veriler as $row): ?>
        <li><span><?= htmlspecialchars($row['baslik']) ?></span> <small style="color:#64748b;"><?= $row['tarih'] ?></small></li>
      <?php endforeach; ?>
    </ul>
    <p style="margin-top: 20px;"><a href="../">← MF Lab Portalına Dön</a></p>
  </div>
</body>
</html>
''');
    } else if (template == 'laravel') {
      log('Laravel projesi kuruluyor (birkaç dakika sürebilir)...');
      await targetDir.delete();
      final stack = '${courseDir(course)}\\.stack\\web2-stack';
      final (code, out) = await stream(
        'docker',
        ['compose', 'exec', '-T', 'web', 'composer', 'create-project', 'laravel/laravel', clean],
        cwd: stack,
        log: log,
      );
      if (code != 0) {
        log('✖ Laravel kurulumu başarısız: $out');
        throw StateError('Laravel kurulumu başarısız.');
      }
    } else {
      final f = File('${targetDir.path}\\index.php');
      await f.writeAsString('''<?php
// MF Lab - $clean
?>
<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="UTF-8">
  <title>$clean</title>
  <style>
    body { font-family: sans-serif; background: #f8fafc; color: #1e293b; padding: 40px; }
    .box { background: #fff; max-width: 600px; margin: 0 auto; padding: 30px; border-radius: 12px; box-shadow: 0 4px 6px rgba(0,0,0,0.05); }
  </style>
</head>
<body>
  <div class="box">
    <h1>🚀 $clean</h1>
    <p>Bu dosya: <code>htdocs/$clean/index.php</code></p>
    <p>PHP: <?= phpversion() ?></p>
    <hr style="margin: 20px 0; border: 0; border-top: 1px solid #e2e8f0;">
    <p><a href="../">← MF Lab Portalına Dön</a></p>
  </div>
</body>
</html>
''');
    }

    log('✔ "$clean" projesi başarıyla oluşturuldu.');
    return targetDir.path;
  }

  /// Öğrencinin ödevini ve veritabanını tek tıkla Masaüstüne ZIP yapar.
  static Future<String> packageAssignment({
    required Course course,
    String? subprojectName,
    required String studentName,
    required String studentNo,
    required Log log,
  }) async {
    log('\n=== 📦 Ödev Paketleme Başlatılıyor ===');
    final ws = workspaceDir(course);
    final sourcePath = (subprojectName != null && subprojectName.isNotEmpty)
        ? '$ws\\$subprojectName'
        : ws;

    if (!await Directory(sourcePath).exists()) {
      throw StateError('Paketlenecek klasör bulunamadı: $sourcePath');
    }

    final tempDump = File('${Directory.systemTemp.path}\\mflab_dump.sql');
    if (await tempDump.exists()) {
      try { await tempDump.delete(); } catch (_) {}
    }

    try {
      final stack = '${courseDir(course)}\\.stack\\web2-stack';
      final vtysStack = '${courseDir(course)}\\.stack\\vtys-stack';
      final targetStack = (await Directory(stack).exists()) ? stack : vtysStack;

      if (await Directory(targetStack).exists()) {
        log('Veritabanı yedeği alınıyor...');
        final r = await run(
          'docker',
          ['compose', 'exec', '-T', 'db', 'mariadb-dump', '-u', 'root', '-proot', 'mflab'],
          cwd: targetStack,
        );
        if (r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty) {
          await tempDump.writeAsString(r.stdout as String);
          log('✔ MariaDB "mflab" veritabanı yedeği eklendi (veritabani.sql).');
        }
      }
    } catch (_) {}

    final cleanName = (studentName.trim().isEmpty ? 'Ogrenci' : studentName.trim())
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final cleanNo = studentNo.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final targetLabel = (subprojectName != null && subprojectName.isNotEmpty)
        ? subprojectName
        : course.id;
    final zipBaseName = '${cleanName}_${cleanNo.isEmpty ? '' : '${cleanNo}_'}${targetLabel}_Odev.zip';

    final script = StringBuffer()
      ..writeln(r"$desktop = [Environment]::GetFolderPath('Desktop')")
      ..writeln("\$outZip = Join-Path \$desktop '${_ps(zipBaseName)}'")
      ..writeln("\$srcDir = '${_ps(sourcePath)}'")
      ..writeln(r'if (Test-Path $outZip) { Remove-Item -Force $outZip }')
      ..writeln(r'$files = Get-ChildItem -Path $srcDir -Exclude "vendor", "node_modules", ".git"')
      ..writeln(r'$paths = @($files.FullName)')
      ..writeln("if (Test-Path '${_ps(tempDump.path)}') { \$paths += '${_ps(tempDump.path)}' }")
      ..writeln(r'Compress-Archive -Path $paths -DestinationPath $outZip -Force')
      ..writeln(r'Write-Output $outZip');

    final tmpScript = File('${Directory.systemTemp.path}\\mflab_zip.ps1');
    await tmpScript.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(script.toString())]);

    final r = await run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      tmpScript.path,
    ]);

    if (await tempDump.exists()) {
      try { await tempDump.delete(); } catch (_) {}
    }

    if (r.exitCode != 0) {
      log('✖ ZIP oluşturulamadı: ${r.stderr}');
      throw StateError('Paketleme başarısız oldu.');
    }

    final outZipPath = (r.stdout as String).trim();
    log('✔ Ödev paketi başarıyla Masaüstünüze oluşturuldu:');
    log('  $outZipPath');

    try {
      await Process.start('explorer.exe', ['/select,', outZipPath], runInShell: true);
    } catch (_) {}

    return outZipPath;
  }

  /// Örnek eğitim veritabanını Docker MariaDB'ye aktarır.
  static Future<void> loadSampleDatabase({
    required Course course,
    required String sampleKey,
    required Log log,
  }) async {
    log('\n=== 🗄️ Örnek Veritabanı Yükleniyor ($sampleKey) ===');
    final stack = '${courseDir(course)}\\.stack\\web2-stack';
    final vtysStack = '${courseDir(course)}\\.stack\\vtys-stack';
    final targetStack = (await Directory(stack).exists()) ? stack : vtysStack;

    String sql;
    String dbName;
    if (sampleKey == 'eticaret') {
      dbName = 'E-Ticaret Demo';
      sql = '''
CREATE DATABASE IF NOT EXISTS mflab CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE mflab;
DROP TABLE IF EXISTS siparisler;
DROP TABLE IF EXISTS urunler;
DROP TABLE IF EXISTS kategoriler;
CREATE TABLE kategoriler (
  id INT AUTO_INCREMENT PRIMARY KEY,
  ad VARCHAR(50) NOT NULL
);
CREATE TABLE urunler (
  id INT AUTO_INCREMENT PRIMARY KEY,
  kategori_id INT,
  ad VARCHAR(100) NOT NULL,
  fiyat DECIMAL(10,2) NOT NULL,
  stok INT DEFAULT 0,
  FOREIGN KEY (kategori_id) REFERENCES kategoriler(id) ON DELETE SET NULL
);
INSERT INTO kategoriler (ad) VALUES ('Elektronik'), ('Kitap'), ('Yazılım');
INSERT INTO urunler (kategori_id, ad, fiyat, stok) VALUES
  (1, 'Kablosuz Klavye & Mouse', 550.00, 30),
  (1, 'USB-C Hub Çoklayıcı', 320.00, 45),
  (2, 'PHP & MySQL Başucu Kitabı', 240.00, 100),
  (2, 'Temiz Kod (Clean Code)', 280.00, 60),
  (3, 'IDE Yıllık Lisans', 1200.00, 15);
''';
    } else if (sampleKey == 'kutuphane') {
      dbName = 'Kütüphane Sistemi';
      sql = '''
CREATE DATABASE IF NOT EXISTS mflab CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE mflab;
DROP TABLE IF EXISTS odunc;
DROP TABLE IF EXISTS kitaplar;
DROP TABLE IF EXISTS uyeler;
CREATE TABLE uyeler (
  id INT AUTO_INCREMENT PRIMARY KEY,
  ad VARCHAR(50) NOT NULL,
  soyad VARCHAR(50) NOT NULL,
  eposta VARCHAR(100) UNIQUE
);
CREATE TABLE kitaplar (
  id INT AUTO_INCREMENT PRIMARY KEY,
  baslik VARCHAR(150) NOT NULL,
  yazar VARCHAR(100) NOT NULL,
  sayfa INT
);
INSERT INTO uyeler (ad, soyad, eposta) VALUES
  ('Ali', 'Yıldız', 'ali@example.com'),
  ('Zeynep', 'Kaya', 'zeynep@example.com');
INSERT INTO kitaplar (baslik, yazar, sayfa) VALUES
  ('Nutuk', 'Mustafa Kemal Atatürk', 600),
  ('Simyacı', 'Paulo Coelho', 188),
  ('Kürk Mantolu Madonna', 'Sabahattin Ali', 160);
''';
    } else {
      dbName = 'Öğrenci Not Sistemi';
      sql = '''
CREATE DATABASE IF NOT EXISTS mflab CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE mflab;
DROP TABLE IF EXISTS notlar;
DROP TABLE IF EXISTS ogrenciler;
CREATE TABLE ogrenciler (
  id INT AUTO_INCREMENT PRIMARY KEY,
  ad VARCHAR(50) NOT NULL,
  soyad VARCHAR(50) NOT NULL,
  ogrenci_no VARCHAR(20) NOT NULL UNIQUE,
  bolum VARCHAR(100) NOT NULL
);
CREATE TABLE notlar (
  id INT AUTO_INCREMENT PRIMARY KEY,
  ogrenci_id INT NOT NULL,
  ders_adi VARCHAR(100) NOT NULL,
  vize INT,
  final INT,
  FOREIGN KEY (ogrenci_id) REFERENCES ogrenciler(id) ON DELETE CASCADE
);
INSERT INTO ogrenciler (ad, soyad, ogrenci_no, bolum) VALUES
  ('Ahmet', 'Yılmaz', '2026101', 'Bilgisayar Programcılığı'),
  ('Ayşe', 'Demir', '2026102', 'Bilişim Güvenliği'),
  ('Mehmet', 'Kaya', '2026103', 'Yazılım Mühendisliği'),
  ('Fatma', 'Çelik', '2026104', 'Bilgisayar Programcılığı');
INSERT INTO notlar (ogrenci_id, ders_adi, vize, final) VALUES
  (1, 'Web Programlama II', 85, 90),
  (1, 'Veritabanı Yönetimi', 75, 80),
  (2, 'Web Programlama II', 90, 95),
  (3, 'Veritabanı Yönetimi', 60, 70),
  (4, 'Web Programlama II', 100, 100);
''';
    }

    final tmpSql = File('${Directory.systemTemp.path}\\sample_init.sql');
    await tmpSql.writeAsString(sql);

    final r = await run('powershell', [
      '-NoProfile',
      '-Command',
      "Get-Content '${tmpSql.path}' | docker compose exec -T db mariadb -u root -proot mflab"
    ], cwd: targetStack);

    try { await tmpSql.delete(); } catch (_) {}

    if (r.exitCode == 0) {
      log('✔ "$dbName" tabloları ve örnek verileri "mflab" veritabanına başarıyla yüklendi.');
      log('phpMyAdmin üzerinden (http://localhost:6381) tabloları inceleyebilirsiniz.');
    } else {
      log('✖ Veritabanı aktarımı başarısız oldu: ${r.stderr}');
    }
  }

  /// MF Lab portlarının durumunu (çakışma var mı, dinleniyor mu) analiz eder.
  static Future<void> checkPorts(Log log) async {
    log('\n=== 🩺 MF Lab Port Doktoru & Teşhis ===');
    final ports = <int, String>{
      6380: 'Apache Web Sunucusu (Web Programlama II)',
      6381: 'phpMyAdmin (Web Programlama II)',
      6306: 'MariaDB Veritabanı (Web Programlama II)',
      6332: 'PostgreSQL Veritabanı (VTYS)',
      6350: 'pgAdmin Arayüzü (VTYS)',
      6307: 'MariaDB Veritabanı (VTYS)',
      6382: 'phpMyAdmin (VTYS)',
    };

    for (final entry in ports.entries) {
      final port = entry.key;
      final desc = entry.value;
      try {
        final socket = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 350));
        socket.destroy();
        log('🟢 Port $port: Aktif & Dinliyor ($desc)');
      } catch (_) {
        log('⚪ Port $port: Boş / Servis kapalı ($desc)');
      }
    }
    log('===========================================\n'
        'Not: "Aktif & Dinliyor" yeşil olan portlar servislerinizin çalıştığını doğrular.');
  }

  /// Kullanılmayan Docker konteyner ve önbelleklerini temizler.
  static Future<void> cleanDocker(Log log) async {
    log('\n=== 🧹 Docker Sistem & Önbellek Temizliği ===');
    log('Kullanılmayan önbellekler temizleniyor...');
    await stream('docker', ['system', 'prune', '-f'], log: log);
    log('✔ Docker önbellek temizliği tamamlandı.');
  }

  static String get _htdocsPortalHtml => r'''<?php
// MF Lab - Akilli Ogrenci Calisma Portali
$dbOk = false;
$dbErr = '';
try {
    $pdo = new PDO("mysql:host=db;dbname=mflab;charset=utf8mb4", "root", "root", [PDO::ATTR_TIMEOUT => 2]);
    $dbOk = true;
} catch (Exception $e) {
    $dbErr = $e->getMessage();
}

$msg = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && !empty($_POST['folder_name'])) {
    $rawName = trim($_POST['folder_name']);
    $folderName = preg_replace('/[^a-zA-Z0-9_\-]/', '_', $rawName);
    if (!empty($folderName) && !is_dir($folderName)) {
        mkdir($folderName, 0777, true);
        $sampleCode = "<?php\n// Proje: {$folderName}\n?>\n<!DOCTYPE html>\n<html lang=\"tr\">\n<head>\n  <meta charset=\"UTF-8\">\n  <title>{$folderName}</title>\n  <style>body{font-family:sans-serif;padding:30px;line-height:1.6;background:#f8fafc;color:#1e293b;}.card{background:#fff;padding:24px;border-radius:12px;box-shadow:0 4px 6px rgba(0,0,0,0.05);max-width:600px;margin:0 auto;}</style>\n</head>\n<body>\n  <div class=\"card\">\n    <h2>🚀 {$folderName} Calisiyor!</h2>\n    <p>Bu dosya: <code>htdocs/{$folderName}/index.php</code></p>\n    <p>PHP Surumu: " . phpversion() . "</p>\n    <p><a href=\"../\">← MF Lab Portalina Don</a></p>\n  </div>\n</body>\n</html>";
        file_put_contents("{$folderName}/index.php", $sampleCode);
        header("Location: {$folderName}/");
        exit;
    } else {
        $msg = 'Klasor zaten mevcut veya gecersiz isim!';
    }
}

$projects = [];
$items = scandir('.');
foreach ($items as $item) {
    if ($item === '.' || $item === '..' || !is_dir($item) || $item[0] === '.') continue;
    $targetUrl = $item . '/';
    $isLaravel = false;
    if (is_dir($item . '/public') && file_exists($item . '/public/index.php')) {
        $targetUrl = $item . '/public/';
        $isLaravel = true;
    }
    $mtime = filemtime($item);
    $projects[] = [
        'name' => $item,
        'url' => $targetUrl,
        'isLaravel' => $isLaravel,
        'mtime' => date('d.m.Y H:i', $mtime),
    ];
}
?>
<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>MF Lab - Ogrenci Portali</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #0f172a; color: #f8fafc; padding: 30px 20px; line-height: 1.5; }
    .container { max-width: 900px; margin: 0 auto; }
    header { background: linear-gradient(135deg, #1e293b, #334155); padding: 28px; border-radius: 16px; border: 1px solid #475569; margin-bottom: 24px; box-shadow: 0 10px 25px rgba(0,0,0,0.3); }
    h1 { font-size: 26px; color: #38bdf8; margin-bottom: 8px; display: flex; align-items: center; gap: 10px; }
    .status-bar { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 14px; font-size: 13px; }
    .badge { padding: 4px 10px; border-radius: 8px; background: #1e293b; border: 1px solid #475569; display: inline-flex; align-items: center; gap: 6px; }
    .badge.success { border-color: #10b981; color: #34d399; }
    .badge.warn { border-color: #f59e0b; color: #fbbf24; }
    .badge a { color: inherit; text-decoration: none; font-weight: 600; }
    .create-card { background: #1e293b; border: 1px solid #334155; padding: 20px; border-radius: 14px; margin-bottom: 24px; }
    .create-card h2 { font-size: 17px; margin-bottom: 12px; color: #94a3b8; }
    .form-row { display: flex; gap: 10px; }
    input[type="text"] { flex: 1; padding: 10px 14px; border-radius: 8px; border: 1px solid #475569; background: #0f172a; color: #fff; font-size: 14px; }
    input[type="text"]:focus { outline: none; border-color: #38bdf8; }
    button { background: #0284c7; color: #fff; border: none; padding: 10px 18px; border-radius: 8px; font-weight: 600; cursor: pointer; }
    button:hover { background: #0369a1; }
    .section-title { font-size: 18px; margin-bottom: 14px; color: #cbd5e1; display: flex; justify-content: space-between; align-items: center; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 16px; }
    .project-card { background: #1e293b; border: 1px solid #334155; padding: 18px; border-radius: 12px; display: flex; flex-direction: column; justify-content: space-between; }
    .project-card:hover { border-color: #38bdf8; }
    .project-name { font-size: 17px; font-weight: 600; color: #f1f5f9; margin-bottom: 6px; word-break: break-all; }
    .project-meta { font-size: 12px; color: #64748b; margin-bottom: 14px; }
    .project-btn { display: inline-block; text-align: center; background: #334155; color: #38bdf8; text-decoration: none; padding: 8px 14px; border-radius: 8px; font-size: 13px; font-weight: 600; border: 1px solid #475569; }
    .project-btn:hover { background: #38bdf8; color: #0f172a; }
    .empty-state { text-align: center; padding: 40px; background: #1e293b; border-radius: 12px; border: 1px dashed #475569; color: #94a3b8; }
  </style>
</head>
<body>
<div class="container">
  <header>
    <h1>🎓 MF Lab Ogrenci Portali</h1>
    <p style="color: #94a3b8; font-size: 14px;">Calisma alanindaki projeleriniz ve haftalik odevleriniz asagida listelenmistir.</p>
    <div class="status-bar">
      <span class="badge success">✔ PHP <?= phpversion() ?></span>
      <span class="badge <?= $dbOk ? 'success' : 'warn' ?>"><?= $dbOk ? '✔ MariaDB Bagli' : '⚠️ MariaDB: ' . htmlspecialchars($dbErr) ?></span>
      <span class="badge"><a href="http://localhost:6381" target="_blank">🐬 phpMyAdmin Ac (6381) ↗</a></span>
      <span class="badge">📁 C:\MFLab\htdocs</span>
    </div>
  </header>

  <div class="create-card">
    <h2>➕ Yeni Hafta / Proje Klasoru Ekle</h2>
    <form method="POST" class="form-row">
      <input type="text" name="folder_name" placeholder="Orn: hafta1_giris veya odev2" required pattern="[a-zA-Z0-9_\-]+" title="Bosluksuz harf, rakam ve alt cizgi kullanin">
      <button type="submit">Olustur ve Ac</button>
    </form>
    <?php if ($msg): ?><p style="color:#ef4444; font-size:13px; margin-top:8px;"><?= htmlspecialchars($msg) ?></p><?php endif; ?>
  </div>

  <div class="section-title">
    <span>📁 Projeleriniz (<?= count($projects) ?>)</span>
    <span style="font-size: 12px; color: #64748b;">Dogrudan projeye gitmek icin tiklayin</span>
  </div>

  <?php if (empty($projects)): ?>
    <div class="empty-state">
      <p style="font-size: 16px; margin-bottom: 8px;">Henuz bir alt proje veya hafta klasoru eklenmedi.</p>
      <p style="font-size: 13px;">Yukaridaki alandan <b>hafta1</b> gibi bir isim yazarak ilk projenizi baslatabilirsiniz.</p>
    </div>
  <?php else: ?>
    <div class="grid">
      <?php foreach ($projects as $p): ?>
        <div class="project-card">
          <div>
            <div class="project-name">📁 <?= htmlspecialchars($p['name']) ?></div>
            <div class="project-meta">Guncelleme: <?= $p['mtime'] ?><?= $p['isLaravel'] ? ' · <b style="color:#f43f5e;">Laravel</b>' : '' ?></div>
          </div>
          <a href="<?= htmlspecialchars($p['url']) ?>" class="project-btn">Projeyi Calistir ↗</a>
        </div>
      <?php endforeach; ?>
    </div>
  <?php endif; ?>
</div>
</body>
</html>
''';

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
    final exe = Platform.resolvedExecutable;
    if (exe.isNotEmpty && exe.toLowerCase().endsWith('.exe')) {
      sb.writeln("Lnk 'MF Lab Yönetim Paneli' '${_ps(exe)}' \$null \$null");
    }
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

    final infoText = [
      '============================================================',
      '  MF Lab - Ders ve Calisma Ortami Bilgisi',
      '============================================================',
      'Ders           : ${_ps(course.name)} (${_ps(course.id)})',
      'MF Lab Surumu  : v${AppConfig.appVersion}',
      'Kurulum Tarihi : \$(Get-Date -Format "dd.MM.yyyy HH:mm:ss")',
      'Gelistirici    : ${_ps(AppConfig.author)}',
      'GitHub         : ${_ps(AppConfig.repoUrl)}',
      '',
      'Calisma Alani  : ${_ps(ws)}',
      'Konteyner Dizini: ${_ps(courseDir(course))}\\.stack',
      '',
      'HIZLI ERISIM & KULLANIM:',
      '1. "VS Code ile ac" kisayolu ile projeyi kodlamaya baslayabilirsin.',
      '2. "${course.workspaceName} klasoru" icinde olusturdugun tum kodlar saklanir.',
      '3. Servisleri baslatmak/durdurmak veya loglari gormek icin',
      '   "MF Lab Yonetim Paneli" kisayolunu calistirabilirsin.',
      '============================================================',
    ].join('`r`n');

    sb.writeln(
        "Set-Content -Path (Join-Path \$dir 'MF_LAB_BILGI.txt') -Value \"$infoText\" -Encoding UTF8");

    try {
      final infoCourse = File('${courseDir(course)}\\MF_LAB_BILGI.txt');
      await infoCourse.writeAsString('''============================================================
  MF Lab - Ders ve Çalışma Ortamı Bilgisi
============================================================
Ders           : ${course.name} (${course.id})
MF Lab Sürümü  : v${AppConfig.appVersion}
Kurulum Tarihi : ${DateTime.now().toString().split('.').first}
Geliştirici    : ${AppConfig.author}
GitHub         : ${AppConfig.repoUrl}
Çalışma Alanı  : $ws
============================================================
''');
    } catch (_) {}

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
    String? subprojectName,
    required Log log,
  }) async {
    log('\n=== 📦 Ödev Teslim Paketi Oluşturuluyor ===');
    final cleanName = studentName.trim().replaceAll(RegExp(r'\s+'), '_').replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
    final cleanNo = studentNumber.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final cleanSub = (subprojectName != null && subprojectName.isNotEmpty)
        ? '_${subprojectName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')}'
        : '';
    final zipName = '${cleanNo}_${cleanName}_${course.id}$cleanSub.zip';

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
        'Proje / Hafta: ${subprojectName ?? "Tüm Çalışma Alanı"}\n'
        'Tarih: ${DateTime.now()}\n'
        '====================================\n',
      );

      // 2. Kod klasörünü kopyala
      final ws = Directory(workspaceDir(course));
      final sourceDir = (subprojectName != null && subprojectName.isNotEmpty)
          ? Directory('${ws.path}\\$subprojectName')
          : ws;
      if (await sourceDir.exists()) {
        log('Proje kodları kopyalanıyor (${subprojectName ?? "Tüm Projeler"})...');
        final copyScript = 'Copy-Item -Path "${_ps(sourceDir.path)}\\*" -Destination "${_ps(tempDir.path)}\\kodlar" -Recurse -Force';
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
        try {
          await Process.start('explorer.exe', ['/select,', outZip], runInShell: true);
        } catch (_) {}
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
