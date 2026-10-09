import 'package:flutter/material.dart';

import '../app_state.dart';
import '../engine.dart';
import '../models.dart';
import 'widgets.dart';

class _Entry {
  _Entry(this.course, this.pkg, this.installed, this.running);
  final Course course;
  final LabPackage pkg;
  final bool installed;
  final bool running;
}

class ManagePage extends StatefulWidget {
  const ManagePage({super.key, required this.state});
  final AppState state;

  @override
  State<ManagePage> createState() => _ManagePageState();
}

class _ManagePageState extends State<ManagePage> {
  late Future<List<_Entry>> future = _load();

  AppState get s => widget.state;

  Future<List<_Entry>> _load() async {
    final cat = s.catalog!;
    final out = <_Entry>[];
    final dockerUp = await Engine.dockerRunning();
    for (final c in cat.courses) {
      for (final id in c.packages) {
        final p = cat.packages[id];
        if (p == null || !p.isDocker) continue;
        final inst = await Engine.isInstalled(c, p);
        if (!inst) continue;
        final run = dockerUp && await Engine.isRunning(c, p);
        out.add(_Entry(c, p, inst, run));
      }
    }
    return out;
  }

  void reload() => setState(() => future = _load());

  Future<void> _task(Future<void> Function() t) async {
    s.logs.clear();
    await s.runTask(t);
    reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_Entry>>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Text('Yönetim',
                    style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                IconButton(
                    tooltip: 'Yenile',
                    onPressed: s.busy ? null : reload,
                    icon: const Icon(Icons.refresh)),
                FilledButton.tonalIcon(
                  onPressed: s.busy || items.every((e) => !e.running)
                      ? null
                      : () => _task(() async {
                            for (final e in items.where((e) => e.running)) {
                              await Engine.stop(e.course, e.pkg, s.log);
                            }
                          }),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Hepsini durdur'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                'Bu uygulamayı kapatsan bile servisler arka planda çalışmaya devam eder. Durdurmak için buradaki düğmeleri kullan.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            if (items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                      'Henüz kurulu bir servis yok. "Dersler" sayfasından dersini seçip kurulumu başlat.'),
                ),
              ),
            for (final e in items) _ServiceCard(entry: e, page: this),
          ],
        );
      },
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.entry, required this.page});
  final _Entry entry;
  final _ManagePageState page;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final s = page.s;
    final busy = s.busy;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(courseIcon(e.course.icon)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.course.name,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(e.pkg.name,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Chip(
                  avatar: Icon(Icons.circle,
                      size: 12,
                      color: e.running ? Colors.green : Colors.redAccent),
                  label: Text(e.running ? 'Çalışıyor' : 'Durdu'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!e.running)
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () => page._task(
                            () => Engine.start(e.course, e.pkg, s.log)),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Başlat'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: busy
                        ? null
                        : () => page._task(
                            () => Engine.stop(e.course, e.pkg, s.log)),
                    icon: const Icon(Icons.stop),
                    label: const Text('Durdur'),
                  ),
                if (e.running)
                  for (final l in e.pkg.links)
                    OutlinedButton.icon(
                      onPressed: () => Engine.openUrl(l.url),
                      icon: const Icon(Icons.public, size: 18),
                      label: Text(l.name),
                    ),
                OutlinedButton.icon(
                  onPressed: () =>
                      Engine.openFolder(Engine.workspaceDir(e.course)),
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('Klasör'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      Engine.openInVsCode(Engine.workspaceDir(e.course)),
                  icon: const Icon(Icons.code, size: 18),
                  label: const Text('VS Code'),
                ),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => page._task(
                          () => Engine.showLogs(e.course, e.pkg, s.log)),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Loglar'),
                ),
                if (e.running)
                  OutlinedButton.icon(
                    onPressed: () => Engine.openContainerTerminal(e.course, e.pkg),
                    icon: const Icon(Icons.terminal, size: 18),
                    label: const Text('Terminal'),
                  ),
                if (e.running && (e.pkg.id == 'web2-stack' || e.pkg.id == 'vtys-stack')) ...[
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => page._task(() =>
                            Engine.backupDatabase(e.course, e.pkg, s.log)),
                    icon: const Icon(Icons.backup_outlined, size: 18),
                    label: const Text('Yedek Al (.sql)'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _importSql(context),
                    icon: const Icon(Icons.restore_page_outlined, size: 18),
                    label: const Text('İçe Aktar (.sql)'),
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _exportHomeworkDialog(context),
                  icon: const Icon(Icons.archive_outlined, size: 18),
                  label: const Text('Ödevi Paketle (.zip)'),
                ),
                if (e.running)
                  for (final a in e.pkg.actions)
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => _runAction(context, a),
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: Text(a.label),
                    ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: busy ? null : () => _showCourseUninstallDialog(context, e.course),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('Ders Bitti / Kaldır'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(e.pkg.info,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Future<void> _runAction(BuildContext context, PackageAction a) async {
    String? name;
    if (a.prompt != null) {
      final ctrl = TextEditingController();
      name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(a.label),
          content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(labelText: a.prompt)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Vazgeç')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Oluştur')),
          ],
        ),
      );
      if (name == null || !RegExp(r'^[a-z0-9_-]+$').hasMatch(name)) {
        if (name != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Ad yalnızca küçük harf, rakam, - ve _ içerebilir.')));
        }
        return;
      }
    }
    await page._task(
        () => Engine.runAction(entry.course, entry.pkg, a, name, page.s.log));
  }

  Future<void> _showCourseUninstallDialog(BuildContext context, Course course) async {
    bool removeVolumes = false;
    bool removeWorkspace = false;
    bool removeShortcuts = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Text('${course.name} - Kaldır'),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dönem veya ders bittiğinde bu dersin oluşturduğu ortamı bilgisayarından temizleyebilirsin.',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.2)),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Neler Yapılacak?', style: TextStyle(fontWeight: FontWeight.bold)),
                            SizedBox(height: 4),
                            Text('• İlgili Docker konteynerleri durdurulur ve silinir (RAM & disk ferahlar).'),
                            Text('• Konfigürasyon ve stack tanımları temizlenir.'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: removeShortcuts,
                        title: const Text('Masaüstü kısayollarını kaldır'),
                        subtitle: const Text('Masaüstündeki "MF Lab - Ders" klasörü silinir.'),
                        onChanged: (v) => setDialogState(() => removeShortcuts = v ?? true),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: removeVolumes,
                        title: const Text('Veritabanı verilerini de kalıcı olarak sil'),
                        subtitle: const Text(
                          'MariaDB / PostgreSQL içindeki tüm tablolar ve kayıtlar silinir. (İşaretlemezsen verilerin ilerisi için saklanır).',
                          style: TextStyle(fontSize: 12),
                        ),
                        onChanged: (v) => setDialogState(() => removeVolumes = v ?? false),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: removeWorkspace,
                        title: const Text(
                          'Yazdığım tüm kod dosyalarını da sil!',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'DİKKAT: Çalışma klasöründeki (htdocs/sql) kodların ve projelerin tamamen silinir! Ödevlerini yedeklemediysen işaretleme.',
                          style: TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                        onChanged: (v) => setDialogState(() => removeWorkspace = v ?? false),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Evet, Ortamı Kaldır'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      await page._task(() => Engine.uninstallCourse(
            catalog: page.s.catalog!,
            course: course,
            removeVolumes: removeVolumes,
            removeWorkspace: removeWorkspace,
            removeShortcuts: removeShortcuts,
            log: page.s.log,
          ));
    }
  }

  Future<void> _importSql(BuildContext context) async {
    final path = await Engine.pickFile(
      title: 'İçe Aktarılacak .sql Dosyasını Seç',
      filterName: 'SQL Dosyaları',
      extension: 'sql',
    );
    if (path == null) return;

    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Veritabanını İçe Aktar?'),
        content: Text('$path dosyasındaki tablolar ve veriler veritabanına aktarılacak. Onaylıyor musun?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('İçe Aktar')),
        ],
      ),
    );

    if (ok == true) {
      await page._task(() => Engine.importDatabase(entry.course, entry.pkg, path, page.s.log));
    }
  }

  Future<void> _exportHomeworkDialog(BuildContext context) async {
    final nameCtrl = TextEditingController(text: page.s.studentName);
    final noCtrl = TextEditingController(text: page.s.studentNumber);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ödev Teslim Paketi Oluştur (.zip)'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Kodların ve veritabanı yedeğin tek bir .zip arşivi olarak masaüstüne kaydedilecek.'),
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
          FilledButton.icon(
            onPressed: () {
              if (noCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(ctx, true);
            },
            icon: const Icon(Icons.archive),
            label: const Text('Paketle'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final name = nameCtrl.text.trim();
      final no = noCtrl.text.trim();
      page.s.setStudentInfo(name, no);
      await page._task(() => Engine.exportHomeworkZip(
            course: entry.course,
            catalog: page.s.catalog!,
            studentName: name,
            studentNumber: no,
            log: page.s.log,
          ));
    }
  }
}
