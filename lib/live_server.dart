import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Live Server benzeri, yalnızca bu bilgisayardan erişilebilen küçük bir önizleme sunucusu.
/// Her proje klasörü için ayrı bir adres açar; klasördeki bir dosya kaydedilince
/// tarayıcıdaki sayfa kendiliğinden yenilenir. VS Code'a veya bir eklentiye ihtiyaç duymaz.
class LiveServer {
  LiveServer._(this.root, this._server);

  final String root;
  final HttpServer _server;
  final _clients = <HttpResponse>{};
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _debounce;

  static final Map<String, LiveServer> _byRoot = {};

  int get port => _server.port;
  Uri get url => Uri.parse('http://127.0.0.1:$port/');

  static const reloadPath = '/__mflab_canli_yenile';
  static const _reloadScript = '<script>(function(){try{var s=new EventSource("$reloadPath");'
      's.onmessage=function(){location.reload();};}catch(e){}})();</script>';

  static const _mime = {
    'html': 'text/html; charset=utf-8',
    'htm': 'text/html; charset=utf-8',
    'css': 'text/css; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'mjs': 'text/javascript; charset=utf-8',
    'json': 'application/json; charset=utf-8',
    'txt': 'text/plain; charset=utf-8',
    'md': 'text/plain; charset=utf-8',
    'svg': 'image/svg+xml',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'ico': 'image/x-icon',
    'mp3': 'audio/mpeg',
    'mp4': 'video/mp4',
    'webm': 'video/webm',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    'ttf': 'font/ttf',
    'pdf': 'application/pdf',
  };

  /// [root] klasörü için sunucuyu başlatır (zaten açıksa aynısını döner).
  static Future<LiveServer> open(String root) async {
    final key = root.toLowerCase();
    final existing = _byRoot[key];
    if (existing != null) return existing;
    HttpServer? server;
    for (var port = 5500; port < 5600 && server == null; port++) {
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      } catch (_) {}
    }
    server ??= await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final s = LiveServer._(root, server);
    _byRoot[key] = s;
    s._listen();
    return s;
  }

  /// Bu klasör için önizleme açık mı?
  static LiveServer? running(String root) => _byRoot[root.toLowerCase()];

  Future<void> close() async {
    _byRoot.remove(root.toLowerCase());
    _debounce?.cancel();
    await _watch?.cancel();
    for (final c in _clients.toList()) {
      try {
        await c.close();
      } catch (_) {}
    }
    await _server.close(force: true);
  }

  void _listen() {
    _server.listen(_handle);
    try {
      _watch = Directory(root).watch(recursive: true).listen((_) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 200), _notify);
      });
    } catch (_) {}
  }

  void _notify() {
    for (final c in _clients.toList()) {
      try {
        c.write('data: yenile\n\n');
        c.flush();
      } catch (_) {
        _clients.remove(c);
      }
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final path = Uri.decodeComponent(req.uri.path);
      if (path == reloadPath) {
        res.bufferOutput = false;
        res.headers
          ..set(HttpHeaders.contentTypeHeader, 'text/event-stream')
          ..set(HttpHeaders.cacheControlHeader, 'no-cache');
        res.write(': mflab\n\n');
        await res.flush();
        _clients.add(res);
        unawaited(res.done.whenComplete(() => _clients.remove(res)));
        return;
      }

      final parts = path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty).toList();
      // Klasör dışına çıkmaya çalışan istekleri reddet.
      if (parts.any((p) => p == '..' || p.contains(':'))) {
        res.statusCode = HttpStatus.forbidden;
        await res.close();
        return;
      }
      var target = parts.isEmpty ? root : '$root\\${parts.join('\\')}';
      if (await Directory(target).exists()) {
        if (!path.endsWith('/')) {
          res.redirect(Uri(path: '$path/'));
          return;
        }
        target = '$target\\index.html';
      }
      final file = File(target);
      if (!await file.exists()) {
        res.statusCode = HttpStatus.notFound;
        res.headers.contentType = ContentType.html;
        res.write(_notFoundPage(path));
        await res.close();
        return;
      }
      final ext = target.split('.').last.toLowerCase();
      res.headers
        ..set(HttpHeaders.contentTypeHeader, _mime[ext] ?? 'application/octet-stream')
        ..set(HttpHeaders.cacheControlHeader, 'no-store');
      if (ext == 'html' || ext == 'htm') {
        var html = await file.readAsString();
        final i = html.toLowerCase().lastIndexOf('</body>');
        html = i >= 0
            ? html.substring(0, i) + _reloadScript + html.substring(i)
            : html + _reloadScript;
        res.add(utf8.encode(html));
      } else {
        await res.addStream(file.openRead());
      }
      await res.close();
    } catch (_) {
      try {
        res.statusCode = HttpStatus.internalServerError;
        await res.close();
      } catch (_) {}
    }
  }

  String _notFoundPage(String path) {
    final html = <String>[];
    try {
      for (final e in Directory(root).listSync()) {
        final n = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (e is File && RegExp(r'\.html?$', caseSensitive: false).hasMatch(n)) {
          html.add('<li><a href="/$n">$n</a></li>');
        }
      }
    } catch (_) {}
    final esc = const HtmlEscape().convert(path);
    return '<!DOCTYPE html><html lang="tr"><head><meta charset="utf-8"><title>Bulunamadı</title>'
        '<style>body{font-family:Segoe UI,sans-serif;padding:40px;color:#1e293b}</style></head><body>'
        '<h2>Sayfa bulunamadı: $esc</h2>'
        '<p>Projenin ana sayfası <b>index.html</b> adında olmalı. Bu klasördeki HTML dosyaları:</p>'
        '<ul>${html.isEmpty ? '<li>(HTML dosyası yok)</li>' : html.join()}</ul>$_reloadScript</body></html>';
  }
}
