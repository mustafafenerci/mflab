import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mflab/engine.dart';

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
}

