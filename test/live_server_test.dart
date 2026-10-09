// Canlı önizleme sunucusu testleri. testWidgets kullanılmaz (Flutter'ın test bağlamı HTTP'yi sahteler).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mflab/live_server.dart';

void main() {
  late Directory dir;
  late LiveServer server;

  setUpAll(() async {
    HttpOverrides.global = null;
    dir = await Directory.systemTemp.createTemp('mflab_live_');
    await File('${dir.path}/index.html')
        .writeAsString('<html><body><h1>Merhaba</h1></body></html>');
    await File('${dir.path}/style.css').writeAsString('body{color:red}');
    await Directory('${dir.path}/alt').create();
    await File('${dir.path}/alt/index.html').writeAsString('<p>alt sayfa</p>');
    server = await LiveServer.open(dir.path);
  });

  tearDownAll(() async {
    await server.close();
    await dir.delete(recursive: true);
  });

  Future<HttpClientResponse> get(String path, {bool follow = true}) async {
    final c = HttpClient();
    final req = await c.getUrl(server.url.resolve(path));
    req.followRedirects = follow;
    return req.close();
  }

  test('aynı klasör için aynı sunucu döner, port 5500 civarında', () async {
    expect(identical(await LiveServer.open(dir.path), server), isTrue);
    expect(server.port, greaterThan(0));
  });

  test('index.html sunulur ve otomatik yenileme betiği eklenir', () async {
    final res = await get('/');
    final body = await res.transform(utf8.decoder).join();
    expect(res.statusCode, 200);
    expect(res.headers.contentType?.mimeType, 'text/html');
    expect(body, contains('<h1>Merhaba</h1>'));
    expect(body, contains(LiveServer.reloadPath));
    expect(body.indexOf(LiveServer.reloadPath), lessThan(body.indexOf('</body>')));
  });

  test('CSS doğru türle sunulur, alt klasör / ile yönlenir', () async {
    final css = await get('/style.css');
    expect(css.headers.contentType?.mimeType, 'text/css');
    await css.drain<void>();
    final redirect = await get('/alt', follow: false);
    expect(redirect.statusCode, HttpStatus.movedTemporarily);
    await redirect.drain<void>();
    final alt = await get('/alt/');
    expect(await alt.transform(utf8.decoder).join(), contains('alt sayfa'));
  });

  test('klasör dışına çıkma engellenir, olmayan sayfa 404', () async {
    Future<String> raw(String path) async {
      final sock = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
      sock.write('GET $path HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n');
      return utf8.decoder.bind(sock).join();
    }

    // "/../" parçalarını Dart'ın sunucusu zaten temizler; klasör içinde kalır ve bulunamaz.
    expect(await raw('/../../Windows/win.ini'), isNot(startsWith('HTTP/1.1 200')));
    // Windows'a özgü ters eğik çizgili kaçış (%5c) temizlenmez; MF Lab'ın koruması engellemeli.
    final r = await raw('/..%5c..%5c..%5cWindows%5cwin.ini');
    expect(r, startsWith('HTTP/1.1 403'));
    expect(r, isNot(contains('[fonts]')));
    final missing = await get('/yok.html');
    expect(missing.statusCode, HttpStatus.notFound);
    expect(await missing.transform(utf8.decoder).join(), contains('index.html'));
  });

  test('dosya kaydedilince tarayıcıya "yenile" sinyali gider', () async {
    final res = await get(LiveServer.reloadPath);
    expect(res.headers.contentType?.mimeType, 'text/event-stream');
    final got = Completer<void>();
    final sub = res.transform(utf8.decoder).listen((chunk) {
      if (chunk.contains('data: yenile') && !got.isCompleted) got.complete();
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await File('${dir.path}/style.css').writeAsString('body{color:blue}');
    await got.future.timeout(const Duration(seconds: 5));
    await sub.cancel();
  });
}
