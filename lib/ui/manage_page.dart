import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../engine.dart';
import '../models.dart';
import '../preflight.dart';
import 'web_projects_dialog.dart';
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

  Future<void> _showSampleDbDialog(BuildContext context, List<_Entry> items) async {
    final activeEntry = items.firstWhere(
      (e) => e.running && (e.pkg.id == 'web2-stack' || e.pkg.id == 'vtys-stack'),
      orElse: () => items.first,
    );

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Örnek Eğitim Veritabanı Yükle'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'ogrenci'),
            child: const ListTile(
              leading: Icon(Icons.school_outlined, color: Colors.blue),
              title: Text('Öğrenci Not Sistemi'),
              subtitle: Text('ogrenciler, dersler, notlar tabloları ve örnek kayıtlar'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'eticaret'),
            child: const ListTile(
              leading: Icon(Icons.shopping_bag_outlined, color: Colors.green),
              title: Text('E-Ticaret Demo'),
              subtitle: Text('kategoriler, urunler, siparisler tabloları'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'kutuphane'),
            child: const ListTile(
              leading: Icon(Icons.menu_book_outlined, color: Colors.amber),
              title: Text('Kütüphane Sistemi'),
              subtitle: Text('kitaplar, yazarlar, uyeler tabloları'),
            ),
          ),
        ],
      ),
    );

    if (choice != null) {
      await _task(() => Engine.loadSampleDatabase(
            course: activeEntry.course,
            sampleKey: choice,
            log: s.log,
          ));
    }
  }

  Widget _tool({
    required IconData icon,
    required String label,
    required String hint,
    required VoidCallback? onPressed,
  }) =>
      HoverHint(
        message: hint,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 16),
          label: Text(label),
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
              textStyle: const TextStyle(fontSize: 13)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_Entry>>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data!;
        final cs = Theme.of(context).colorScheme;
        // Docker gerektirmeyen (HTML/CSS/JS) ve kurulmuş web dersleri.
        final webCourses = s.catalog!.courses
            .where((c) =>
                c.isStaticWeb &&
                (s.settings.courseInstallDates.containsKey(c.id) ||
                    Directory(Engine.workspaceDir(c)).existsSync()))
            .toList();
        final runningCount = items.where((e) => e.running).length;
        final hasDb = items.any((e) =>
            e.running && (e.pkg.id == 'web2-stack' || e.pkg.id == 'vtys-stack'));
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Yönetim',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                          items.isEmpty
                              ? 'Henüz kurulu servis yok'
                              : '${items.length} servis · $runningCount çalışıyor',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                _tool(
                  icon: Icons.fact_check_outlined,
                  label: 'Ön Kontrol',
                  hint:
                      'Bilgisayarın Docker için hazır mı bakar: Windows sürümü, RAM, disk, sanallaştırma, WSL, '
                      'yeniden başlatma, Docker modu ve internet erişimi. Sorun varsa ne yapacağını Türkçe yazar.',
                  onPressed: s.busy
                      ? null
                      : () => _task(() => Preflight.run(s.log, needsDocker: true)),
                ),
                _tool(
                  icon: Icons.health_and_safety_outlined,
                  label: 'Port Doktoru',
                  hint:
                      'MF Lab\'ın kullandığı portların (6380, 6381, 6306 ...) dolu mu boş mu olduğunu kontrol eder. Site açılmıyorsa ilk burayı dene.',
                  onPressed: s.busy ? null : () => _task(() => Engine.checkPorts(s.log)),
                ),
                if (hasDb)
                  _tool(
                    icon: Icons.dataset_outlined,
                    label: 'Örnek Veritabanı',
                    hint:
                        'Eğitim için hazır tablolar ve örnek veriler yükler (öğrenci notları, e-ticaret, kütüphane). Alıştırma yapmak için idealdir.',
                    onPressed: s.busy ? null : () => _showSampleDbDialog(context, items),
                  ),
                _tool(
                  icon: Icons.cleaning_services_outlined,
                  label: 'Docker Temizliği',
                  hint:
                      'Kullanılmayan Docker imajlarını ve önbellekleri silip disk alanı açar. Çalışan servislerine dokunmaz.',
                  onPressed: s.busy ? null : () => _task(() => Engine.cleanDocker(s.log)),
                ),
                _tool(
                  icon: Icons.stop_circle_outlined,
                  label: 'Hepsini durdur',
                  hint:
                      'Çalışan tüm servisleri durdurur. Dosyaların ve veritabanın silinmez; Başlat ile devam edersin.',
                  onPressed: s.busy || runningCount == 0
                      ? null
                      : () => _task(() async {
                            for (final e in items.where((e) => e.running)) {
                              await Engine.stop(e.course, e.pkg, s.log);
                            }
                          }),
                ),
                HoverHint(
                  message: 'Listeyi ve servislerin çalışıp çalışmadığını yeniden okur.',
                  child: IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      onPressed: s.busy ? null : reload,
                      icon: const Icon(Icons.refresh)),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 10),
              child: Text(
                  'Bu uygulamayı kapatsan bile servisler arka planda çalışmaya devam eder.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ),
            if (items.isEmpty && webCourses.isEmpty)
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(Icons.dns_outlined, color: cs.onSurfaceVariant),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                            'Henüz kurulu bir servis yok. "Dersler" sayfasından dersini seçip kurulumu başlat.'),
                      ),
                    ],
                  ),
                ),
              ),
            for (final e in items) _ServiceCard(entry: e, page: this),
            for (final c in webCourses) _WebCourseCard(course: c, state: s),
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

  bool get _isDb =>
      entry.running &&
      (entry.pkg.id == 'web2-stack' || entry.pkg.id == 'vtys-stack');

  /// Küçük, açıklamalı (4 sn bekleyince ipucu gösteren) düğme.
  Widget _btn({
    required IconData icon,
    required String label,
    required String hint,
    required VoidCallback? onPressed,
    _Kind kind = _Kind.outlined,
  }) {
    final ic = Icon(icon, size: 16);
    final txt = Text(label);
    const pad = EdgeInsets.symmetric(horizontal: 10);
    const density = VisualDensity(horizontal: -2, vertical: -2);
    const text = TextStyle(fontSize: 13);
    final Widget b;
    switch (kind) {
      case _Kind.filled:
        b = FilledButton.icon(
            onPressed: onPressed,
            icon: ic,
            label: txt,
            style: FilledButton.styleFrom(
                padding: pad, visualDensity: density, textStyle: text));
      case _Kind.tonal:
        b = FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: ic,
            label: txt,
            style: FilledButton.styleFrom(
                padding: pad, visualDensity: density, textStyle: text));
      case _Kind.outlined:
        b = OutlinedButton.icon(
            onPressed: onPressed,
            icon: ic,
            label: txt,
            style: OutlinedButton.styleFrom(
                padding: pad, visualDensity: density, textStyle: text));
    }
    return HoverHint(message: hint, child: b);
  }

  Widget _sep(BuildContext context) => SizedBox(
        height: 22,
        child: VerticalDivider(
            width: 10, color: Theme.of(context).colorScheme.outlineVariant),
      );

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final s = page.s;
    final busy = s.busy;
    final cs = Theme.of(context).colorScheme;
    final running = e.running;
    final info = Engine.mapText(e.course.id, e.pkg.id, e.pkg.info);
    final infoLines = info
        .split('|')
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .toList();
    final links = running ? e.pkg.links : const <PackageLink>[];
    final actions = running ? e.pkg.actions : const <PackageAction>[];

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 2),
          // ---------------------------------------------------------- başlık
          Container(
            color: (running ? Colors.green : cs.outline).withValues(alpha: 0.08),
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(courseIcon(e.course.icon),
                      size: 18, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.course.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(e.pkg.name,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                _StatusPill(running: running),
                const SizedBox(width: 10),
                if (!running)
                  _btn(
                    icon: Icons.play_arrow_rounded,
                    label: 'Başlat',
                    kind: _Kind.filled,
                    hint:
                        'Bu dersin servislerini (Apache, MariaDB, phpMyAdmin) başlatır. İlk açılış 10–20 saniye sürebilir.',
                    onPressed: busy
                        ? null
                        : () => page._task(
                            () => Engine.start(e.course, e.pkg, s.log)),
                  )
                else
                  _btn(
                    icon: Icons.stop_rounded,
                    label: 'Durdur',
                    kind: _Kind.tonal,
                    hint:
                        'Servisleri durdurur. Dosyaların ve veritabanın silinmez; Başlat\'a basınca kaldığın yerden devam edersin.',
                    onPressed: busy
                        ? null
                        : () => page._task(
                            () => Engine.stop(e.course, e.pkg, s.log)),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'Daha fazla',
                  enabled: !busy,
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (_) => _showCourseUninstallDialog(context, e.course),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'remove',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_sweep_outlined, color: cs.error),
                        title: Text('Ders Bitti / Kaldır',
                            style: TextStyle(color: cs.error)),
                        subtitle: const Text(
                            'Servisleri ve konteynerleri kaldırır.\nKlasörü silmek isteğe bağlıdır.'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ---------------------------------------------------------- düğmeler
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final l in links)
                  _btn(
                    icon: Icons.public,
                    label: l.name,
                    kind: _Kind.tonal,
                    hint:
                        '${l.name} sayfasını tarayıcıda açar: ${Engine.mapText(e.course.id, e.pkg.id, l.url)}',
                    onPressed: () => Engine.openUrl(
                        Engine.mapText(e.course.id, e.pkg.id, l.url)),
                  ),
                if (links.isNotEmpty) _sep(context),
                _btn(
                  icon: Icons.code,
                  label: 'VS Code',
                  hint:
                      'Çalışma klasörünü VS Code\'da açar. Dosyayı kaydedip tarayıcıda sayfayı yenilemen yeterli.',
                  onPressed: () =>
                      Engine.openInVsCode(Engine.workspaceDir(e.course)),
                ),
                _btn(
                  icon: Icons.folder_open,
                  label: 'Klasör',
                  hint:
                      'Kodlarını koyduğun çalışma klasörünü Dosya Gezgini\'nde açar.',
                  onPressed: () =>
                      Engine.openFolder(Engine.workspaceDir(e.course)),
                ),
                _btn(
                  icon: Icons.folder_copy_outlined,
                  label: 'Projelerim',
                  kind: _Kind.tonal,
                  hint:
                      'Alt klasörlerdeki projelerini ve haftalık ödevlerini listeler. Yeni proje açabilir ve tarayıcıda çalıştırabilirsin.',
                  onPressed: busy ? null : () => _showProjectsDialog(context),
                ),
                if (running)
                  _btn(
                    icon: Icons.terminal,
                    label: 'Terminal',
                    hint:
                        'Konteynerin içinde komut satırı (bash) açar. composer, php ve npm komutlarını burada çalıştırırsın.',
                    onPressed: () => Engine.openContainerTerminal(e.course, e.pkg),
                  ),
                for (final a in actions)
                  _btn(
                    icon: Icons.auto_awesome,
                    label: a.label,
                    hint:
                        '${a.label}: konteynerin içinde hazır bir komut çalıştırır${a.prompt == null ? '' : ' (önce ${a.prompt!.split('(').first.trim().toLowerCase()} sorulur)'}.',
                    onPressed: busy ? null : () => _runAction(context, a),
                  ),
                if (_isDb) ...[
                  _sep(context),
                  _btn(
                    icon: Icons.backup_outlined,
                    label: 'Yedek Al',
                    hint:
                        'Veritabanındaki tabloları .sql dosyası olarak yedekler. Bir şey bozulursa geri yükleyebilirsin.',
                    onPressed: busy
                        ? null
                        : () => page._task(() =>
                            Engine.backupDatabase(e.course, e.pkg, s.log)),
                  ),
                  _btn(
                    icon: Icons.restore_page_outlined,
                    label: 'İçe Aktar',
                    hint:
                        'Daha önce aldığın ya da hocanın verdiği bir .sql dosyasını veritabanına yükler.',
                    onPressed: busy ? null : () => _importSql(context),
                  ),
                ],
                _sep(context),
                _btn(
                  icon: Icons.archive_outlined,
                  label: 'Ödevi Paketle',
                  hint:
                      'Projenin kodunu ve veritabanı yedeğini adın ve numaranla tek bir .zip dosyası yapıp Masaüstüne koyar. Teslim için hazırdır.',
                  onPressed: busy ? null : () => _exportHomeworkDialog(context),
                ),
                _btn(
                  icon: Icons.receipt_long_outlined,
                  label: 'Loglar',
                  hint:
                      'Servislerin son çıktılarını alttaki günlük panelinde gösterir. Bir şey çalışmıyorsa hatayı burada ararsın.',
                  onPressed: busy
                      ? null
                      : () => page._task(
                          () => Engine.showLogs(e.course, e.pkg, s.log)),
                ),
              ],
            ),
          ),
          // -------------------------------------------- bağlantı bilgileri
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.key_outlined, size: 14, color: cs.onSurfaceVariant),
                for (final line in infoLines) _InfoChip(text: line),
              ],
            ),
          ),
        ],
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

  Future<void> _showProjectsDialog(BuildContext context) async {
    final c = entry.course;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return FutureBuilder<List<ProjectItem>>(
            future: Engine.getProjects(c),
            builder: (ctx, snap) {
              final projects = snap.data ?? [];
              final loading = snap.connectionState == ConnectionState.waiting;

              return AlertDialog(
                title: Row(
                  children: [
                    Icon(courseIcon(c.icon), size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${c.name} - Projelerim',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 550,
                  height: 420,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: () async {
                              final created = await _createNewProjectDialog(context);
                              if (created) {
                                setDialogState(() {});
                              }
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Yeni Hafta / Proje Ekle'),
                          ),
                          const Spacer(),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _exportHomeworkDialog(context);
                            },
                            icon: const Icon(Icons.archive_outlined, size: 18),
                            label: const Text('Tümünü Paketle (.zip)'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      Expanded(
                        child: loading
                            ? const Center(child: CircularProgressIndicator())
                            : projects.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.folder_open, size: 48, color: Colors.grey),
                                          const SizedBox(height: 8),
                                          const Text(
                                            'Henüz alt proje veya hafta klasörü yok.',
                                            style: TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Tüm dosyalar doğrudan "${c.workspaceName}" ana klasöründe bulunuyor.\nYukarıdaki "Yeni Hafta / Proje Ekle" butonuyla "hafta1", "odev2" gibi ayrı klasörler açabilirsiniz.',
                                            textAlign: TextAlign.center,
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    itemCount: projects.length,
                                    separatorBuilder: (_, index) => const Divider(height: 1),
                                    itemBuilder: (ctx, idx) {
                                      final p = projects[idx];
                                      final dateStr =
                                          '${p.modified.day.toString().padLeft(2, '0')}.${p.modified.month.toString().padLeft(2, '0')}.${p.modified.year}';
                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: CircleAvatar(
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .primaryContainer,
                                          child: Icon(
                                            p.isLaravel ? Icons.rocket_launch : Icons.folder,
                                            size: 20,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onPrimaryContainer,
                                          ),
                                        ),
                                        title: Text(
                                          p.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        subtitle: Text(
                                          'Son değişiklik: $dateStr${p.isLaravel ? ' · Laravel Projesi' : ''}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        trailing: Wrap(
                                          spacing: 6,
                                          children: [
                                            if (entry.running && entry.pkg.links.isNotEmpty)
                                              IconButton(
                                                tooltip: 'Tarayıcıda Çalıştır',
                                                icon: const Icon(Icons.public, color: Colors.blue),
                                                onPressed: () {
                                                  final base = Engine.mapText(entry.course.id, entry.pkg.id,
                                                      entry.pkg.links.first.url);
                                                  final target = '$base/${p.name}/${p.entry}';
                                                  Engine.openUrl(target);
                                                },
                                              ),
                                            IconButton(
                                              tooltip: 'VS Code ile Aç',
                                              icon: const Icon(Icons.code, color: Colors.teal),
                                              onPressed: () => Engine.openInVsCode(p.path),
                                            ),
                                            IconButton(
                                              tooltip: 'Bu Ödevi Paketle (.zip)',
                                              icon: const Icon(Icons.archive, color: Colors.orange),
                                              onPressed: () {
                                                Navigator.pop(ctx);
                                                _exportHomeworkDialog(context, subprojectName: p.name);
                                              },
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Kapat'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<bool> _createNewProjectDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    String template = 'crud';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            title: const Text('Yeni Hafta / Proje Klasörü Oluştur'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Proje / Hafta Adı (boşluksuz, küçük harf):'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Örn: hafta1_giris veya odev2',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Başlangıç Şablonu:'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: template,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(
                        value: 'crud',
                        child: Text('Veritabanı / CRUD Şablonu (MariaDB bağlı)'),
                      ),
                      DropdownMenuItem(
                        value: 'blank',
                        child: Text('Temiz Başlangıç (Boş index.php)'),
                      ),
                      DropdownMenuItem(
                        value: 'laravel',
                        child: Text('Laravel Projesi (composer create-project)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setDlgState(() => template = val);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () {
                  if (nameCtrl.text.trim().isNotEmpty) {
                    Navigator.pop(ctx, true);
                  }
                },
                child: const Text('Oluştur & Başlat'),
              ),
            ],
          );
        },
      ),
    );

    if (ok == true) {
      final name = nameCtrl.text.trim();
      await page._task(() async {
        final path = await Engine.createProject(
          course: entry.course,
          projectName: name,
          template: template,
          log: page.s.log,
        );
        await Engine.openInVsCode(path);
      });
      return true;
    }
    return false;
  }

  Future<void> _exportHomeworkDialog(BuildContext context, {String? subprojectName}) async {
    final nameCtrl = TextEditingController(text: page.s.studentName);
    final noCtrl = TextEditingController(text: page.s.studentNumber);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(subprojectName != null
            ? '"$subprojectName" Ödevini Paketle (.zip)'
            : 'Ödev Teslim Paketi Oluştur (.zip)'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(subprojectName != null
                  ? '"$subprojectName" klasöründeki kodların ve veritabanı yedeğin tek bir .zip arşivi olarak masaüstüne kaydedilecek.'
                  : 'Kodların ve veritabanı yedeğin tek bir .zip arşivi olarak masaüstüne kaydedilecek.'),
              const SizedBox(height: 12),
              TextField(
                controller: noCtrl,
                decoration: const InputDecoration(
                  labelText: 'Öğrenci Numarası',
                  hintText: 'Örn: 2026101',
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
            subprojectName: subprojectName,
            log: page.s.log,
          ));
    }
  }
}

enum _Kind { filled, tonal, outlined }

/// Tıklayınca panoya kopyalanan küçük bilgi etiketi.
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return HoverHint(
      message: 'Kopyalamak için tıkla.',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                duration: const Duration(seconds: 2),
                content: Text('Kopyalandı: $text')));
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.running});
  final bool running;

  @override
  Widget build(BuildContext context) {
    final color = running ? Colors.green : Theme.of(context).colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(running ? 'Çalışıyor' : 'Durdu',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

/// Docker gerektirmeyen web dersi (Web Tasarımı) için sade kart: projeler, VS Code, klasör.
class _WebCourseCard extends StatelessWidget {
  const _WebCourseCard({required this.course, required this.state});
  final Course course;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ws = Engine.workspaceDir(course);
    const pad = EdgeInsets.symmetric(horizontal: 10);
    const density = VisualDensity(horizontal: -2, vertical: -2);
    const text = TextStyle(fontSize: 13);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(courseIcon(course.icon), size: 18, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(course.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text('HTML · CSS · JavaScript — sunucu gerekmez, projeler tarayıcıda açılır',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                HoverHint(
                  message:
                      'Projelerini listeler: yeni proje aç, tarayıcıda canlı önizle (kaydedince yenilenir) veya VS Code\'da aç.',
                  child: FilledButton.tonalIcon(
                    onPressed: () => showWebProjectsDialog(context, state, course),
                    icon: const Icon(Icons.folder_copy_outlined, size: 16),
                    label: const Text('Projelerim'),
                    style: FilledButton.styleFrom(
                        padding: pad, visualDensity: density, textStyle: text),
                  ),
                ),
                HoverHint(
                  message: 'Tüm projelerini tek pencerede VS Code\'da açar.',
                  child: OutlinedButton.icon(
                    onPressed: () => Engine.openInVsCode(ws),
                    icon: const Icon(Icons.code, size: 16),
                    label: const Text('VS Code'),
                    style: OutlinedButton.styleFrom(
                        padding: pad, visualDensity: density, textStyle: text),
                  ),
                ),
                HoverHint(
                  message: 'Proje klasörünü Dosya Gezgini\'nde açar.',
                  child: OutlinedButton.icon(
                    onPressed: () => Engine.openFolder(ws),
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('Klasör'),
                    style: OutlinedButton.styleFrom(
                        padding: pad, visualDensity: density, textStyle: text),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
