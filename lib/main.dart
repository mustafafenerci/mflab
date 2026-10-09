import 'package:flutter/material.dart';

import 'app_state.dart';
import 'config.dart';
import 'engine.dart';
import 'ui/about_page.dart';
import 'ui/courses_page.dart';
import 'ui/manage_page.dart';
import 'ui/widgets.dart';

void main() => runApp(const MFLabApp());

class MFLabApp extends StatelessWidget {
  const MFLabApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1F5C8F), brightness: Brightness.light),
          useMaterial3: true,
        ),
        home: const Shell(),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final state = AppState();
  int index = 0;

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
      builder: (context, _) {
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
      },
    );
  }
}
