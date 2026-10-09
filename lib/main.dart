import 'package:flutter/material.dart';

import 'app_state.dart';
import 'config.dart';
import 'engine.dart';
import 'ui/about_page.dart';
import 'ui/courses_page.dart';
import 'ui/manage_page.dart';
import 'ui/widgets.dart';

void main() => runApp(const MFLabApp());

class MFLabApp extends StatefulWidget {
  const MFLabApp({super.key});

  @override
  State<MFLabApp> createState() => _MFLabAppState();
}

class _MFLabAppState extends State<MFLabApp> {
  final state = AppState();

  @override
  void initState() {
    super.initState();
    state.init();
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        title: AppConfig.appName,
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
              content: Text(
                  'Yeni sürüm ${u.version} hazır.${u.notes.isEmpty ? '' : ' ${u.notes}'}'),
              actions: [
                FilledButton(
                    onPressed: () => Engine.openUrl(u.url),
                    child: const Text('İndir')),
                if (!u.mandatory)
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
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Image.asset('assets/images/logo.png', width: 52),
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
