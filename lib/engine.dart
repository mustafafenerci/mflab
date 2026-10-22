import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'platform.dart';

import 'package:flutter/services.dart';

import 'config.dart';
import 'models.dart';
import 'preflight.dart';

typedef Log = void Function(String);

class InstallResult {
  InstallResult(this.ok, {this.help});
  final bool ok;
  final HelpEntry? help;
}

class Engine {
  static String courseDir(Course c) => '${AppConfig.baseDir}${Os.sep}${c.id}';
  static String workspaceDir(Course c) =>
      '${courseDir(c)}${Os.sep}${c.workspaceName}';
  static String stackDir(Course c, LabPackage p) =>
      '${courseDir(c)}${Os.sep}.stack${Os.sep}${p.id}';

  // ---------------------------------------------------------------- process

  /// Docker ve PowerShell çıktısı UTF-8'dir; systemEncoding ile okununca
  /// Türkçe karakterler bozuluyordu ("Ã¶", "ÅŸ" gibi).
  static const _utf8 = Utf8Codec(allowMalformed: true);

  /// Alt süreçlere verilen ortam. Uygulama açıldıktan sonra kurulan programlar (VS Code, Git,
  /// Docker) çalışan sürecin PATH'inde olmaz; [refreshPath] güncel PATH'i buraya koyar.
  static Map<String, String>? _env;

  /// Windows'taki güncel (Makine + Kullanıcı) PATH'i okur ve bilinen kurulum klasörlerini ekler.
  /// Böylece VS Code / Git / Docker'ı sonradan kuran öğrenci uygulamayı kapatıp açmak zorunda kalmaz.
  static Future<void> refreshPath() async {
    final parts = <String>[];
    final seen = <String>{};
    void add(String? raw) {
      final v = (raw ?? '').trim();
      if (v.isEmpty) return;
      if (seen.add(v.toLowerCase())) parts.add(v);
    }

    final pathSep = Os.isWindows ? ';' : ':';
    for (final x in (Platform.environment['PATH'] ?? '').split(pathSep)) {
      add(x);
    }
    if (Os.isWindows) {
      try {
        final r = await Process.run(
            'powershell',
            [
              '-NoProfile',
              '-Command',
              "[Environment]::GetEnvironmentVariable('Path','Machine') + ';' + "
                  "[Environment]::GetEnvironmentVariable('Path','User')"
            ],
            stdoutEncoding: _utf8);
        for (final x in (r.stdout as String).split(';')) {
          add(x);
        }
      } catch (_) {}
    }
    // PATH'e eklenmemiş olsa bile bilinen kurulum yerlerine bak.
    // (macOS'ta Dock/Finder'dan açılan uygulamanın PATH'i neredeyse boştur.)
    for (final d in _knownToolDirs()) {
      if (Directory(d).existsSync()) add(d);
    }
    _env = {'PATH': parts.join(pathSep)};
  }

  /// POSIX'te komutu, güncellenmiş PATH'te arayıp tam yolunu döner (Windows'ta olduğu gibi bırakır).
  static String _exe(String cmd) {
    if (Os.isWindows || cmd.contains('/')) return cmd;
    final path = _env?['PATH'] ?? Platform.environment['PATH'] ?? '';
    for (final d in path.split(':')) {
      if (d.isEmpty) continue;
      final f = File('$d/$cmd');
      if (f.existsSync()) return f.path;
    }
    return cmd;
  }

  static List<String> _knownToolDirs() {
    if (!Os.isWindows) return Os.extraToolDirs;
    final local = Platform.environment['LOCALAPPDATA'] ?? '';
    final pf = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    final pf86 =
        Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
    return [
      '$local${Os.sep}Programs${Os.sep}Microsoft VS Code${Os.sep}bin',
      '$pf${Os.sep}Microsoft VS Code${Os.sep}bin',
      '$pf86${Os.sep}Microsoft VS Code${Os.sep}bin',
      '$pf${Os.sep}Git${Os.sep}cmd',
      '$pf86${Os.sep}Git${Os.sep}cmd',
      '$pf${Os.sep}Docker${Os.sep}Docker${Os.sep}resources${Os.sep}bin',
    ];
  }

