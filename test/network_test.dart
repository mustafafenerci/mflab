// Gerçek ağ ve sistem testleri. Bu dosyada testWidgets YOK: Flutter'ın test bağlamı
// açılırsa tüm HTTP istekleri sahte 400 yanıtı döner ve bu testler anlamsızlaşır.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mflab/preflight.dart';
import 'package:mflab/updater.dart';

void main() {
  // Flutter test ortamı HTTP'yi sahte yanıtlarla değiştirir; gerçek ağı kullan.
  var online = true;
  setUpAll(() async {
    HttpOverrides.global = null;
    // Bazı bilgisayarlarda güvenlik duvarı test sürecinin internete çıkmasını engeller.
    try {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      await (await c.getUrl(Uri.parse('https://github.com'))).close();
      c.close(force: true);
    } catch (_) {
      online = false;
    }
  });

  test('ön kontrol bu bilgisayarda gerçek bilgi topluyor', () async {
    final f = await Preflight.gather(needsDocker: true);
    expect(f.windowsBuild, isNotNull);
    expect(f.ramGb, greaterThan(0));
    expect(f.freeDiskGb, greaterThan(0));
    // ignore: avoid_print
    print('build=${f.windowsBuild} ram=${f.ramGb} disk=${f.freeDiskGb} virt=${f.virtualization} '
        'hyper=${f.hypervisor} admin=${f.isAdmin} reboot=${f.rebootPending} wsl=${f.wslOk} '
        'docker=${f.dockerInstalled}/${f.dockerRunning}/${f.dockerOs} net=${f.network}');
    // curl.exe ile ikinci kontrol sayesinde, test süreci engelli olsa bile erişim doğru ölçülmeli.
    expect(f.network['ghcr.io'], isNull, reason: 'ghcr.io erişilebilir olmalı');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('gerçek v1.1.6 kurulum dosyası indirilir ve SHA-256 doğrulanır', () async {
    if (!online) {
      markTestSkipped('Bu bilgisayarda test sürecinin internet erişimi engelli (güvenlik duvarı).');
      return;
    }
    var last = 0.0;
    final f = await Updater.download('1.1.6', onProgress: (p) => last = p);
    expect(await f.length(), greaterThan(1000000));
    expect(last, closeTo(1.0, 0.001));
    expect(await Updater.verify('1.1.6', f), isTrue);
    await f.delete();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
