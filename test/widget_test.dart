import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mflab/engine.dart';
import 'package:mflab/models.dart';
import 'package:mflab/settings.dart';
import 'package:mflab/ui/widgets.dart';

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
}