  /// VS Code'un çalıştırılabilir dosyası (kurulu değilse null).
  static String? findVsCodeExe() {
    if (!Os.isWindows) return null;
    final local = Platform.environment['LOCALAPPDATA'] ?? '';
    final pf = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    final pf86 =
        Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
    for (final c in [
      '$local${Os.sep}Programs${Os.sep}Microsoft VS Code${Os.sep}Code.exe',
      '$pf${Os.sep}Microsoft VS Code${Os.sep}Code.exe',
      '$pf86${Os.sep}Microsoft VS Code${Os.sep}Code.exe',
    ]) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  static Future<ProcessResult> run(String cmd, List<String> args,
      {String? cwd}) {
    return Process.run(_exe(cmd), args,
        workingDirectory: cwd,
        runInShell: Os.isWindows,
        environment: _env,
        stdoutEncoding: _utf8,
        stderrEncoding: _utf8);
  }

  /// Komutu çalıştırır, çıktıyı canlı olarak [log]'a akıtır ve tüm çıktıyı döner.
  ///
  /// [heartbeat] açıksa, uzun süre çıktı gelmediğinde öğrenci takıldı sanmasın diye
  /// her 30 saniyede bir "hâlâ çalışıyor" yazar.
  static Future<(int, String)> stream(String cmd, List<String> args,
      {String? cwd, required Log log, bool heartbeat = false}) async {
    final buf = StringBuffer();
    final started = DateTime.now();
    var lastOutput = DateTime.now();
    final timer = heartbeat
        ? Timer.periodic(const Duration(seconds: 30), (_) {
            if (DateTime.now().difference(lastOutput).inSeconds < 25) return;
            final el = DateTime.now().difference(started);
            log('… hâlâ çalışıyor (${el.inMinutes} dk ${el.inSeconds % 60} sn). '
                'İnternet hızına göre birkaç dakika sürebilir, pencereyi kapatma.');
          })
        : null;
    final proc = await Process.start(_exe(cmd), args,
        workingDirectory: cwd, runInShell: Os.isWindows, environment: _env);
    final done = <Future<void>>[];
    for (final s in [proc.stdout, proc.stderr]) {
      final c = Completer<void>();
      done.add(c.future);
      s.transform(_utf8.decoder).listen((d) {
        lastOutput = DateTime.now();
        buf.write(d);
        final t = d.trim();
        if (t.isNotEmpty) log(t);
      }, onDone: c.complete, onError: (_) => c.complete());
    }
    await Future.wait(done);
    final code = await proc.exitCode;
    timer?.cancel();
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

  /// Dosya yöneticisi/tarayıcı gibi bir masaüstü programını açar ve beklemez.
  static Future<void> _launch(String cmd, List<String> args) async {
    try {
      await Process.start(_exe(cmd), args,
          runInShell: Os.isWindows,
          environment: _env,
          mode: ProcessStartMode.detached);
    } catch (_) {}
  }

  static Future<void> openUrl(String url) async {
    if (Os.isWindows) {
      await run('cmd', ['/c', 'start', '', url]);
    } else {
      await _launch(Os.isMac ? 'open' : 'xdg-open', [url]);
    }
  }

  /// Varsayılan e-posta programında hazır bir ileti açar. Windows'ta `cmd start` kullanılmaz:
  /// adresteki `&` işaretini komut ayracı sayıp iletiyi keserdi.
  static Future<void> openMailto(String uri) async {
    if (Os.isWindows) {
      await _launch('rundll32', ['url.dll,FileProtocolHandler', uri]);
    } else {
      await _launch(Os.isMac ? 'open' : 'xdg-open', [uri]);
    }
  }

  static Future<void> openFolder(String path) async {
    await Directory(path).create(recursive: true);
    if (Os.isWindows) {
      await Process.start('explorer', [path], runInShell: true);
    } else {
      await _launch(Os.isMac ? 'open' : 'xdg-open', [path]);
    }
  }

  /// Dosya yöneticisinde dosyayı seçili gösterir.
  static Future<void> revealFile(String path) async {
    try {
      if (Os.isWindows) {
        await Process.start('explorer.exe', ['/select,', path], runInShell: true);
      } else if (Os.isMac) {
        await _launch('open', ['-R', path]);
      } else {
        await _launch('xdg-open', [File(path).parent.path]);
      }
    } catch (_) {}
  }

  static Future<void> openInVsCode(String path) async {
    await Directory(path).create(recursive: true);
    await refreshPath();
    if (Os.isMac && !await commandOk('code --version')) {
      await _launch('open', ['-a', 'Visual Studio Code', path]);
      return;
    }
    await run('code', [path]);
  }

  /// Masaüstü klasörü (Windows'ta OneDrive'a taşınmış olabilir, bu yüzden Windows'a sorulur).
  static Future<String> desktopDir() async {
    if (Os.isWindows) {
      final r = await run('powershell',
          ['-NoProfile', '-Command', r"[Environment]::GetFolderPath('Desktop')"]);
      final d = (r.stdout as String).trim();
      if (d.isNotEmpty) return d;
      return '${Os.home}\\Desktop';
    }
    if (Os.isLinux) {
      try {
        final r = await run('xdg-user-dir', ['DESKTOP']);
        final d = (r.stdout as String).trim();
        if (r.exitCode == 0 && d.isNotEmpty && Directory(d).existsSync()) return d;
      } catch (_) {}
    }
    final d = Directory('${Os.home}/Desktop');
    if (!d.existsSync()) {
      try {
        d.createSync(recursive: true);
      } catch (_) {
        return Os.home;
      }
    }
    return d.path;
  }

  /// `docker ...` çıktısını (ör. veritabanı dökümü) bayt bayt dosyaya yazar.
  static Future<bool> dockerToFile(List<String> args, String cwd, File out) async {
    try {
      final proc = await Process.start(_exe('docker'), args,
          workingDirectory: cwd, runInShell: Os.isWindows, environment: _env);
      final sink = out.openWrite();
      final done = proc.stdout.pipe(sink);
      final err = proc.stderr.drain<void>();
      final code = await proc.exitCode;
      await done;
      await err;
      return code == 0;
    } catch (_) {
      return false;
    }
  }

  /// Dosyayı `docker ...` komutunun girdisine verir (ör. .sql içe aktarma).
  static Future<(int, String)> dockerFromFile(
      List<String> args, String cwd, File input) async {
    try {
      final proc = await Process.start(_exe('docker'), args,
          workingDirectory: cwd, runInShell: Os.isWindows, environment: _env);
      final errBuf = StringBuffer();
      final errDone = proc.stderr.transform(_utf8.decoder).forEach(errBuf.write);
      final outDone = proc.stdout.drain<void>();
      await input.openRead().pipe(proc.stdin);
      final code = await proc.exitCode;
      await errDone;
      await outDone;
      return (code, errBuf.toString());
    } catch (e) {
      return (1, '$e');
    }
  }

  /// [src] klasörünün içeriğini [dst]'ye kopyalar; [exclude] adlı ilk seviye öğeleri atlar.
  static Future<void> copyDir(Directory src, Directory dst,
      {Set<String> exclude = const {}}) async {
    await dst.create(recursive: true);
    await for (final e in src.list(followLinks: false)) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (exclude.contains(name)) continue;
      if (e is Directory) {
        await copyDir(e, Directory('${dst.path}${Os.sep}$name'));
      } else if (e is File) {
        await e.copy('${dst.path}${Os.sep}$name');
      }
    }
  }

  /// macOS/Linux'ta [stagingDir] içeriğini `zip` komutuyla [outZip] dosyasına arşivler.
  static Future<bool> zipDirPosix(String stagingDir, String outZip) async {
    try {
      if (File(outZip).existsSync()) File(outZip).deleteSync();
      final r = await run('zip', ['-r', '-q', outZip, '.'], cwd: stagingDir);
      return r.exitCode == 0 && File(outZip).existsSync();
    } catch (_) {
      return false;
    }
  }


  // ------------------------------------------------------- otomatik başlatma

  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _runValue = 'MF Lab';

  /// Windows açılınca MF Lab'ı saatin yanında (pencere açmadan) başlatır ya da bunu kapatır.
  static Future<bool> setAutostart(bool enabled) async {
    if (!Os.isWindows) return false;
    try {
      final exe = Platform.resolvedExecutable;
      final r = enabled
          ? await Process.run('reg', [
              'add', _runKey, '/v', _runValue, '/t', 'REG_SZ',
              '/d', '"$exe" --tray', '/f',
            ])
          : await Process.run('reg', ['delete', _runKey, '/v', _runValue, '/f']);
      return r.exitCode == 0 || !enabled;
    } catch (_) {
      return false;
    }
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
    await refreshPath();
    if (await commandOk(p.check!)) {
      log('✔ ${p.name} kurulu.');
      return true;
    }
    log('✖ ${p.name} bulunamadı. İndirme sayfası açılıyor: ${p.downloadUrl}');
    log('Kurulumu bitirdikten sonra bu uygulamada "Kur" düğmesine tekrar bas. '
        'Uygulamayı kapatıp açmana gerek yok, yeni kurulan program otomatik bulunur.');
    await openUrl(p.downloadUrl!);
    return false;
  }

  static Future<void> installExtensions(List<String> ids, Log log,
      {List<String> remove = const []}) async {
    if (ids.isEmpty && remove.isEmpty) return;
    await refreshPath();
    if (!await commandOk('code --version')) {
      log('VS Code komutu bulunamadı, eklentiler atlandı.');
      return;
    }
    log('VS Code eklentileri kuruluyor...');
    for (final e in ids) {
      final r = await run('code', ['--install-extension', e, '--force']);
      log(r.exitCode == 0 ? '  ✔ $e' : '  ✖ $e kurulamadı');
    }
    if (remove.isEmpty) return;
    // Aynı işi yapan iki eklenti kafa karıştırmasın: eskisini kaldır.
    final list = await run('code', ['--list-extensions']);
    final installed = (list.stdout as String)
        .split('\n')
        .map((x) => x.trim().toLowerCase())
        .toSet();
    for (final x in remove) {
      if (!installed.contains(x.toLowerCase())) continue;
      final r = await run('code', ['--uninstall-extension', x]);
      log(r.exitCode == 0
          ? '  ✔ $x kaldırıldı (yerine Microsoft Live Preview kullanılıyor)'
          : '  ✖ $x kaldırılamadı');
    }
  }

  // ----------------------------------------------------------------- docker

  static Future<InstallResult> installDocker(
      Catalog cat, Course course, LabPackage p, Log log) async {
    await refreshPath();
    if (!await dockerInstalled()) {
      log('✖ Docker bulunamadı. Önce Docker Desktop kurulmalı.');
      return InstallResult(false);
    }
    if (!await ensureDockerRunning(log)) {
      return InstallResult(false,
          help: helpFor(cat, 'error during connect docker daemon'));
    }

    final stack = stackDir(course, p);
    final ws = workspaceDir(course);
    await Directory(stack).create(recursive: true);
    await Directory(ws).create(recursive: true);

    await File('$stack${Os.sep}compose.yml')
        .writeAsString(await rootBundle.loadString(p.compose!));
    await File('$stack${Os.sep}.env')
        .writeAsString('WORKSPACE=${ws.replaceAll('\\', '/')}\n');
    if (p.buildContext != null) {
      final dir = Directory('$stack${Os.sep}php-web');
      await dir.create(recursive: true);
      await File('${dir.path}${Os.sep}Dockerfile')
          .writeAsString(await rootBundle.loadString(p.buildContext!));
    }
    await _seedWorkspace(course, ws);

    // Bu kursun eski konteynerleri portları tutuyor olabilir; önce onları durdur,
    // yoksa kendi kendimizle "çakışıyoruz" sanırız. Veriler (volume) korunur.
    await run('docker', ['compose', 'down'], cwd: stack);

    // Portlar doluysa otomatik olarak boş bir porta geçilir; böylece XAMPP, yerel
    // MySQL vb. kurulu olan öğrencilerde de kurulum sorunsuz tamamlanır.
    final portMap = <int, int>{};
    if (p.ports.isNotEmpty) {
      log('Portlar kontrol ediliyor (${p.ports.join(', ')})...');
      var conflicts = await findConflictingPorts(p.ports);
      if (conflicts.isNotEmpty) {
        // Portu MF Lab'ın kendi (örn. eski sürümden kalan) konteyneri tutuyorsa onu kapat.
        for (final port in conflicts) {
          await _stopOwnContainersOnPort(port, log);
        }
        conflicts = await findConflictingPorts(conflicts);
      }
      if (conflicts.isEmpty) {
        log('✔ Portlar boş ve kullanıma hazır.');
      } else {
        final taken = {...p.ports};
        for (final port in conflicts) {
          log('⚠ Port $port başka bir program tarafından kullanılıyor: '
              '${await describePortUsers(port)}');
          final free = await _findFreePort(taken);
          if (free == null) {
            log('✖ Boş bir port bulunamadı. Bilgisayarındaki sunucu programlarını (XAMPP, MySQL vb.) kapatıp tekrar dene.');
            return InstallResult(false, help: _portHelp(cat));
          }
          taken.add(free);
          portMap[port] = free;
          log('  → Sorun değil: bu ders için $port yerine $free portu kullanılacak.');
        }
      }
    }
    await _savePortMap(course.id, p.id, portMap);
    if (course.workspaceName == 'htdocs') {
      try {
        await File('$ws${Os.sep}.mflab-ports.json').writeAsString(
            jsonEncode(portMap.map((k, v) => MapEntry('$k', v))));
      } catch (_) {}
    }
    await File('$stack${Os.sep}compose.yml')
        .writeAsString(await _composeText(p, portMap));

    log('Konteynerler indiriliyor ve başlatılıyor (ilk seferde birkaç dakika sürebilir)...');
    var (code, out) =
        await stream('docker', ['compose', 'up', '-d'],
            cwd: stack, log: log, heartbeat: true);
    // Derleme yalnızca imaj indirilemediyse işe yarar; port/Docker hatasında boşa 10 dk harcar.
    final firstHelp = code != 0 ? helpFor(cat, out) : null;
    final buildCanHelp = firstHelp == null ||
        firstHelp.id == 'image' ||
        firstHelp.id == 'network';
    if (code != 0 && p.buildContext != null && buildCanHelp) {
      log('Hazır imaj indirilemedi, imaj bu bilgisayarda derleniyor (5-10 dk sürebilir)...');
      (code, out) = await stream(
          'docker', ['compose', 'up', '-d', '--build'],
          cwd: stack, log: log, heartbeat: true);
    }
    if (code != 0) {
      log('✖ Kurulum başarısız (kod $code).');
      return InstallResult(false, help: helpFor(cat, out));
    }
    if (p.buildContext != null) await ensurePatchedPhp(course, p, log);
    log('✔ ${p.name} hazır.');
    log(mapText(course.id, p.id, p.info));
    return InstallResult(true);
  }

  /// Docker gerektiren her işlemin başında çağrılır: Docker kurulu değilse ya da kapalıysa
  /// öğrenciye ne olduğunu açıkça söyler, kapalıysa kendisi açıp hazır olmasını bekler.
  /// `false` dönerse işlem yapılmaz (açıklama günlüğe yazılmıştır).
  static Future<bool> requireDocker(Log log) async {
    await refreshPath();
    if (!await dockerInstalled()) {
      log('✖ Docker bu bilgisayarda kurulu değil.');
      log('   → Docker olmadan bu işlem yapılamaz. "Dersler" sayfasından dersi seçip "Kur"a bas; '
          'Docker Desktop indirme sayfası açılır.');
      return false;
    }
    if (await dockerRunning()) return true;
    log('ℹ Docker şu an kapalı. MF Lab Docker\'ı senin yerine açıyor, hazır olunca işleme devam edecek...');
    return ensureDockerRunning(log);
  }

  /// Docker Desktop hiç açılmamışsa (ilk kurulum) ya da kapanmışsa açar ve motorun
  /// hazır olmasını bekler. İlk açılış WSL'i hazırladığı için 2-5 dk sürebilir; bu yüzden
  /// 6 dakika beklenir ve takılırsa öğrenciye ne yapacağı adım adım yazılır.
  static Future<bool> ensureDockerRunning(Log log) async {
    if (await dockerRunning()) return true;
    if (Os.isLinux) {
      log('✖ Docker motoru çalışmıyor.');
      log('   → Terminalde şunu çalıştır: sudo systemctl enable --now docker');
      log('   → "permission denied" görüyorsan kullanıcını docker grubuna ekle: '
          'sudo usermod -aG docker \$USER  (sonra oturumu kapatıp aç).');
      log('   → Docker kurulu değilse: https://docs.docker.com/engine/install/');
      return false;
    }
    log('Docker çalışmıyor, Docker Desktop açılıyor...');
    log('İlk kez açılıyorsa Docker kendini hazırlar; 2-5 dakika sürebilir, bekle.');
    await _tryStartDockerDesktop();
    for (var i = 0; i < 72; i++) {
      await Future.delayed(const Duration(seconds: 5));
      if (await dockerRunning()) {
        log('✔ Docker hazır.');
        return true;
      }
      final sec = (i + 1) * 5;
      if (sec == 30 && !await _dockerDesktopProcessAlive()) {
        log('Docker Desktop penceresi görünmedi, yeniden açılıyor...');
        await _tryStartDockerDesktop();
      } else if (sec == 120) {
        log('Docker hâlâ hazır değil, Docker Desktop yeniden başlatılıyor...');
        await _tryStartDockerDesktop(restart: true);
      } else if (sec == 90) {
        log('   → Docker Desktop penceresi açıldıysa: lisans sözleşmesi çıktıysa "Accept", '
            'giriş ekranı çıktıysa "Skip" de. Pencere yoksa saatin yanındaki balina simgesine bak.');
      } else if (sec % 30 == 0) {
        log('Docker bekleniyor... ($sec sn)');
      }
    }
    log('✖ Docker 6 dakikada hazır olmadı.');
    if (Os.isMac) {
      log('   → Docker Desktop penceresine bak: lisans sözleşmesi çıktıysa "Accept", yönetici '
          'parolası (ağ bileşenleri için) istenirse gir, giriş ekranı çıktıysa "Skip" de.');
      log('   → Yine de açılmazsa Docker uygulamasını Uygulamalar klasöründen elle aç, '
          'durum çubuğundaki balina simgesi sabitlenince tekrar "Kur"a bas.');
    } else if (await Preflight.rebootPending()) {
      log('   → Windows bir yeniden başlatma bekliyor (Docker/WSL yeni kurulduysa normaldir). '
          'Bilgisayarı yeniden başlat, sonra tekrar "Kur"a bas.');
    } else if (await Preflight.dockerUsersMissing()) {
      log('   → Windows hesabın "docker-users" grubunda görünmüyor. Docker kurulumundan sonra '
          'oturumu kapatıp yeniden aç (veya bilgisayarı yeniden başlat), sonra tekrar "Kur"a bas.');
    } else {
      log('   → Docker Desktop penceresine bak: lisans sözleşmesi çıktıysa "Accept", giriş '
          'ekranı çıktıysa "Skip" de. Sol altta yeşil "Engine running" yazınca tekrar "Kur"a bas.');
      log('   → Hâlâ açılmıyorsa bilgisayarı yeniden başlat; o da olmazsa Hakkında → '
          '"Sistem Durumunu Tara" ile ön kontrol yap.');
    }
    return false;
  }

  static Future<bool> _dockerDesktopProcessAlive() async {
    if (!Os.isWindows) {
      try {
        final r = await Process.run('pgrep', ['-x', 'Docker Desktop']);
        return r.exitCode == 0;
      } catch (_) {
        return false;
      }
    }
    try {
      final r = await Process.run(
          'tasklist', ['/FI', 'IMAGENAME eq Docker Desktop.exe', '/NH']);
      return (r.stdout as String).toLowerCase().contains('docker desktop.exe');
    } catch (_) {
      return false;
    }
  }

  /// Uzaktan kod çalıştırmaya izin veren CVE-2026-109618 / CVE-2026-109619 bu sürümde kapalı.
  static const minPhpVersion = '8.3.36';

  /// `a >= b` için noktalı sürüm karşılaştırması (8.3.9 < 8.3.36).
  static bool versionAtLeast(String a, String b) {
    List<int> parts(String v) => RegExp(r'\d+')
        .allMatches(v.split(RegExp(r'[-+~]')).first)
        .map((m) => int.parse(m.group(0)!))
        .toList();
    final x = parts(a), y = parts(b);
    for (var i = 0; i < y.length; i++) {
      final xi = i < x.length ? x[i] : 0;
      if (xi != y[i]) return xi > y[i];
    }
    return true;
  }

  static Future<String?> _containerPhpVersion(String stack) async {
    final r = await run(
        'docker', ['compose', 'exec', '-T', 'web', 'php', '-r', 'echo PHP_VERSION;'],
        cwd: stack);
    if (r.exitCode != 0) return null;
    final v = (r.stdout as String).trim();
    return RegExp(r'^\d+\.\d+\.\d+').hasMatch(v) ? v : null;
  }

  /// Çalışan web konteynerindeki PHP yamalı mı bakar; eskiyse yeni imajı çekip konteyneri yeniler.
  /// (`compose up` yerelde eski imaj varsa onu kullanır, bu yüzden elle yenilemek gerekir.)
  static Future<bool> ensurePatchedPhp(Course c, LabPackage p, Log log) async {
    final stack = stackDir(c, p);
    var v = await _containerPhpVersion(stack);
    if (v == null) return true; // okunamadı: kurulumu engelleme
    if (versionAtLeast(v, minPhpVersion)) {
      log('✔ PHP $v (güvenlik yaması içeriyor).');
      return true;
    }
    log('⚠ PHP $v güvenlik açığı içeriyor (en az $minPhpVersion gerekli). Yeni imaj indiriliyor...');
    await stream('docker', ['compose', 'pull', 'web'],
        cwd: stack, log: log, heartbeat: true);
    await stream('docker', ['compose', 'up', '-d', 'web'],
        cwd: stack, log: log, heartbeat: true);
    v = await _containerPhpVersion(stack);
    if (v != null && !versionAtLeast(v, minPhpVersion)) {
      log('Hazır imaj henüz güncel değil, imaj bu bilgisayarda derleniyor (5-10 dk sürebilir)...');
      await stream('docker', ['compose', 'build', '--pull', 'web'],
          cwd: stack, log: log, heartbeat: true);
      await stream('docker', ['compose', 'up', '-d', 'web'],
          cwd: stack, log: log, heartbeat: true);
      v = await _containerPhpVersion(stack);
    }
    final ok = v == null || versionAtLeast(v, minPhpVersion);
    log(ok
        ? '✔ PHP ${v ?? ''} güncellendi.'
        : '✖ PHP $v güncellenemedi. İnterneti kontrol edip tekrar dene.');
    return ok;
  }

  static Future<void> _tryStartDockerDesktop({bool restart = false}) async {
    if (Os.isMac) {
      await _launch('open', ['-a', 'Docker']);
      return;
    }
    if (!Os.isWindows) return;
    // `docker desktop start/restart` kapanmış ya da yarım kalmış motoru da toparlar.
    try {
      await Process.start('docker', ['desktop', restart ? 'restart' : 'start'],
          runInShell: true,
          environment: _env,
          mode: ProcessStartMode.detached);
    } catch (_) {}
    if (restart || await _dockerDesktopProcessAlive()) return;
    final candidates = [
      r'C:\Program Files\Docker\Docker\Docker Desktop.exe',
      '${Platform.environment['LOCALAPPDATA']}${Os.sep}Programs${Os.sep}Docker${Os.sep}Docker${Os.sep}Docker Desktop.exe',
    ];
    for (final c in candidates) {
      if (await File(c).exists()) {
        await Process.start(c, [], mode: ProcessStartMode.detached);
        return;
      }
    }
  }

  static const _portalVersion = 2;

  static Future<String> _readmeTemplate() =>
      rootBundle.loadString('assets/portal/README.template.md');

  /// Proje README'si: ne yapıldı, nasıl kuruldu, nasıl olmalı + adres ve veritabanı bilgisi.
  static Future<String> renderReadme(String name) async {
    final web = effectivePort(6380);
    final pma = effectivePort(6381);
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return (await _readmeTemplate())
        .replaceAll('{{NAME}}', name)
        .replaceAll('{{URL}}', 'http://localhost:$web/$name/')
        .replaceAll('{{PMA}}', 'http://localhost:$pma')
        .replaceAll('{{DATE}}',
            '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}');
  }

  /// Portalı (htdocs/index.php) yazar. Yoksa veya MF Lab'a ait eski bir sürümse güncellenir;
  /// öğrencinin kendi yazdığı bir ana sayfa varsa dokunulmaz.
  static Future<void> _writePortal(String ws) async {
    final f = File('$ws${Os.sep}index.php');
    if (await f.exists()) {
      final cur = await f.readAsString();
      final m = RegExp(r'mflab-portal:(\d+)').firstMatch(cur);
      final ours = m != null ||
          cur.contains('MF Lab çalışıyor!') ||
          cur.contains('Akıllı Öğrenci Çalışma Portalı') ||
          cur.contains('Akilli Ogrenci Calisma Portali');
      if (!ours) return;
      if (m != null && int.parse(m.group(1)!) >= _portalVersion) return;
    }
    final src = (await rootBundle.loadString('assets/portal/index.php'))
        .replaceFirst('@@README_TEMPLATE@@', await _readmeTemplate());
    await f.writeAsString(src);
  }

  static Future<void> _seedWorkspace(Course c, String ws) async {
    if (c.workspaceName == 'htdocs') {
      await _writePortal(ws);
    } else if (c.workspaceName == 'proje') {
      // Boş çalışma alanında öğrenciye hazır bir ilk proje aç.
      if (await Directory(ws).list().isEmpty) {
        await writeWebProject('$ws${Os.sep}ilk-proje', 'ilk-proje');
      }
    }
  }

  /// HTML/CSS/JS başlangıç projesi: index.html, style.css, script.js ve açıklamalı README.
  static Future<void> writeWebProject(String dir, String name) async {
    await Directory(dir).create(recursive: true);
    await File('$dir${Os.sep}index.html').writeAsString('''<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$name</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <header>
    <h1>$name</h1>
    <p>İlk sayfan hazır. <code>index.html</code> dosyasını değiştirip kaydet, önizleme kendiliğinden yenilenir.</p>
  </header>

  <main>
    <button id="selam">Bana tıkla</button>
    <p id="mesaj"></p>
  </main>

  <script src="script.js"></script>
</body>
</html>
''');
    await File('$dir${Os.sep}style.css').writeAsString('''body {
  font-family: "Segoe UI", Arial, sans-serif;
  max-width: 720px;
  margin: 40px auto;
  padding: 0 16px;
  line-height: 1.6;
  color: #1e293b;
  background: #f8fafc;
}

h1 {
  color: #0284c7;
}

button {
  padding: 10px 18px;
  border: none;
  border-radius: 8px;
  background: #0284c7;
  color: white;
  font-size: 16px;
  cursor: pointer;
}
''');
    await File('$dir${Os.sep}script.js').writeAsString('''// Sayfa yüklenince çalışır.
document.getElementById("selam").addEventListener("click", () => {
  document.getElementById("mesaj").textContent = "Merhaba! JavaScript çalışıyor 🎉";
});
''');
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final readme = (await rootBundle.loadString('assets/portal/README.web.template.md'))
        .replaceAll('{{NAME}}', name)
        .replaceAll('{{PATH}}', dir)
        .replaceAll('{{DATE}}',
            '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}');
    await File('$dir${Os.sep}README.md').writeAsString(readme);
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
          final isLaravel = await File('${entity.path}${Os.sep}public${Os.sep}index.php').exists();
          var entry = isLaravel ? 'public/' : '';
          if (!isLaravel) {
            var hasIndex = false;
            for (final n in ['index.php', 'index.html', 'index.htm']) {
              if (await File('${entity.path}${Os.sep}$n').exists()) hasIndex = true;
            }
            if (!hasIndex) {
              await for (final e in entity.list(followLinks: false)) {
                if (e is File &&
                    RegExp(r'\.(php|html?)$', caseSensitive: false)
                        .hasMatch(e.path)) {
                  entry = e.uri.pathSegments.last;
                  break;
                }
              }
            }
          }
          items.add(ProjectItem(
            name: name,
            path: entity.path,
            modified: stat.modified,
            isLaravel: isLaravel,
            entry: entry,
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
    final targetDir = Directory('$ws${Os.sep}$clean');
    if (await targetDir.exists()) {
      throw StateError('"$clean" adında bir proje zaten var.');
    }
    await targetDir.create(recursive: true);

    if (template == 'html') {
      await writeWebProject(targetDir.path, clean);
      log('✔ "$clean" projesi oluşturuldu.');
      return targetDir.path;
    } else if (template == 'crud') {
      final f = File('${targetDir.path}${Os.sep}index.php');
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
      if (!await requireDocker(log)) {
        await targetDir.delete();
        throw StateError('Docker çalışmıyor.');
      }
      log('Laravel projesi kuruluyor (birkaç dakika sürebilir)...');
      await targetDir.delete();
      final stack = '${courseDir(course)}${Os.sep}.stack${Os.sep}web2-stack';
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
      final f = File('${targetDir.path}${Os.sep}index.php');
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

    if (template != 'laravel') {
      await File('${targetDir.path}${Os.sep}README.md')
          .writeAsString(await renderReadme(clean));
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
        ? '$ws${Os.sep}$subprojectName'
        : ws;

    if (!await Directory(sourcePath).exists()) {
      throw StateError('Paketlenecek klasör bulunamadı: $sourcePath');
    }

    final tempDump = File('${Directory.systemTemp.path}${Os.sep}mflab_dump.sql');
    if (await tempDump.exists()) {
      try { await tempDump.delete(); } catch (_) {}
    }

    try {
      final stack = '${courseDir(course)}${Os.sep}.stack${Os.sep}web2-stack';
      final vtysStack = '${courseDir(course)}${Os.sep}.stack${Os.sep}vtys-stack';
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

    if (!Os.isWindows) {
      final outZip = '${await desktopDir()}${Os.sep}$zipBaseName';
      final stage = Directory(
          '${Directory.systemTemp.path}${Os.sep}mflab_zip_${DateTime.now().millisecondsSinceEpoch}');
      try {
        await copyDir(Directory(sourcePath), stage,
            exclude: {'vendor', 'node_modules', '.git'});
        if (await tempDump.exists()) {
          await tempDump.copy('${stage.path}${Os.sep}veritabani.sql');
        }
        if (!await zipDirPosix(stage.path, outZip)) {
          log('✖ ZIP oluşturulamadı. "zip" komutu kurulu mu? (Linux: sudo apt install zip)');
          throw StateError('Paketleme başarısız oldu.');
        }
      } finally {
        try {
          await stage.delete(recursive: true);
        } catch (_) {}
        if (await tempDump.exists()) {
          try { await tempDump.delete(); } catch (_) {}
        }
      }
      log('✔ Ödev paketi başarıyla Masaüstünüze oluşturuldu:');
      log('  $outZip');
      await revealFile(outZip);
      return outZip;
    }

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

    final tmpScript = File('${Directory.systemTemp.path}${Os.sep}mflab_zip.ps1');
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

    await revealFile(outZipPath);

    return outZipPath;
  }

  /// Örnek eğitim veritabanını Docker MariaDB'ye aktarır.
  static Future<void> loadSampleDatabase({
    required Course course,
    required String sampleKey,
    required Log log,
  }) async {
    log('\n=== 🗄️ Örnek Veritabanı Yükleniyor ($sampleKey) ===');
    if (!await requireDocker(log)) return;
    final stack = '${courseDir(course)}${Os.sep}.stack${Os.sep}web2-stack';
    final vtysStack = '${courseDir(course)}${Os.sep}.stack${Os.sep}vtys-stack';
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

    final tmpSql = File('${Directory.systemTemp.path}${Os.sep}sample_init.sql');
    await tmpSql.writeAsString(sql);

    final (code, err) = await dockerFromFile(
        ['compose', 'exec', '-T', 'db', 'mariadb', '-u', 'root', '-proot', 'mflab'],
        targetStack,
        tmpSql);

    try { await tmpSql.delete(); } catch (_) {}

    if (code == 0) {
      log('✔ "$dbName" tabloları ve örnek verileri "mflab" veritabanına başarıyla yüklendi.');
      log('phpMyAdmin üzerinden (http://localhost:${effectivePort(6381)}) tabloları inceleyebilirsiniz.');
    } else {
      log('✖ Veritabanı aktarımı başarısız oldu: $err');
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
      final port = effectivePort(entry.key);
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
    if (!await requireDocker(log)) return;
    log('Kullanılmayan önbellekler temizleniyor...');
    await stream('docker', ['system', 'prune', '-f'], log: log);
    log('✔ Docker önbellek temizliği tamamlandı.');
  }

  static Future<bool> isRunning(Course c, LabPackage p) async {
    final dir = stackDir(c, p);
    if (!await File('$dir${Os.sep}compose.yml').exists()) return false;
    final r = await run('docker', ['compose', 'ps', '--status', 'running', '-q'],
        cwd: dir);
    return r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty;
  }

  static Future<bool> isInstalled(Course c, LabPackage p) async =>
      File('${stackDir(c, p)}${Os.sep}compose.yml').exists();

  /// Paketin compose dosyası; çakışan portlar [portMap]'e göre değiştirilir. Tüm portlar yalnızca
  /// 127.0.0.1'e bağlanır: veritabanı şifreleri (root/root) ve oturumsuz yönetim ekranları
  /// aynı ağdaki başkalarına açılmasın.
  static Future<String> _composeText(LabPackage p, Map<int, int> portMap) async {
    var text = await rootBundle.loadString(p.compose!);
    portMap.forEach((from, to) {
      text = text.replaceAll('"127.0.0.1:$from:', '"127.0.0.1:$to:');
    });
    return text;
  }

  static Future<void> start(Course c, LabPackage p, Log log) async {
    if (c.workspaceName == 'htdocs') {
      try {
        await _writePortal(workspaceDir(c));
      } catch (_) {}
    }
    if (!await requireDocker(log)) return;
    // Eski sürümle kurulmuş yığınların compose dosyası da güvenli sürüme yükseltilir.
    try {
      await File('${stackDir(c, p)}${Os.sep}compose.yml').writeAsString(
          await _composeText(p, _portMaps['${c.id}/${p.id}'] ?? const {}));
    } catch (_) {}
    await stream('docker', ['compose', 'up', '-d'],
        cwd: stackDir(c, p), log: log);
    if (p.buildContext != null) await ensurePatchedPhp(c, p, log);
  }

  static Future<void> stop(Course c, LabPackage p, Log log) async {
    if (!await dockerRunning()) {
      log('ℹ Docker kapalı olduğu için servisler zaten durmuş durumda.');
      return;
    }
    await stream('docker', ['compose', 'stop'], cwd: stackDir(c, p), log: log);
  }

  /// Konteyner loglarını (son 60 satır) ekrana akıtır.
  static Future<void> showLogs(Course c, LabPackage p, Log log) async {
    log('\n=== ${p.name} Son Loglar ===');
    if (!await requireDocker(log)) return;
    await stream('docker', ['compose', 'logs', '--tail', '60'],
        cwd: stackDir(c, p), log: log);
  }

  /// Öğrencinin sistem durumunu (Docker, WSL, RAM, Disk, Araçlar) tarar.
  static Future<void> diagnoseSystem(Log log) async {
    await Preflight.run(log, needsDocker: true);
    final code = await commandOk('code --version');
    log(code ? '✔ VS Code: Kurulu' : 'ℹ VS Code: Bulunamadı (kodlama için önerilir).');
    final git = await commandOk('git --version');
    log(git ? '✔ Git: Kurulu' : 'ℹ Git: Bulunamadı (Laravel/Composer için önerilir).');
    log('===========================================\n'
        'İpucu: Sorun yaşarsan günlükteki "Yapay zekâya sor" düğmesini kullan ya da '
        '"Kopyala" ile hocana ilet.');
  }

  /// Konteynerleri siler; [removeVolumes] true ise veritabanı verileri de silinir.
  static Future<void> remove(Course c, LabPackage p, Log log,
      {bool removeVolumes = false}) async {
    if (!await dockerRunning()) {
      log('ℹ Docker kapalı; kaldırılacak çalışan konteyner yok.');
      return;
    }
    final args = ['compose', 'down'];
    if (removeVolumes) args.add('-v');
    await stream('docker', args, cwd: stackDir(c, p), log: log);
  }

  /// Masaüstündeki `MF Lab - ders adı` kısayol klasörünü siler.
  static Future<void> removeDesktopShortcuts(Course course, Log log) async {
    if (!Os.isWindows) {
      try {
        final dir = Directory(
            '${await desktopDir()}${Os.sep}MF Lab - ${course.name}');
        if (await dir.exists()) await dir.delete(recursive: true);
        log('✔ Masaüstündeki "${course.name}" kısayolları temizlendi.');
      } catch (_) {}
      return;
    }
    final sb = StringBuffer()
      ..writeln(r"$desktop = [Environment]::GetFolderPath('Desktop')")
      ..writeln(
          "\$dir = Join-Path \$desktop '${_ps('MF Lab - ${course.name}')}'")
      ..writeln(r'if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }');

    final tmp = File('${Directory.systemTemp.path}${Os.sep}mflab_rm_shortcuts.ps1');
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
    if (!await requireDocker(log)) return;
    final cmd = a.command.replaceAll('{name}', name ?? '');
    log('Çalıştırılıyor: $cmd');
    final (code, _) = await stream(
        'docker',
        ['compose', 'exec', '-T', a.service, 'sh', '-c', cmd],
        cwd: stackDir(c, p),
        log: log);
    if (code == 0 && a.afterInfo != null) {
      log('✔ ${mapText(c.id, p.id, a.afterInfo!.replaceAll('{name}', name ?? ''))}');
    } else if (code != 0) {
      log('✖ İşlem başarısız (kod $code).');
    }
  }

  // -------------------------------------------------------------- shortcuts

  static String _ps(String s) => s.replaceAll("'", "''");

  static Future<String> _ensureIcon() async {
    await Directory(AppConfig.baseDir).create(recursive: true);
    if (Os.isWindows) {
      final path = '${AppConfig.baseDir}${Os.sep}mflab.ico';
      final data = await rootBundle.load('assets/images/app_icon.ico');
      await File(path).writeAsBytes(data.buffer.asUint8List());
      return path;
    }
    final path = '${AppConfig.baseDir}${Os.sep}mflab.png';
    final data = await rootBundle.load('assets/images/logo.png');
    await File(path).writeAsBytes(data.buffer.asUint8List());
    return path;
  }

  /// Masaüstünde `MF Lab - ders adı` klasörü ve içinde kısayollar oluşturur.
  static Future<void> createShortcuts(
      Course course, List<LabPackage> pkgs, Log log) async {
    if (!Os.isWindows) return _createShortcutsPosix(course, pkgs, log);
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
      final codeExe = findVsCodeExe();
      if (codeExe != null) {
        sb.writeln(
            "Lnk 'VS Code ile aç' '${_ps(codeExe)}' '\"${_ps(ws)}\"' 1");
      } else {
        sb.writeln(
            "Lnk 'VS Code ile aç' 'cmd.exe' '/c code \"${_ps(ws)}\"' 7");
      }
    }
    for (final p in pkgs) {
      for (final l in p.links) {
        sb.writeln(
            "Set-Content -Path (Join-Path \$dir '${_ps(l.name)}.url') -Value \"[InternetShortcut]`nURL=${_ps(mapText(course.id, p.id, l.url))}`nIconFile=${_ps(icon)}`nIconIndex=0\"");
      }
    }

    final infoText = [
      '============================================================',
      '  MF Lab - Ders ve Çalışma Ortamı Bilgisi',
      '============================================================',
      'Ders           : ${_ps(course.name)} (${_ps(course.id)})',
      'MF Lab Sürümü  : v${AppConfig.appVersion}',
      'Kurulum Tarihi : \$(Get-Date -Format "dd.MM.yyyy HH:mm:ss")',
      'Geliştirici    : ${_ps(AppConfig.author)}',
      'GitHub         : ${_ps(AppConfig.repoUrl)}',
      '',
      'Çalışma Alanı  : ${_ps(ws)}',
      'Konteyner Dizini: ${_ps(courseDir(course))}${Os.sep}.stack',
      '',
      'HIZLI ERİŞİM & KULLANIM:',
      '1. "VS Code ile aç" kısayolu ile projeyi kodlamaya başlayabilirsin.',
      '2. "${course.workspaceName} klasörü" içinde oluşturduğun tüm kodlar saklanır.',
      '3. Servisleri başlatmak/durdurmak veya günlükleri görmek için',
      '   "MF Lab Yönetim Paneli" kısayolunu çalıştırabilirsin.',
      '============================================================',
    ].join('`r`n');

    sb.writeln(
        "Set-Content -Path (Join-Path \$dir 'MF_LAB_BILGI.txt') -Value \"$infoText\" -Encoding UTF8");

    try {
      final infoCourse = File('${courseDir(course)}${Os.sep}MF_LAB_BILGI.txt');
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

    final tmp = File('${Directory.systemTemp.path}${Os.sep}mflab_shortcuts.ps1');
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

  /// macOS / Linux: masaüstüne `MF Lab - ders adı` klasörü; içinde çalışma klasörü bağlantısı,
  /// tarayıcı bağlantıları ve bilgi dosyası. (Windows'taki .lnk/.url karşılığı.)
  static Future<void> _createShortcutsPosix(
      Course course, List<LabPackage> pkgs, Log log) async {
    try {
      final icon = await _ensureIcon();
      final ws = workspaceDir(course);
      await Directory(ws).create(recursive: true);
      final desktop = await desktopDir();
      final dir = Directory('$desktop${Os.sep}MF Lab - ${course.name}');
      await dir.create(recursive: true);

      final link = Link('${dir.path}${Os.sep}${course.workspaceName} klasörü');
      if (!await link.exists()) await link.create(ws);

      for (final p in pkgs) {
        for (final l in p.links) {
          final url = mapText(course.id, p.id, l.url);
          if (Os.isMac) {
            await File('${dir.path}${Os.sep}${l.name}.webloc').writeAsString(
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
                '<plist version="1.0"><dict><key>URL</key><string>$url</string>'
                '</dict></plist>\n');
          } else {
            final f = File('${dir.path}${Os.sep}${l.name}.desktop');
            await f.writeAsString('[Desktop Entry]\nType=Link\nName=${l.name}\n'
                'URL=$url\nIcon=$icon\n');
            await Process.run('chmod', ['+x', f.path]);
          }
        }
      }

      await File('${dir.path}${Os.sep}MF_LAB_BILGI.txt').writeAsString(
          'MF Lab - Ders ve Çalışma Ortamı Bilgisi\n'
          '============================================================\n'
          'Ders           : ${course.name} (${course.id})\n'
          'MF Lab Sürümü  : v${AppConfig.appVersion}\n'
          'Kurulum Tarihi : ${DateTime.now().toString().split('.').first}\n'
          'Geliştirici    : ${AppConfig.author}\n'
          'GitHub         : ${AppConfig.repoUrl}\n'
          'Çalışma Alanı  : $ws\n'
          'Konteyner Dizini: ${courseDir(course)}${Os.sep}.stack\n');
      await File('${courseDir(course)}${Os.sep}MF_LAB_BILGI.txt').writeAsString(
          'MF Lab - ${course.name}\nÇalışma Alanı: $ws\n');
      log('✔ Masaüstüne "MF Lab - ${course.name}" klasörü ve kısayollar eklendi.');
    } catch (e) {
      log('✖ Kısayollar oluşturulamadı: $e');
    }
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

  // -------------------------------------------------------- port eşlemeleri

  /// "dersId/paketId" -> {orijinal port -> kullanılan port}. Yalnızca çakışma olan portlar yer alır.
  static final Map<String, Map<int, int>> _portMaps = {};
  static String get _portMapFile => '${AppConfig.baseDir}${Os.sep}ports.json';

  static Future<void> loadPortMaps() async {
    _portMaps.clear();
    try {
      final f = File(_portMapFile);
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      j.forEach((k, v) {
        _portMaps[k] = (v as Map)
            .map((a, b) => MapEntry(int.parse(a.toString()), (b as num).toInt()));
      });
    } catch (_) {}
  }

  static Future<void> _savePortMap(
      String courseId, String pkgId, Map<int, int> map) async {
    final key = '$courseId/$pkgId';
    if (map.isEmpty) {
      _portMaps.remove(key);
    } else {
      _portMaps[key] = map;
    }
    try {
      await Directory(AppConfig.baseDir).create(recursive: true);
      await File(_portMapFile).writeAsString(jsonEncode(_portMaps
          .map((k, v) => MapEntry(k, v.map((a, b) => MapEntry('$a', b))))));
    } catch (_) {}
  }

  /// Metindeki ":6306" gibi port gösterimlerini, o ders için seçilen gerçek portlarla değiştirir.
  static String mapText(String courseId, String pkgId, String text) {
    final map = _portMaps['$courseId/$pkgId'];
    if (map == null || map.isEmpty) return text;
    var out = text;
    map.forEach((from, to) {
      out = out.replaceAllMapped(
          RegExp(':$from(?!\\d)'), (_) => ':$to');
    });
    return out;
  }

  /// Orijinal port için gerçekte kullanılan portu döner (eşleme yoksa aynısı).
  static int effectivePort(int original) {
    for (final m in _portMaps.values) {
      final v = m[original];
      if (v != null) return v;
    }
    return original;
  }

  static Future<int?> _findFreePort(Set<int> avoid) async {
    for (var port = 6400; port < 7000; port++) {
      if (avoid.contains(port)) continue;
      if ((await findConflictingPorts([port])).isEmpty) return port;
    }
    return null;
  }

  /// [port]'u yayınlayan, adı `mflab-` ile başlayan (yani MF Lab'ın açtığı) konteynerleri durdurur.
  /// Başkasının programlarına ve MF Lab'a ait olmayan konteynerlere dokunmaz.
  static Future<void> _stopOwnContainersOnPort(int port, Log log) async {
    try {
      final r = await run('docker',
          ['ps', '--filter', 'publish=$port', '--format', '{{.Names}}']);
      for (final raw in (r.stdout as String).split('\n')) {
        final name = raw.trim();
        if (!name.startsWith('mflab-')) continue;
        log('Port $port daha önce MF Lab tarafından açılmış ($name). Servis kapatılıyor...');
        final stop = await run('docker', ['stop', name]);
        log(stop.exitCode == 0
            ? '  ✔ $name durduruldu.'
            : '  ✖ $name durdurulamadı.');
      }
    } catch (_) {}
  }

  static HelpEntry? _portHelp(Catalog cat) =>
      cat.help.where((h) => h.id == 'port').firstOrNull;

  /// Portu hangi programın / konteynerin tuttuğunu insan okuyacak şekilde döner.
  static Future<String> describePortUsers(int port) async {
    final found = <String>[];
    try {
      if (!Os.isWindows) {
        final r = await run('lsof', ['-nP', '-iTCP:$port', '-sTCP:LISTEN', '-Fc']);
        found.addAll((r.stdout as String)
            .split('\n')
            .where((e) => e.startsWith('c'))
            .map((e) => e.substring(1).trim())
            .toSet());
      } else {
      final r = await run('powershell', [
        '-NoProfile',
        '-Command',
        "Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue "
            "| ForEach-Object { (Get-Process -Id \$_.OwningProcess -ErrorAction SilentlyContinue).ProcessName } "
            "| Sort-Object -Unique"
      ]);
      found.addAll((r.stdout as String)
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty));
      }
    } catch (_) {}
    try {
      final r = await run(
          'docker', ['ps', '--filter', 'publish=$port', '--format', '{{.Names}}']);
      for (final n in (r.stdout as String).split('\n')) {
        if (n.trim().isNotEmpty) found.add('Docker konteyneri: ${n.trim()}');
      }
    } catch (_) {}
    return found.isEmpty
        ? 'kullanan program tespit edilemedi (yönetici izni gerekebilir)'
        : found.join(', ');
  }

  static Future<void> openContainerTerminal(
      Course course, LabPackage pkg, {String service = 'web'}) async {
    final stack = stackDir(course, pkg);
    final compose = '$stack${Os.sep}compose.yml';
    if (!Os.isWindows) {
      final sh = 'echo "MF Lab: ${pkg.name} ($service). Çıkmak için: exit"; '
          'docker compose -f "$compose" exec -it $service bash || '
          'docker compose -f "$compose" exec -it $service sh; exec \$SHELL';
      if (Os.isMac) {
        final esc = sh.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
        await _launch('osascript', [
          '-e',
          'tell application "Terminal" to activate',
          '-e',
          'tell application "Terminal" to do script "$esc"',
        ]);
        return;
      }
      for (final t in [
        ['x-terminal-emulator', '-e'],
        ['gnome-terminal', '--'],
        ['konsole', '-e'],
        ['xfce4-terminal', '-e'],
        ['xterm', '-e'],
      ]) {
        if (_exe(t[0]) == t[0] && !File(t[0]).existsSync()) {
          // PATH'te bulunamadıysa sıradakini dene
          final found = (_env?['PATH'] ?? '')
              .split(':')
              .any((d) => File('$d/${t[0]}').existsSync());
          if (!found) continue;
        }
        await _launch(t[0], [...t.skip(1), 'bash', '-lc', sh]);
        return;
      }
      return;
    }
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
    ], runInShell: true, environment: _env);
  }

  static Future<String?> pickFile({
    required String title,
    required String filterName,
    required String extension,
  }) async {
    if (!Os.isWindows) {
      try {
        if (Os.isMac) {
          final r = await run('osascript', [
            '-e',
            'POSIX path of (choose file with prompt "${title.replaceAll('"', '')}")'
          ]);
          final p = (r.stdout as String).trim();
          return r.exitCode == 0 && p.isNotEmpty ? p : null;
        }
        for (final cmd in [
          ['zenity', '--file-selection', '--title=$title'],
          ['kdialog', '--getopenfilename', Os.home, '*.$extension'],
        ]) {
          final found = (_env?['PATH'] ?? Platform.environment['PATH'] ?? '')
              .split(':')
              .any((d) => File('$d/${cmd[0]}').existsSync());
          if (!found) continue;
          final r = await run(cmd[0], cmd.skip(1).toList());
          final p = (r.stdout as String).trim();
          return r.exitCode == 0 && p.isNotEmpty ? p : null;
        }
      } catch (_) {}
      return null;
    }
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

  static Future<String?> backupDatabase(Course c, LabPackage p, Log log) async {
    final stack = stackDir(c, p);
    final now = DateTime.now();
    final timeStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final fileName = 'mflab_${c.id}_yedek_$timeStr.sql';

    final desktop = await desktopDir();
    final outPath = '$desktop${Os.sep}$fileName';

    log('\n=== Veritabanı Yedeği Alınıyor ===');
    if (!await requireDocker(log)) return null;
    log('Hedef dosya: $outPath');

    final args = p.id == 'web2-stack'
        ? ['compose', 'exec', '-T', 'db', 'mariadb-dump', '-uroot', '-proot', '--all-databases']
        : ['compose', 'exec', '-T', 'postgres', 'pg_dumpall', '-U', 'postgres'];

    if (await dockerToFile(args, stack, File(outPath)) &&
        await File(outPath).exists()) {
      log('✔ Veritabanı yedeği masaüstüne kaydedildi: $fileName');
      return outPath;
    } else {
      log('✖ Yedek alınamadı. Servis çalışıyor mu kontrol et.');
      return null;
    }
  }

  static Future<bool> importDatabase(
      Course c, LabPackage p, String sqlFilePath, Log log) async {
    log('\n=== Veritabanı İçe Aktarılıyor ===');
    if (!await requireDocker(log)) return false;
    log('Kaynak dosya: $sqlFilePath');
    final stack = stackDir(c, p);

    final args = p.id == 'web2-stack'
        ? ['compose', 'exec', '-T', 'db', 'mariadb', '-uroot', '-proot', 'mflab']
        : ['compose', 'exec', '-T', 'postgres', 'psql', '-U', 'postgres', 'postgres'];

    final (code, err) = await dockerFromFile(args, stack, File(sqlFilePath));
    if (code == 0) {
      log('✔ .sql dosyası veritabanına başarıyla aktarıldı.');
      return true;
    } else {
      log('✖ İçe aktarma sırasında hata oluştu: $err');
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

    final desktop = await desktopDir();
    final outZip = '$desktop${Os.sep}$zipName';

    final tempDir = Directory('${Directory.systemTemp.path}${Os.sep}mflab_hw_${DateTime.now().millisecondsSinceEpoch}');
    await tempDir.create(recursive: true);

    try {
      // 1. Öğrenci bilgi dosyası
      final infoFile = File('${tempDir.path}${Os.sep}OGRENCI_BILGI.txt');
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
          ? Directory('${ws.path}${Os.sep}$subprojectName')
          : ws;
      if (await sourceDir.exists()) {
        log('Proje kodları kopyalanıyor (${subprojectName ?? "Tüm Projeler"})...');
        if (!Os.isWindows) {
          await copyDir(sourceDir, Directory('${tempDir.path}${Os.sep}kodlar'));
        } else {
        final copyScript = 'Copy-Item -Path "${_ps(sourceDir.path)}${Os.sep}*" -Destination "${_ps(tempDir.path)}${Os.sep}kodlar" -Recurse -Force';
        await Directory('${tempDir.path}${Os.sep}kodlar').create(recursive: true);
        await run('powershell', ['-NoProfile', '-Command', copyScript]);
        }
      }

      // 3. Veritabanı varsa yedeğini al
      for (final id in course.packages) {
        final p = catalog.packages[id];
        if (p != null && p.isDocker) {
          final isUp = await isRunning(course, p);
          if (isUp) {
            log('Veritabanı yedeği pakete ekleniyor...');
            final sqlFile = '${tempDir.path}${Os.sep}veritabani.sql';
            final stack = stackDir(course, p);
            await dockerToFile(
                p.id == 'web2-stack'
                    ? ['compose', 'exec', '-T', 'db', 'mariadb-dump', '-uroot', '-proot', '--all-databases']
                    : ['compose', 'exec', '-T', 'postgres', 'pg_dumpall', '-U', 'postgres'],
                stack,
                File(sqlFile));
          }
        }
      }

      // 4. Zip oluştur
      log('Zip arşivi oluşturuluyor...');
      if (!Os.isWindows) {
        if (await zipDirPosix(tempDir.path, outZip)) {
          log('🎉 Ödev paketi masaüstünde hazır: $zipName');
          await revealFile(outZip);
          return outZip;
        }
        log('✖ Zip oluşturulamadı. "zip" komutu kurulu mu? (Linux: sudo apt install zip)');
        return null;
      }
      final zipScript = 'if (Test-Path "${_ps(outZip)}") { Remove-Item -Force "${_ps(outZip)}" }; '
          'Compress-Archive -Path "${_ps(tempDir.path)}${Os.sep}*" -DestinationPath "${_ps(outZip)}" -Force';
      final r = await run('powershell', ['-NoProfile', '-Command', zipScript]);
      if (r.exitCode == 0 && await File(outZip).exists()) {
        log('🎉 Ödev paketi masaüstünde hazır: $zipName');
        await revealFile(outZip);
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
    if (!await requireDocker(log)) return false;
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
