import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'config.dart';
import 'engine.dart';

enum CheckLevel { ok, warn, fail }

/// Ön kontroldeki tek bir maddenin sonucu.
class CheckResult {
  const CheckResult(this.level, this.title, this.detail, {this.fix});
  final CheckLevel level;
  final String title;
  final String detail;

  /// Öğrencinin yapması gereken, adım adım Türkçe çözüm.
  final String? fix;
}

/// Bilgisayardan toplanan ham bilgiler. `null` = öğrenilemedi.
class SystemFacts {
  SystemFacts({
    this.windowsBuild,
    this.ramGb,
    this.freeDiskGb,
    this.virtualization,
    this.hypervisor,
    this.isAdmin,
    this.rebootPending = false,
    this.wslOk,
    this.baseDirWritable = true,
    this.dockerInstalled = false,
    this.dockerRunning = false,
    this.dockerOs,
    Map<String, String?>? network,
  }) : network = network ?? {};

  final int? windowsBuild;
  final double? ramGb;
  final double? freeDiskGb;
  final bool? virtualization;
  final bool? hypervisor;
  final bool? isAdmin;
  final bool rebootPending;
  final bool? wslOk;
  final bool baseDirWritable;
  final bool dockerInstalled;
  final bool dockerRunning;

  /// `docker version` sunucu işletim sistemi: 'linux' veya 'windows'.
  final String? dockerOs;

  /// Sunucu adı -> null (erişildi) ya da hata türü ('sertifika', 'zaman aşımı', 'erişilemiyor').
  final Map<String, String?> network;
}

/// Kurulumdan önce bilgisayarın hazır olup olmadığını kontrol eder ve sorunları Türkçe anlatır.
class Preflight {
  static const registries = {
    'registry-1.docker.io': 'Docker Hub (MariaDB, phpMyAdmin, PostgreSQL imajları)',
    'ghcr.io': 'GitHub (MF Lab PHP imajı)',
  };

  static const _dockerCli = r'C:\Program Files\Docker\Docker\DockerCli.exe';

  // ------------------------------------------------------------ toplama

  static const _factsScript = r'''
$ErrorActionPreference = 'SilentlyContinue'
$o = [ordered]@{}
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$o.build = [int]$cv.CurrentBuild
$cs = Get-CimInstance Win32_ComputerSystem
$o.ramGb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$o.hypervisor = [bool]$cs.HypervisorPresent
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$o.virt = [bool]$cpu.VirtualizationFirmwareEnabled
$d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$o.freeGb = [math]::Round($d.FreeSpace / 1GB, 1)
$o.admin = @((whoami /groups) -match 'S-1-5-32-544').Count -gt 0
$o.reboot = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
$o | ConvertTo-Json -Compress
''';

