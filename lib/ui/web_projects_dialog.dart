import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../engine.dart';
import '../live_server.dart';
import '../models.dart';
import 'widgets.dart';

/// Docker gerektirmeyen web dersleri (HTML/CSS/JS) için "Projelerim" penceresi.
Future<void> showWebProjectsDialog(
    BuildContext context, AppState state, Course course) {
  return showDialog(
    context: context,
    builder: (_) => _WebProjectsDialog(state: state, course: course),
  );
}

class _WebProjectsDialog extends StatefulWidget {
  const _WebProjectsDialog({required this.state, required this.course});
  final AppState state;
  final Course course;

  @override
  State<_WebProjectsDialog> createState() => _WebProjectsDialogState();
}

class _WebProjectsDialogState extends State<_WebProjectsDialog> {
  late Future<List<ProjectItem>> projects = Engine.getProjects(widget.course);

  String get root => Engine.workspaceDir(widget.course);

  void _reload() => setState(() => projects = Engine.getProjects(widget.course));

  /// Proje klasörü dışında, doğrudan ana klasörde duran HTML dosyaları.
  List<String> get _looseHtml {
    try {
      return Directory(root)
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => RegExp(r'\.html?$', caseSensitive: false).hasMatch(n))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _preview(String folder, {String entry = ''}) async {
    try {
      final s = await LiveServer.open(folder);
      await Engine.openUrl('${s.url}$entry');
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Önizleme başlatılamadı: $e')));
      }
    }
  }

  Future<void> _create() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeni proje'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Proje adı',
                  hintText: 'Örn: hafta1, odev2, portfolyo',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
              const SizedBox(height: 8),
              Text(
                  'Boşluk ve Türkçe karakter kullanma. İçine index.html, style.css, script.js ve '
                  'açıklamalı bir README.md hazır gelir.',
                  style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Oluştur')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final path = await Engine.createProject(
          course: widget.course, projectName: name, template: 'html', log: widget.state.log);
      _reload();
      await Engine.openInVsCode(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is StateError || e is ArgumentError ? '$e'.split(': ').last : '$e')));
      }
    }
  }

  Widget _projectTile(ProjectItem p) {
    final cs = Theme.of(context).colorScheme;
    final live = LiveServer.running(p.path);
    final d = p.modified;
    String two(int n) => n.toString().padLeft(2, '0');
    final hasPage = File('${p.path}\\index.html').existsSync() || p.entry.isNotEmpty;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: cs.primaryContainer,
        child: Icon(Icons.web, size: 20, color: cs.onPrimaryContainer),
      ),
      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        live != null
            ? 'Canlı önizleme açık: ${live.url}'
            : 'Son değişiklik: ${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}'
                '${hasPage ? '' : ' · index.html yok'}',
        style: TextStyle(fontSize: 12, color: live != null ? Colors.green : null),
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          HoverHint(
            message:
                'Projeyi tarayıcıda açar (Live Server gibi). Dosyayı kaydettiğinde sayfa kendiliğinden yenilenir. '
                'Yalnızca bu bilgisayardan açılabilir.',
            child: IconButton(
              icon: Icon(Icons.public, color: live != null ? Colors.green : Colors.blue),
              onPressed: () => _preview(p.path, entry: p.entry),
            ),
          ),
          HoverHint(
            message:
                'Bu projeyi VS Code\'da açar. index.html açıkken sağ üstteki "Show Preview" ile VS Code içinde de önizleyebilirsin.',
            child: IconButton(
              icon: const Icon(Icons.code, color: Colors.teal),
              onPressed: () => Engine.openInVsCode(p.path),
            ),
          ),
          HoverHint(
            message: 'Proje klasörünü Dosya Gezgini\'nde açar (resim eklemek için).',
            child: IconButton(
              icon: const Icon(Icons.folder_open_outlined),
              onPressed: () => Engine.openFolder(p.path),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loose = _looseHtml;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
      title: Row(
        children: [
          Icon(courseIcon(widget.course.icon)),
          const SizedBox(width: 10),
          Expanded(child: Text('${widget.course.name} — Projelerim')),
          IconButton(
              tooltip: 'Kapat',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close)),
        ],
      ),
      content: SizedBox(
        width: 640,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                HoverHint(
                  message:
                      'Yeni bir proje klasörü açar (index.html, style.css, script.js ve README hazır gelir) ve VS Code\'da gösterir.',
                  child: FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Yeni proje'),
                  ),
                ),
                HoverHint(
                  message:
                      'Tüm projelerini tek pencerede VS Code\'da açar; soldaki listeden istediğin projeye geçebilirsin.',
                  child: OutlinedButton.icon(
                    onPressed: () => Engine.openInVsCode(root),
                    icon: const Icon(Icons.code, size: 18),
                    label: const Text('Hepsini VS Code\'da aç'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<ProjectItem>>(
                future: projects,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final list = snap.data!;
                  if (list.isEmpty && loose.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.folder_open, size: 44, color: Colors.grey),
                          const SizedBox(height: 8),
                          const Text('Henüz proje yok.',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('"Yeni proje" ile ilk projeni oluştur.',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    );
                  }
                  return ListView(
                    children: [
                      for (final p in list) _projectTile(p),
                      if (loose.isNotEmpty)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          leading: const CircleAvatar(child: Icon(Icons.description_outlined, size: 20)),
                          title: const Text('Ana klasördeki dosyalar'),
                          subtitle: Text(
                              '${loose.join(', ')} — bir proje klasöründe değil. Düzenli olması için "Yeni proje" ile ayrı klasöre taşıyabilirsin.',
                              style: const TextStyle(fontSize: 12)),
                          trailing: IconButton(
                            tooltip: 'Canlı önizle',
                            icon: const Icon(Icons.public, color: Colors.blue),
                            onPressed: () => _preview(root, entry: loose.first),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
