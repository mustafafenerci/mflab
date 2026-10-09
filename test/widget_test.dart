import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mflab/config.dart';
import 'package:mflab/engine.dart';
import 'package:mflab/models.dart';
import 'package:mflab/preflight.dart';
import 'package:mflab/settings.dart';
import 'package:mflab/ui/widgets.dart';
import 'package:mflab/updater.dart';

void main() {
  test('PowerShell process encoding and argument passing', () async {
    final tmp = File('${Directory.systemTemp.path}\\test_exec.ps1');
    await tmp.writeAsString('Write-Output "FINISHED_OK"');

    final r1 = await Process.run(
      'powershell',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', tmp.path],
      runInShell: true,
      stdoutEncoding: systemEncoding,
      stderrEncoding: systemEncoding,
    );

    expect(r1.exitCode, 0);
    expect((r1.stdout as String).contains('FINISHED_OK'), isTrue);
    if (await tmp.exists()) await tmp.delete();
  });

  test('Shortcut creation script executes without syntax error', () async {
    final desktop = Platform.environment['USERPROFILE']! + r'\Desktop';
    final courseName = 'Web Tasarımı';
    final dir = '$desktop\\MF Lab - $courseName';

    final sb = StringBuffer()
      ..writeln(r"$desktop = [Environment]::GetFolderPath('Desktop')")
      ..writeln("\$dir = Join-Path \$desktop 'MF Lab - $courseName'")
      ..writeln(r'New-Item -ItemType Directory -Force $dir | Out-Null')
      ..writeln(r'$sh = New-Object -ComObject WScript.Shell')
      ..writeln(r'function Lnk($name, $target, $arguments, $style) {')
      ..writeln(r'  $l = $sh.CreateShortcut((Join-Path $dir ($name + ".lnk")))')
      ..writeln(r'  $l.TargetPath = $target')
      ..writeln(r'  if ($arguments) { $l.Arguments = $arguments }')
      ..writeln(r'  if ($style) { $l.WindowStyle = $style }')
      ..writeln(r'  $l.Save()')
      ..writeln(r'}')
      ..writeln("Lnk 'proje klasörü' 'C:\\temp' \$null \$null");

    final tmp = File('${Directory.systemTemp.path}\\mflab_test_shortcuts.ps1');
    await tmp.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(sb.toString())]);

    final r = await Process.run(
      'powershell',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', tmp.path],
      runInShell: true,
      stdoutEncoding: systemEncoding,
      stderrEncoding: systemEncoding,
    );

    expect(r.exitCode, 0);
    expect(await Directory(dir).exists(), isTrue);

    if (await Directory(dir).exists()) {
      await Directory(dir).delete(recursive: true);
    }
    if (await tmp.exists()) {
      await tmp.delete();
    }
  });

  test('semver comparison', () {
    expect(Engine.isNewer('1.0.1', '1.0.0'), isTrue);
    expect(Engine.isNewer('v1.2.0', '1.1.9'), isTrue);
    expect(Engine.isNewer('1.0.0', '1.0.0'), isFalse);
    expect(Engine.isNewer('0.9.9', '1.0.0'), isFalse);
  });

  test('AppSettings load, save, and restore', () async {
    final settings = AppSettings(
      themeMode: ThemeMode.dark,
      studentName: 'Mustafa Fenerci',
      studentNumber: '123456789',
      lastCourseId: 'web-programlama-2',
      courseInstallDates: {'web-programlama-2': '2026-10-09T05:00:00'},
    );

    await settings.save();
    expect(await File(AppSettings.filePath).exists(), isTrue);

    final restored = await AppSettings.load();
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.studentName, 'Mustafa Fenerci');
    expect(restored.studentNumber, '123456789');
    expect(restored.lastCourseId, 'web-programlama-2');
    expect(restored.courseInstallDates['web-programlama-2'], '2026-10-09T05:00:00');
  });

  test('ProjectItem creation and properties', () {
    final now = DateTime.now();
    final p = ProjectItem(
      name: 'hafta1_giris',
      path: 'C:\\MFLab\\htdocs\\hafta1_giris',
      modified: now,
      isLaravel: false,
    );
    expect(p.name, 'hafta1_giris');
    expect(p.isLaravel, isFalse);
    expect(p.modified, now);

    final laravel = ProjectItem(
      name: 'blog_projesi',
      path: 'C:\\MFLab\\htdocs\\blog_projesi',
      modified: now,
      isLaravel: true,
    );
    expect(laravel.isLaravel, isTrue);
  });

  testWidgets('HoverHint açıklaması ancak ~4 sn bekleyince görünür',
      (tester) async {
    const msg = 'Bu düğmenin uzun açıklaması';
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: HoverHint(message: msg, child: Text('Düğme')),
        ),
      ),
    ));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('Düğme')));

    await tester.pump(const Duration(seconds: 2));
    expect(find.text(msg), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text(msg), findsOneWidget);
  });

  test('refreshPath: sonradan kurulan VS Code uygulama yeniden açılmadan bulunur',
      () async {
    await Engine.refreshPath();
    final exe = Engine.findVsCodeExe();
    if (exe == null) return; // Bu bilgisayarda VS Code yok; denenecek bir şey yok.
    final r = await Engine.run('code', ['--version']);
    expect(r.exitCode, 0);
  });

  group('Ön kontrol değerlendirmesi', () {
    SystemFacts good({
      int build = 22631,
      double ram = 16,
      double disk = 80,
      bool? virt = true,
      bool hyper = false,
      bool reboot = false,
      bool dockerInstalled = true,
      bool dockerRunning = true,
      String? dockerOs = 'linux',
      bool? admin = true,
      Map<String, String?>? net,
    }) =>
        SystemFacts(
          windowsBuild: build,
          ramGb: ram,
          freeDiskGb: disk,
          virtualization: virt,
          hypervisor: hyper,
          isAdmin: admin,
          rebootPending: reboot,
          wslOk: true,
          dockerInstalled: dockerInstalled,
          dockerRunning: dockerRunning,
          dockerOs: dockerOs,
          network: net ?? {'registry-1.docker.io': null, 'ghcr.io': null},
        );

    List<CheckResult> fails(SystemFacts f) => Preflight.evaluate(f, needsDocker: true)
        .where((c) => c.level == CheckLevel.fail)
        .toList();

    test('hazır bilgisayarda engelleyici sorun yok', () {
      expect(fails(good()), isEmpty);
    });
    test('BIOS sanallaştırması kapalı ve hipervizör yoksa engeller', () {
      final f = fails(good(virt: false, dockerRunning: false, dockerOs: null));
      expect(f.map((c) => c.title), contains('Sanallaştırma'));
    });
    test('eski Windows engeller', () {
      expect(fails(good(build: 18363)).map((c) => c.title), contains('Windows sürümü'));
    });
    test('Docker kurulu ama açılmıyor ve yeniden başlatma bekleniyorsa engeller', () {
      final f = fails(good(reboot: true, dockerRunning: false, dockerOs: null));
      expect(f.map((c) => c.title), contains('Yeniden başlatma'));
    });
    test('Windows konteyner modu engeller', () {
      expect(fails(good(dockerOs: 'windows')).map((c) => c.title), contains('Docker modu'));
    });
    test('yönetici olmayan hesapta Docker yoksa engeller', () {
      final f = fails(good(dockerInstalled: false, dockerRunning: false, dockerOs: null, admin: false));
      expect(f.map((c) => c.title), contains('Docker Desktop'));
    });
    test('6 GB RAM ve sertifika sorunu yalnızca uyarıdır', () {
      final r = Preflight.evaluate(
          good(ram: 6, net: {'registry-1.docker.io': 'sertifika', 'ghcr.io': null}),
          needsDocker: true);
      expect(r.where((c) => c.level == CheckLevel.fail), isEmpty);
      expect(r.where((c) => c.level == CheckLevel.warn).length, 2);
    });
    test('Docker gerekmeyen derste yalnızca klasör ve disk kontrol edilir', () {
      final r = Preflight.evaluate(SystemFacts(freeDiskGb: 50), needsDocker: false);
      expect(r.map((c) => c.title), ['Çalışma klasörü', 'Disk alanı']);
    });
  });

  test('hata açıklamaları doğru eşleşir', () {
    final help = (jsonDecode(File('assets/help/errors.json').readAsStringSync()) as List)
        .map((h) => HelpEntry(h as Map<String, dynamic>))
        .toList();
    final cat = Catalog({}, [], help);
    String? id(String out) => Engine.helpFor(cat, out)?.id;
    expect(id('toomanyrequests: You have reached your pull rate limit.'), 'ratelimit');
    expect(id('Get "https://ghcr.io/v2/": tls: failed to verify certificate: x509: certificate signed by unknown authority'),
        'certificate');
    expect(id('image operating system "linux" cannot be used on this platform'), 'wincontainers');
    expect(id('Error response from daemon: ports are not available: exposing port TCP 0.0.0.0:3306'), 'port');
    expect(id('error during connect: open //./pipe/docker_engine'), 'docker');
  });


  group('Kullanıcıya özel çalışma klasörü', () {
    test('kullanıcı adı klasör adına uygun hale gelir', () {
      expect(AppConfig.safeUserName('Ömer Şahin'), 'Omer_Sahin');
      expect(AppConfig.safeUserName('MF-KUN'), 'MF-KUN');
      expect(AppConfig.safeUserName('  '), 'ogrenci');
      expect(AppConfig.safeUserName('ığüşöç'), 'igusoc');
    });
    const root = r'C:\MFLab';
    test('eski sürüm verisi varsa ilk kullanıcı taşımadan kökte devam eder', () {
      expect(AppConfig.resolveBaseDir(root: root, user: 'ali', legacyData: true), root);
    });
    test('kökün sahibi başka biriyse kullanıcıya ayrı klasör verilir', () {
      expect(AppConfig.resolveBaseDir(root: root, user: 'ayse', legacyData: false, owner: 'ali'),
          '$root\\ayse');
      expect(AppConfig.resolveBaseDir(root: root, user: 'ALI', legacyData: false, owner: 'ali'), root);
    });
    test('yeni kurulumda her kullanıcı kendi klasörünü kullanır', () {
      expect(AppConfig.resolveBaseDir(root: root, user: 'ali', legacyData: false), '$root\\ali');
    });
  });

  group('Uygulama içi güncelleme', () {
    test('indirme adresi ve özet okuma', () {
      expect(Updater.downloadUrl('1.2.3'),
          'https://github.com/mustafafenerci/mflab/releases/download/v1.2.3/MFLab-Setup-v1.2.3.exe');
      expect(Updater.parseChecksum('${'A' * 64}  MFLab-Setup-v1.2.3.exe\r\n'), 'a' * 64);
      expect(Updater.parseChecksum('bozuk'), isNull);
    });
  });

  test('web projesi şablonu: dosyalar ve doldurulmuş README oluşur', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = await Directory.systemTemp.createTemp('mflab_web_');
    final dir = '${tmp.path}/hafta1';
    await Engine.writeWebProject(dir, 'hafta1');
    for (final f in ['index.html', 'style.css', 'script.js', 'README.md']) {
      expect(File('$dir/$f').existsSync(), isTrue, reason: f);
    }
    final html = File('$dir/index.html').readAsStringSync();
    expect(html, contains('href="style.css"'));
    expect(html, contains('src="script.js"'));
    final readme = File('$dir/README.md').readAsStringSync();
    expect(readme, startsWith('# hafta1'));
    expect(readme, isNot(contains('{{')));
    await tmp.delete(recursive: true);
  });
}
