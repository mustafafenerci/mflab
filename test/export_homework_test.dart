import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mflab/engine.dart';
import 'package:mflab/models.dart';

void main() {
  LabPackage dbPkg() =>
      LabPackage(const {'id': 'vtys-stack', 'type': 'docker'});

  Course exportCourse() => Course(const {
    'id': 'zz-export-dump-test',
    'name': 'Export Dump Test',
    'description': 'test',
    'workspaceName': 'sql',
    'packages': ['vtys-stack'],
  });

  Catalog exportCatalog() =>
      Catalog({'vtys-stack': dbPkg()}, const [], const []);

  Future<String?> runExport({
    required Future<bool> Function(List<String>, String, File) dumpToFile,
    required List<String> logs,
  }) => Engine.exportHomeworkZip(
    course: exportCourse(),
    catalog: exportCatalog(),
    studentName: 'Test Ogrenci',
    studentNumber: '0000',
    log: logs.add,
    isPackageRunning: (c, p) async => true,
    dumpToFile: dumpToFile,
  );

  test('dump komutu başarısızsa ZIP oluşturulmaz', () async {
    final logs = <String>[];
    final result = await runExport(
      logs: logs,
      dumpToFile: (args, cwd, out) async => false,
    );
    expect(result, isNull);
    final text = logs.join('\n');
    expect(text, contains('Veritabanı yedeği alınamadı'));
    expect(text, isNot(contains('Ödev paketi masaüstünde hazır')));
  });

  test('dump başarılı ama dosya boşsa ZIP oluşturulmaz', () async {
    final logs = <String>[];
    final result = await runExport(
      logs: logs,
      dumpToFile: (args, cwd, out) async {
        await out.writeAsString('');
        return true;
      },
    );
    expect(result, isNull);
    expect(logs.join('\n'), contains('Veritabanı yedeği alınamadı'));
  });

  test('dump başarılı ama dosya oluşmadıysa ZIP oluşturulmaz', () async {
    final logs = <String>[];
    final result = await runExport(
      logs: logs,
      dumpToFile: (args, cwd, out) async => true,
    );
    expect(result, isNull);
    expect(logs.join('\n'), contains('Veritabanı yedeği alınamadı'));
  });
}
