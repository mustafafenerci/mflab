import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../engine.dart';
import '../settings.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Center(
          child: Column(
            children: [
              Image.asset('assets/images/logo.png', width: 128),
              const SizedBox(height: 12),
              Text(AppConfig.appName, style: t.headlineMedium),
              Text('Sürüm ${AppConfig.appVersion}', style: t.bodyMedium),
              const SizedBox(height: 4),
              const Text('Öğrenciler için ders ortamı kurucusu'),
            ],
          ),
        ),
        const SizedBox(height: 28),
        _section(context, 'Kullanıcı & Öğrenci Ayarları', [
          ListenableBuilder(
            listenable: state,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.studentName.isNotEmpty || state.studentNumber.isNotEmpty
                      ? 'Öğrenci: ${state.studentNumber} - ${state.studentName}'
                      : 'Öğrenci bilgisi henüz kaydedilmedi (Ödev teslim paketinde otomatik kullanılır).',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tema: ${switch (state.themeMode) {
                    ThemeMode.light => 'Açık Tema',
                    ThemeMode.dark => 'Koyu Tema',
                    ThemeMode.system => 'Sistem Teması'
                  }}',
                  style: const TextStyle(fontSize: 13),
                ),
                Text(
                  'Ayarlar dosyası: ${AppSettings.filePath}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => _editStudentInfo(context),
                      icon: const Icon(Icons.badge_outlined, size: 18),
                      label: const Text('Öğrenci Bilgilerini Düzenle'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Engine.openFolder(AppConfig.baseDir),
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('MF Lab Klasörünü Aç'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ]),
        _section(context, 'Hakkında', [
          const Text(
              'MF Lab, bilişim ve yazılım derslerinde gereken yazılımları (Apache, PHP, MariaDB, PostgreSQL, Composer, Git, VS Code ve eklentileri) tek yerden, anlayarak kurman için hazırlandı. '
              'Her kurulum adımında "neden kuruyoruz?" sorusunun cevabı gösterilir. Sunucu yazılımları Docker konteynerlerinde çalışır; böylece herkeste aynı ortam olur ve bilgisayarın temiz kalır.'),
        ]),
        _section(context, 'Nasıl çalışır?', [
          const Text('• Dersini seç, kurulacak yazılımları ve nedenlerini oku.\n'
              '• "Kur"a bas; Docker ve araçlar kontrol edilir, eksikler için indirme sayfası açılır.\n'
              '• Çalışma klasörün (htdocs gibi) Windows\'ta durur, konteynere bağlıdır. Dosyaları VS Code\'da düzenleyip tarayıcıda anında görürsün.\n'
              '• Masaüstüne kısayollar eklenir. Servisleri "Yönetim" sayfasından başlatıp durdurursun.\n'
              '• Bir hata olursa nedeni ve resmi kaynak bağlantısı gösterilir.'),
        ]),
        _section(context, 'Geliştirici', [
          const Text(AppConfig.author),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                  onPressed: () => Engine.openUrl(AppConfig.repoUrl),
                  icon: const Icon(Icons.code),
                  label: const Text('GitHub')),
              OutlinedButton.icon(
                  onPressed: () => Engine.openUrl(AppConfig.issuesUrl),
                  icon: const Icon(Icons.bug_report_outlined),
                  label: const Text('Hata bildir / öneri')),
              OutlinedButton.icon(
                  onPressed: () => Engine.openUrl(AppConfig.releasesUrl),
                  icon: const Icon(Icons.new_releases_outlined),
                  label: const Text('Sürümler')),
            ],
          ),
        ]),
        _section(context, 'Sistem & Donanım Tanısı', [
          const Text(
              'Bilgisayarının Docker, WSL, VS Code, disk ve RAM durumunu tek tıkla tara. Bir sorun yaşarsan çıkan sonucu hocana iletebilirsin.'),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: state.busy
                ? null
                : () {
                    state.clearLog();
                    state.runTask(() => Engine.diagnoseSystem(state.log));
                  },
            icon: const Icon(Icons.troubleshoot),
            label: const Text('Sistem Durumunu Tara'),
          ),
        ]),
        _section(context, 'Çevrimdışı Laboratuvar Desteği', [
          const Text(
              'Okul veya sınıf interneti yavaşsa veya kota sorunu varsa, hocandan USB ile aldığın hazır imaj arşivini (.tar) tek tıkla Docker\'a aktarabilirsin.'),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: state.busy
                ? null
                : () async {
                    final path = await Engine.pickFile(
                      title: 'Docker İmaj Arşivi (.tar) Seç',
                      filterName: 'Tar Arşivleri',
                      extension: 'tar',
                    );
                    if (path != null) {
                      state.clearLog();
                      state.runTask(
                          () => Engine.importDockerTar(path, state.log));
                    }
                  },
            icon: const Icon(Icons.usb),
            label: const Text('USB / Dosyadan İmaj Yükle (.tar)'),
          ),
        ]),
        _section(context, 'Güncelleme', [
          ListenableBuilder(
            listenable: state,
            builder: (context, _) {
              final u = state.update;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u != null
                      ? 'Yeni sürüm var: ${u.version}'
                      : state.checkedUpdate
                          ? 'Güncelsin (sürüm ${AppConfig.appVersion}).'
                          : 'Henüz denetlenmedi.'),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    OutlinedButton.icon(
                        onPressed: state.checkUpdate,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Güncellemeleri denetle')),
                    if (u != null)
                      FilledButton.icon(
                          onPressed: () => Engine.openUrl(u.url),
                          icon: const Icon(Icons.download),
                          label: const Text('İndir')),
                  ]),
                ],
              );
            },
          ),
        ]),
        _section(context, 'Lisans', [
          Text('${AppConfig.license} Lisansı. Copyright (c) 2026 ${AppConfig.author}.\n'
              'Kodu özgürce kullanabilir, değiştirebilir ve geliştirebilirsin. Katkı önerileri GitHub üzerinden Pull Request ile gelir.'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: () => showLicensePage(
                    context: context,
                    applicationName: AppConfig.appName,
                    applicationVersion: AppConfig.appVersion,
                    applicationIcon: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Image.asset('assets/images/logo.png', width: 48)),
                  ),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Kullanılan açık kaynak lisansları')),
        ]),
        _section(context, 'Teşekkürler', [
          const Text('Docker, Apache, PHP, MariaDB, PostgreSQL, phpMyAdmin, pgAdmin, Composer, Laravel, Node.js, Git, VS Code ve Flutter projelerine ve katkıcılarına.'),
        ]),
      ],
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editStudentInfo(BuildContext context) async {
    final nameCtrl = TextEditingController(text: state.studentName);
    final noCtrl = TextEditingController(text: state.studentNumber);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Öğrenci Bilgilerini Kaydet'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Bu bilgiler ödev teslim zip paketlerinde ve raporlarda otomatik kullanılır.'),
              const SizedBox(height: 12),
              TextField(
                controller: noCtrl,
                decoration: const InputDecoration(
                  labelText: 'Öğrenci Numarası',
                  hintText: 'Örn: 2024101050',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ad Soyad',
                  hintText: 'Örn: Ali Yılmaz',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );

    if (ok == true) {
      state.setStudentInfo(nameCtrl.text.trim(), noCtrl.text.trim());
    }
  }
}

