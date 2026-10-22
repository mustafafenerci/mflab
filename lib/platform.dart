import 'dart:io';

/// İşletim sistemine bağlı sabitler ve yollar. MF Lab Windows, macOS ve Linux'ta çalışır;
/// işletim sistemine göre değişen her şey buradan ya da `Engine` içindeki `Platform` dallarından geçer.
class Os {
  static final bool isWindows = Platform.isWindows;
  static final bool isMac = Platform.isMacOS;
  static final bool isLinux = Platform.isLinux;

  /// Dosya yolu ayracı: Windows'ta `\`, diğerlerinde `/`.
  static final String sep = Platform.pathSeparator;

  static String get home =>
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.systemTemp.path;

  static String get userName =>
      Platform.environment['USERNAME'] ??
      Platform.environment['USER'] ??
      Platform.environment['LOGNAME'] ??
      'ogrenci';

  /// Tüm MF Lab dosyalarının ortak kökü. Windows'ta paylaşılan `C:\MFLab` (laboratuvar bilgisayarları
  /// için kullanıcıya özel alt klasörlere bölünür); macOS ve Linux'ta kullanıcının kendi ev klasörü.
  static String get rootDir => isWindows ? r'C:\MFLab' : '$home/MFLab';

  /// Uygulamanın küçük yapılandırma dosyalarını koyduğu klasör.
  static String get configDir {
    if (isWindows) {
      return '${Platform.environment['APPDATA'] ?? rootDir}\\MFLab';
    }
    if (isMac) return '$home/Library/Application Support/MFLab';
    return '${Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config'}/MFLab';
  }

  /// Kullanıcı arayüzünde gösterilen işletim sistemi adı.
  static String get name => isWindows
      ? 'Windows'
      : isMac
          ? 'macOS'
          : 'Linux';

  /// Dosya yöneticisinin adı (arayüz metinleri için).
  static String get fileManager => isWindows
      ? 'Dosya Gezgini'
      : isMac
          ? 'Finder'
          : 'Dosya Yöneticisi';

  /// Windows açılışında tepsiye yerleşme yalnızca Windows'ta desteklenir.
  static bool get supportsTray => isWindows;

  /// Uygulama içi sessiz güncelleme yalnızca Windows'ta var; diğerlerinde sürüm sayfası açılır.
  static bool get supportsSelfUpdate => isWindows;

  /// Docker Desktop'ın kurulu olabileceği ek klasörler (GUI uygulamalarının PATH'i boştur).
  static List<String> get extraToolDirs {
    if (isMac) {
      return [
        '/opt/homebrew/bin',
        '/usr/local/bin',
        '/Applications/Docker.app/Contents/Resources/bin',
        '/Applications/Visual Studio Code.app/Contents/Resources/app/bin',
        '$home/.docker/bin',
      ];
    }
    if (isLinux) {
      return ['/usr/local/bin', '/usr/bin', '/snap/bin', '/usr/share/code/bin'];
    }
    return const [];
  }
}
