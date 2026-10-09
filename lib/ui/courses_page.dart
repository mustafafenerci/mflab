import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../engine.dart';
import '../models.dart';
import 'web_projects_dialog.dart';
import 'widgets.dart';

class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key, required this.state});
  final AppState state;

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  Course? course;
  final selected = <String>{};

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    final cat = s.catalog;
    if (cat != null && s.lastCourseId != null) {
      final last = cat.courses.where((c) => c.id == s.lastCourseId).firstOrNull;
      if (last != null) {
        course = last;
        selected.addAll(last.packages);
      }
    }
  }

  void pick(Course c) {
    setState(() {
      course = c;
      selected
        ..clear()
        ..addAll(c.packages);
    });
    s.setLastCourse(c.id);
  }

  @override
  Widget build(BuildContext context) {
    final cat = s.catalog!;
    return Row(
      children: [
        SizedBox(
          width: 320,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('1. Dersini seç',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final c in cat.courses)
                Card(
                  elevation: course == c ? 2 : 0,
                  color: course == c
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  child: ListTile(
                    leading: Icon(courseIcon(c.icon)),
                    title: Text(c.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(c.description),
                    onTap: s.busy ? null : () => pick(c),
                  ),
                ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: course == null
              ? const _Welcome()
              : _CourseDetail(
                  state: s,
                  course: course!,
                  selected: selected,
                  onChanged: () => setState(() {}),
                ),
        ),
      ],
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/images/logo.png', width: 120),
          const SizedBox(height: 16),
          Text('MF Lab\'e hoş geldin',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Soldan dersini seç, gerekli yazılımları senin için kuralım.'),
        ],
      ),
    );
  }
}

class _CourseDetail extends StatelessWidget {
  const _CourseDetail({
    required this.state,
    required this.course,
    required this.selected,
    required this.onChanged,
  });

  final AppState state;
  final Course course;
  final Set<String> selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final cat = state.catalog!;
    final pkgs = course.packages.map((id) => cat.packages[id]).whereType<LabPackage>();
    final ready = state.finishedCourse?.id == course.id;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(course.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(course.description),
        const SizedBox(height: 16),
        Text('2. Kurulacak yazılımlar',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
            'Her yazılımın altında neden kurulduğu yazıyor. Merak ettiğin satırı aç.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        for (final p in pkgs)
          Card(
            child: ExpansionTile(
              leading: Checkbox(
                value: selected.contains(p.id),
                onChanged: state.busy
                    ? null
                    : (v) {
                        v! ? selected.add(p.id) : selected.remove(p.id);
                        onChanged();
                      },
              ),
              title: Text(p.name),
              subtitle: Text(p.isDocker ? 'Docker ile kurulur' : 'Araç denetimi'),
              childrenPadding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Neden kuruyoruz?',
                        style: Theme.of(context).textTheme.labelLarge)),
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerLeft, child: Text(p.why)),
              ],
            ),
          ),
        if (course.extensions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('VS Code eklentileri (otomatik kurulur)',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in course.extensions)
                Chip(
                    label: Text(e.split('.').last),
                    visualDensity: VisualDensity.compact),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.folder_outlined, size: 18),
            const SizedBox(width: 6),
            Expanded(
                child: Text('Çalışma klasörün: ${Engine.workspaceDir(course)}')),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: state.busy || selected.isEmpty
                  ? null
                  : () => state.install(course, selected),
              icon: const Icon(Icons.download),
              label: Text(state.busy ? 'Kuruluyor...' : '3. Kur'),
              style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
            ),
            if (course.isStaticWeb &&
                (state.settings.courseInstallDates.containsKey(course.id) ||
                    Directory(Engine.workspaceDir(course)).existsSync()))
              HoverHint(
                message:
                    'Projelerini listeler: yeni proje aç, tarayıcıda canlı önizle veya VS Code\'da aç.',
                child: FilledButton.tonalIcon(
                  onPressed: () => showWebProjectsDialog(context, state, course),
                  icon: const Icon(Icons.folder_copy_outlined),
                  label: const Text('Projelerim'),
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16)),
                ),
              ),
          ],
        ),
        if (ready) _ReadyCard(course: course, cat: cat, state: state),
      ],
    );
  }
}

class _ReadyCard extends StatelessWidget {
  const _ReadyCard({required this.course, required this.cat, required this.state});
  final Course course;
  final Catalog cat;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final links = course.packages
        .map((id) => cat.packages[id])
        .whereType<LabPackage>()
        .expand((p) => p.links.map((l) =>
            PackageLink(l.name, Engine.mapText(course.id, p.id, l.url))))
        .toList();
    return Card(
      margin: const EdgeInsets.only(top: 20),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🎉 Hazır!', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text(
                'Masaüstünde "MF Lab" klasörü oluştu. Buradan da hemen başlayabilirsin:'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (course.isStaticWeb)
                  FilledButton.icon(
                    onPressed: () => showWebProjectsDialog(context, state, course),
                    icon: const Icon(Icons.folder_copy_outlined),
                    label: const Text('Projelerim'),
                  ),
                for (final l in links)
                  FilledButton.tonalIcon(
                    onPressed: () => Engine.openUrl(l.url),
                    icon: const Icon(Icons.public),
                    label: Text(l.name),
                  ),
                OutlinedButton.icon(
                  onPressed: () => Engine.openFolder(Engine.workspaceDir(course)),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Klasörü aç'),
                ),
                if (course.packages.contains('vscode'))
                  OutlinedButton.icon(
                    onPressed: () =>
                        Engine.openInVsCode(Engine.workspaceDir(course)),
                    icon: const Icon(Icons.code),
                    label: const Text('VS Code ile aç'),
                  ),
              ],
            ),
            if (course.packages.any((id) => cat.packages[id]?.isDocker ?? false)) ...[
              const SizedBox(height: 12),
              const Text(
                '💡 İpucu: Sol menüdeki "Yönetim" sekmesinden servisleri dilediğin zaman başlatıp durdurabilir, logları görebilirsin.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
