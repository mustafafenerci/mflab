import 'package:flutter/material.dart';

import 'app_state.dart';
import 'config.dart';
import 'engine.dart';
import 'tray.dart';
import 'ui/about_page.dart';
import 'ui/courses_page.dart';
import 'ui/manage_page.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Kullanıcıya özel çalışma klasörünü belirle (ayarlar da oradan okunur).
  await AppConfig.init();
  runApp(const MFLabApp());
}

class MFLabApp extends StatefulWidget {
  const MFLabApp({super.key});

  @override
  State<MFLabApp> createState() => _MFLabAppState();
}

class _MFLabAppState extends State<MFLabApp> {
  final state = AppState();
  late final tray = TrayService(state);

  @override
  void initState() {
    super.initState();
    state.init();
    tray.init();
  }

  @override
  void dispose() {
    tray.dispose();
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        title: '${AppConfig.appName} v${AppConfig.appVersion}',
        debugShowCheckedModeBanner: false,
        themeMode: state.themeMode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1F5C8F), brightness: Brightness.light),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1F5C8F), brightness: Brightness.dark),
          useMaterial3: true,
        ),
        home: Shell(state: state),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key, required this.state});
  final AppState state;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;

  AppState get state => widget.state;

  @override
  Widget build(BuildContext context) {
    if (state.catalog == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    final u = state.update;
    final pages = [
      CoursesPage(state: state),
      ManagePage(key: ValueKey('manage-${state.busy}'), state: state),
      AboutPage(state: state),
    ];
    return Scaffold(
      body: Column(
        children: [
          if (u != null && !state.updateDismissed)
            MaterialBanner(
              leading: const Icon(Icons.system_update_alt),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      'Yeni sürüm ${u.version} hazır.${u.notes.isEmpty ? '' : ' ${u.notes}'}'),
                  if (state.updateStatus != null) ...[
                    const SizedBox(height: 6),
                    Text(state.updateStatus!,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                  if (state.updating) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: state.updateProgress),
                  ],
                ],
              ),
              actions: [
                HoverHint(
                  message:
                      'Yeni sürümü indirir, GitHub\'daki SHA-256 özetiyle doğrular ve kurar. '
                      'MF Lab kısa bir süre kapanıp yeni sürümle kendiliğinden açılır; servislerin çalışmaya devam eder.',
                  child: FilledButton(
                      onPressed: state.updating ? null : state.installUpdate,
                      child: const Text('Şimdi güncelle')),
                ),
                TextButton(
                    onPressed: () => Engine.openUrl(u.url),
                    child: const Text('Sayfayı aç')),
                if (!u.mandatory && !state.updating)
                  TextButton(
                      onPressed: state.dismissUpdate,
                      child: const Text('Sonra')),
              ],
            ),
          Expanded(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (i) => setState(() => index = i),
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset('assets/images/logo.png', width: 48),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'v${AppConfig.appVersion}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: IconButton(
                          tooltip: 'Temayı Değiştir (Açık / Koyu / Sistem)',
                          icon: Icon(
                            state.themeMode == ThemeMode.dark
                                ? Icons.dark_mode_outlined
                                : state.themeMode == ThemeMode.light
                                    ? Icons.light_mode_outlined
                                    : Icons.brightness_auto_outlined,
                          ),
                          onPressed: state.cycleTheme,
                        ),
                      ),
                    ),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                        icon: Icon(Icons.school_outlined),
                        selectedIcon: Icon(Icons.school),
                        label: Text('Dersler')),
                    NavigationRailDestination(
                        icon: Icon(Icons.dns_outlined),
                        selectedIcon: Icon(Icons.dns),
                        label: Text('Yönetim')),
                    NavigationRailDestination(
                        icon: Icon(Icons.info_outline),
                        selectedIcon: Icon(Icons.info),
                        label: Text('Hakkında')),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: pages[index]),
              ],
            ),
          ),
          if (state.logVisible) LogPanel(state: state),
        ],
      ),
    );
  }
}
