import 'dart:io';

/// Merkezi yapılandırma. Fork edenler yalnızca burayı değiştirerek
/// kendi GitHub deposunu ve imajını gösterebilir.
class AppConfig {
  static const appName = 'MF Lab';
  static const appVersion = '1.1.8';
  static const author = 'Mustafa Fenerci';
  static const githubUser = 'mustafafenerci';
  static const githubRepo = 'mflab';
  static const license = 'MIT';

  static const repoUrl = 'https://github.com/$githubUser/$githubRepo';
  static const releasesUrl = '$repoUrl/releases/latest';
  static const issuesUrl = '$repoUrl/issues';
  static const versionJsonUrl =
      'https://raw.githubusercontent.com/$githubUser/$githubRepo/main/version.json';

  /// Tüm MF Lab dosyalarının ortak kökü.
  static const rootDir = r'C:\MFLab';

  /// Bu Windows kullanıcısının çalışma dosyaları ve konteyner tanımları.
  /// Laboratuvarda aynı bilgisayarı kullanan öğrenciler birbirinin projesini görmesin diye
  /// her kullanıcıya `C:\MFLab\<kullanıcı>` ayrılır. [init] çağrılana kadar [rootDir]'dir.
  static String baseDir = rootDir;

  /// Kaldırma programının (Inno Setup) çalışma klasörünü bulabilmesi için yazılan dosya.
  static String get baseDirPointerFile =>
      '${Platform.environment['APPDATA'] ?? rootDir}\\MFLab\\basedir.txt';

  static const _ownerFile = '$rootDir\\.owner';

  /// Windows kullanıcı adını klasör adı olarak güvenli hale getirir (Türkçe harfler sadeleşir).
  static String safeUserName(String name) {
    const tr = {
      'ç': 'c', 'Ç': 'C', 'ğ': 'g', 'Ğ': 'G', 'ı': 'i', 'İ': 'I',
      'ö': 'o', 'Ö': 'O', 'ş': 's', 'Ş': 'S', 'ü': 'u', 'Ü': 'U',
    };
    final b = StringBuffer();
    for (final ch in name.trim().split('')) {
      final t = tr[ch] ?? ch;
      b.write(RegExp(r'^[A-Za-z0-9_.-]$').hasMatch(t) ? t : '_');
    }
    final s = b.toString().replaceAll(RegExp(r'^[._]+|[._]+$'), '');
    return s.isEmpty ? 'ogrenci' : s;
  }

  /// Hangi klasörün kullanılacağına karar verir.
  /// - Eski sürümden kalan veriler doğrudan `C:\MFLab` altındaysa ve sahibi bu kullanıcıysa
  ///   (ya da henüz sahibi yoksa) taşımadan orada devam edilir.
  /// - Diğer her durumda kullanıcıya özel `C:\MFLab\<kullanıcı>` kullanılır.
  static String resolveBaseDir({
    required String root,
    required String user,
    required bool legacyData,
    String? owner,
  }) {
    if (owner != null && owner.isNotEmpty) {
      return owner.toLowerCase() == user.toLowerCase() ? root : '$root\\$user';
    }
    return legacyData ? root : '$root\\$user';
  }

  static bool _hasLegacyData() {
    final root = Directory(rootDir);
    if (!root.existsSync()) return false;
    if (File('$rootDir\\settings.json').existsSync()) return true;
    try {
      for (final e in root.listSync(followLinks: false)) {
        if (e is Directory && Directory('${e.path}\\.stack').existsSync()) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  static Future<void> init() async {
    final user = safeUserName(Platform.environment['USERNAME'] ?? 'ogrenci');
    String? owner;
    try {
      final f = File(_ownerFile);
      if (f.existsSync()) owner = f.readAsStringSync().trim();
    } catch (_) {}
    final legacy = (owner == null || owner.isEmpty) && _hasLegacyData();
    baseDir = resolveBaseDir(
        root: rootDir, user: user, legacyData: legacy, owner: owner);

    try {
      if (legacy) await File(_ownerFile).writeAsString(user);
      final dir = Directory(baseDir);
      if (baseDir != rootDir && !dir.existsSync()) {
        await dir.create(recursive: true);
        // Klasörü yalnızca bu kullanıcı (ve yöneticiler/sistem) görebilsin.
        final who =
            '${Platform.environment['USERDOMAIN'] ?? '.'}\\${Platform.environment['USERNAME'] ?? ''}';
        await Process.run('icacls', [
          baseDir,
          '/inheritance:r',
          '/grant:r',
          '$who:(OI)(CI)F',
          '*S-1-5-18:(OI)(CI)F',
          '*S-1-5-32-544:(OI)(CI)F',
        ]);
      }
    } catch (_) {}

    try {
      final p = File(baseDirPointerFile);
      await p.parent.create(recursive: true);
      await p.writeAsString(baseDir);
    } catch (_) {}
  }
}
