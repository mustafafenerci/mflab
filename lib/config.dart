/// Merkezi yapılandırma. Fork edenler yalnızca burayı değiştirerek
/// kendi GitHub deposunu ve imajını gösterebilir.
class AppConfig {
  static const appName = 'MF Lab';
  static const appVersion = '1.1.3';
  static const author = 'Mustafa Fenerci';
  static const githubUser = 'mustafafenerci';
  static const githubRepo = 'mflab';
  static const license = 'MIT';

  static const repoUrl = 'https://github.com/$githubUser/$githubRepo';
  static const releasesUrl = '$repoUrl/releases/latest';
  static const issuesUrl = '$repoUrl/issues';
  static const versionJsonUrl =
      'https://raw.githubusercontent.com/$githubUser/$githubRepo/main/version.json';

  /// Öğrenci çalışma dosyalarının ve konteyner tanımlarının kökü.
  static const baseDir = r'C:\MFLab';
}