  static Future<Map<String, dynamic>> _systemJson() async {
    final f = File('${Directory.systemTemp.path}\\mflab_facts.ps1');
    try {
      await f.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(_factsScript)]);
      final r = await Engine.run('powershell',
          ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', f.path]);
      final out = (r.stdout as String).trim();
      final start = out.indexOf('{');
      if (start < 0) return {};
      return jsonDecode(out.substring(start)) as Map<String, dynamic>;
    } catch (_) {
      return {};
    } finally {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  static Future<bool> rebootPending() async =>
      (await _systemJson())['reboot'] == true;

  static Future<bool> _baseDirWritable() async {
    try {
      final dir = Directory(AppConfig.baseDir);
      await dir.create(recursive: true);
      final probe = File('${dir.path}\\.yazma_testi');
      await probe.writeAsString('ok');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Docker kayıt sunucusuna HTTPS ile ulaşılabiliyor mu? Herhangi bir HTTP yanıtı (401 dahil) yeterli.
  static Future<String?> _reach(String host) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client
          .getUrl(Uri.parse('https://$host/v2/'))
          .timeout(const Duration(seconds: 8));
      final res = await req.close().timeout(const Duration(seconds: 8));
      await res.drain<void>();
      return null;
    } on HandshakeException {
      return 'sertifika';
    } on TlsException {
      return 'sertifika';
    } on TimeoutException {
      return 'zaman aşımı';
    } catch (_) {
      return 'erişilemiyor';
    } finally {
      client.close(force: true);
    }
  }

  static Future<SystemFacts> gather({required bool needsDocker}) async {
    await Engine.refreshPath();
    final sys = await _systemJson();
    final writable = await _baseDirWritable();
    var dInst = false, dRun = false;
    String? dOs;
    bool? wsl;
    final net = <String, String?>{};
    if (needsDocker) {
      dInst = await Engine.dockerInstalled();
      dRun = dInst && await Engine.dockerRunning();
      if (dRun) {
        final r = await Engine.run(
            'docker', ['version', '--format', '{{.Server.Os}}']);
        dOs = (r.stdout as String).trim().toLowerCase();
      }
      wsl = await Engine.commandOk('wsl --status');
      final results = await Future.wait(registries.keys.map(_reach));
      var i = 0;
      for (final h in registries.keys) {
        net[h] = results[i++];
      }
    }
    double? d(Object? v) => v is num ? v.toDouble() : null;
    return SystemFacts(
      windowsBuild: sys['build'] is num ? (sys['build'] as num).toInt() : null,
      ramGb: d(sys['ramGb']),
      freeDiskGb: d(sys['freeGb']),
      virtualization: sys['virt'] as bool?,
      hypervisor: sys['hypervisor'] as bool?,
      isAdmin: sys['admin'] as bool?,
      rebootPending: sys['reboot'] == true,
      wslOk: wsl,
      baseDirWritable: writable,
      dockerInstalled: dInst,
      dockerRunning: dRun,
      dockerOs: dOs,
      network: net,
    );
  }

  // ------------------------------------------------------- değerlendirme

  static List<CheckResult> evaluate(SystemFacts f, {required bool needsDocker}) {
    final r = <CheckResult>[];

    r.add(f.baseDirWritable
        ? const CheckResult(CheckLevel.ok, 'Çalışma klasörü', '${AppConfig.baseDir} yazılabilir.')
        : const CheckResult(CheckLevel.fail, 'Çalışma klasörü',
            '${AppConfig.baseDir} klasörü oluşturulamıyor veya içine yazılamıyor.',
            fix: 'Okul/laboratuvar bilgisayarıysan bilgisayar sorumlusundan C:\\MFLab klasörü için '
                'yazma izni iste. Kendi bilgisayarındaysan antivirüs programının "korumalı klasör" '
                'ayarına MF Lab\'ı ekle.'));

    final disk = f.freeDiskGb;
    final minDisk = needsDocker ? 5 : 1;
    if (disk == null) {
      r.add(const CheckResult(CheckLevel.warn, 'Disk alanı', 'Boş alan öğrenilemedi.'));
    } else if (disk < minDisk) {
      r.add(CheckResult(CheckLevel.fail, 'Disk alanı',
          'C: sürücüsünde yalnızca ${disk.toStringAsFixed(1)} GB boş alan var.',
          fix: 'En az ${needsDocker ? 15 : 2} GB boş alan aç: Ayarlar → Sistem → Depolama → '
              'Geçici dosyalar\'ı temizle, kullanmadığın programları kaldır.'));
    } else if (needsDocker && disk < 15) {
      r.add(CheckResult(CheckLevel.warn, 'Disk alanı',
          '${disk.toStringAsFixed(1)} GB boş alan var; Docker imajları için 15 GB önerilir.',
          fix: 'Kurulum çalışabilir ama yer biterse yarıda kalır. Gerekirse Yönetim → Docker Temizliği kullan.'));
    } else {
      r.add(CheckResult(CheckLevel.ok, 'Disk alanı', '${disk.toStringAsFixed(1)} GB boş.'));
    }

    if (!needsDocker) return r;

    final build = f.windowsBuild;
    if (build == null) {
      r.add(const CheckResult(CheckLevel.warn, 'Windows sürümü', 'Sürüm öğrenilemedi.'));
    } else if (build < 19044) {
      r.add(CheckResult(CheckLevel.fail, 'Windows sürümü',
          'Windows derleme numaran $build; Docker Desktop için çok eski.',
          fix: 'Ayarlar → Windows Update ile Windows 10 22H2 veya Windows 11\'e güncelle, '
              'sonra bilgisayarı yeniden başlat.'));
    } else {
      r.add(CheckResult(CheckLevel.ok, 'Windows sürümü',
          build >= 22000 ? 'Windows 11 (derleme $build).' : 'Windows 10 (derleme $build).'));
    }

    final ram = f.ramGb;
    if (ram == null) {
      r.add(const CheckResult(CheckLevel.warn, 'Bellek (RAM)', 'RAM miktarı öğrenilemedi.'));
    } else if (ram < 3.5) {
      r.add(CheckResult(CheckLevel.fail, 'Bellek (RAM)',
          '${ram.toStringAsFixed(1)} GB RAM var; Docker için en az 4 GB gerekir.',
          fix: 'Bu bilgisayarda Docker çalışmaz. Okul laboratuvarındaki bir bilgisayarı kullan '
              'veya hocana haber ver.'));
    } else if (ram < 7.5) {
      r.add(CheckResult(CheckLevel.warn, 'Bellek (RAM)',
          '${ram.toStringAsFixed(1)} GB RAM var; çalışır ama yavaş olabilir (8 GB önerilir).',
          fix: 'Ders sırasında tarayıcıda gereksiz sekmeleri ve oyun/sohbet programlarını kapat. '
              'İşin bitince Yönetim → Hepsini durdur ile servisleri kapat.'));
    } else {
      r.add(CheckResult(CheckLevel.ok, 'Bellek (RAM)', '${ram.toStringAsFixed(1)} GB.'));
    }

    if (f.hypervisor == true || f.virtualization == true || f.dockerRunning) {
      r.add(const CheckResult(CheckLevel.ok, 'Sanallaştırma', 'Açık.'));
    } else if (f.virtualization == false) {
      r.add(const CheckResult(CheckLevel.fail, 'Sanallaştırma',
          'İşlemcinin sanallaştırma özelliği (Intel VT-x / AMD-V) BIOS\'ta kapalı. Docker bu olmadan çalışmaz.',
          fix: 'Bilgisayarı yeniden başlat, açılırken F2 / Del / F10 (markaya göre) ile BIOS\'a gir. '
              '"Intel Virtualization Technology", "VT-x", "SVM Mode" veya "AMD-V" ayarını Enabled yap, '
              'kaydedip çık (genelde F10).'));
    } else {
      r.add(const CheckResult(CheckLevel.warn, 'Sanallaştırma', 'Durumu öğrenilemedi.'));
    }

    if (f.wslOk == false) {
      r.add(const CheckResult(CheckLevel.warn, 'WSL 2',
          'Windows Linux Alt Sistemi (WSL) hazır değil. Docker Desktop buna ihtiyaç duyar.',
          fix: 'Docker Desktop kurulumu WSL\'i genelde kendisi kurar; kurulumdan sonra bilgisayarı '
              'yeniden başlat. Olmazsa Başlat menüsünde PowerShell\'e sağ tıkla → Yönetici olarak '
              'çalıştır → "wsl --install" yaz, bitince yeniden başlat.'));
    } else if (f.wslOk == true) {
      r.add(const CheckResult(CheckLevel.ok, 'WSL 2', 'Hazır.'));
    }

    if (f.rebootPending) {
      r.add(CheckResult(
          f.dockerInstalled && !f.dockerRunning ? CheckLevel.fail : CheckLevel.warn,
          'Yeniden başlatma',
          'Windows bir yeniden başlatma bekliyor (güncelleme veya yeni kurulan WSL/Docker).',
          fix: 'Açık dosyalarını kaydet ve bilgisayarı yeniden başlat. Sonra MF Lab\'ı açıp tekrar "Kur"a bas.'));
    }

    if (!f.dockerInstalled) {
      r.add(CheckResult(
          f.isAdmin == false ? CheckLevel.fail : CheckLevel.warn,
          'Docker Desktop',
          f.isAdmin == false
              ? 'Docker Desktop kurulu değil ve bu Windows hesabının yönetici yetkisi yok. Docker kurmak için yönetici gerekir.'
              : 'Docker Desktop kurulu değil. Kurulumda indirme sayfası açılacak.',
          fix: f.isAdmin == false
              ? 'Okul bilgisayarıysan bilgisayar sorumlusundan Docker Desktop kurmasını iste. '
                  'Kendi bilgisayarındaysan yönetici hesabıyla oturum aç.'
              : 'Docker Desktop\'ı kur, bilgisayarı yeniden başlat, Docker\'ı bir kez açıp lisansı kabul et.'));
    } else if (!f.dockerRunning) {
      r.add(const CheckResult(CheckLevel.warn, 'Docker Desktop',
          'Kurulu ama çalışmıyor. MF Lab başlatmayı deneyecek.',
          fix: 'Docker Desktop açılınca bir lisans sözleşmesi veya giriş ekranı çıkarsa "Accept" ve '
              '"Skip" ile geç. Sol altta "Engine running" yazmalı.'));
    } else if (f.dockerOs == 'windows') {
      r.add(const CheckResult(CheckLevel.fail, 'Docker modu',
          'Docker "Windows konteynerleri" modunda; MF Lab Linux konteynerleri kullanır.',
          fix: 'Saatin yanındaki Docker (balina) simgesine sağ tıkla → "Switch to Linux containers..." seç.'));
    } else {
      r.add(const CheckResult(CheckLevel.ok, 'Docker Desktop', 'Çalışıyor (Linux konteynerleri).'));
    }

    for (final e in f.network.entries) {
      final what = registries[e.key] ?? e.key;
      if (e.value == null) {
        r.add(CheckResult(CheckLevel.ok, 'İnternet: ${e.key}', 'Erişilebiliyor.'));
      } else if (e.value == 'sertifika') {
        r.add(CheckResult(CheckLevel.warn, 'İnternet: ${e.key}',
            '$what adresine güvenli bağlantı kurulamadı (sertifika). Okul ağı HTTPS trafiğini denetliyor olabilir.',
            fix: 'Mümkünse cep telefonu internetiyle (hotspot) veya evde kurulumu yap. Okul ağında '
                'kalıcı çözüm için bilgi işlem biriminden Docker için istisna iste.'));
      } else {
        r.add(CheckResult(CheckLevel.warn, 'İnternet: ${e.key}',
            '$what adresine ulaşılamadı (${e.value}). İmajlar indirilemeyebilir.',
            fix: 'İnternet bağlantını kontrol et. Okul ağı engelliyorsa telefon interneti veya ev ağıyla dene. '
                'Daha önce indirilen imajlar varsa kurulum yine de çalışabilir.'));
      }
    }
    return r;
  }

  // ------------------------------------------------------------ çalıştırma

  /// Ön kontrolü yapar ve sonucu günlüğe yazar. Engelleyici sorun yoksa `true` döner.
  static Future<bool> run(Log log, {required bool needsDocker}) async {
    log('\n=== 🧪 Ön Kontrol ===');
    log('Bilgisayarın kuruluma hazır mı kontrol ediliyor...');
    var facts = await gather(needsDocker: needsDocker);

    // Docker yanlış moddaysa otomatik olarak Linux moduna geçirmeyi dene.
    if (facts.dockerOs == 'windows' && await File(_dockerCli).exists()) {
      log('Docker "Windows konteynerleri" modunda, Linux moduna geçiriliyor...');
      // Yolda boşluk olduğu için kabuk (cmd) kullanmadan doğrudan çalıştır.
      await Process.run(_dockerCli, ['-SwitchLinuxEngine']);
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(seconds: 5));
        final r = await Engine.run(
            'docker', ['version', '--format', '{{.Server.Os}}']);
        if ((r.stdout as String).trim().toLowerCase() == 'linux') break;
      }
      facts = await gather(needsDocker: needsDocker);
    }

    final results = evaluate(facts, needsDocker: needsDocker);
    for (final c in results) {
      final icon = switch (c.level) {
        CheckLevel.ok => '✔',
        CheckLevel.warn => '⚠',
        CheckLevel.fail => '✖',
      };
      log('$icon ${c.title}: ${c.detail}');
      if (c.level != CheckLevel.ok && c.fix != null) log('   → Ne yapmalı: ${c.fix}');
    }
    final fails = results.where((c) => c.level == CheckLevel.fail).length;
    final warns = results.where((c) => c.level == CheckLevel.warn).length;
    if (fails > 0) {
      log('✖ Ön kontrolde $fails engelleyici sorun var. Yukarıdaki "Ne yapmalı" adımlarını uygula, sonra tekrar dene.');
    } else if (warns > 0) {
      log('✔ Ön kontrol tamam ($warns uyarı). Kurulum devam edebilir.');
    } else {
      log('✔ Ön kontrol tamam: bilgisayarın hazır.');
    }
    return fails == 0;
  }
}
