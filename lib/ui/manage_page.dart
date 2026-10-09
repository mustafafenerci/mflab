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
                if (e.running)
                  for (final a in e.pkg.actions)
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => _runAction(context, a),
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: Text(a.label),
                    ),
                TextButton.icon(
                  onPressed: busy ? null : () => _confirmRemove(context),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Kaldır'),
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

  Future<void> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Servisleri kaldır?'),
        content: const Text(
            'Konteynerler silinir. Çalışma klasöründeki dosyaların ve veritabanı verilerin korunur. İstersen sonra Dersler sayfasından yeniden kurabilirsin.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kaldır')),
        ],
      ),
    );
    if (ok == true) {
      await page
          ._task(() => Engine.remove(entry.course, entry.pkg, page.s.log));
    }
  }
}
