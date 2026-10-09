import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../engine.dart';

IconData courseIcon(String name) {
  switch (name) {
    case 'palette':
      return Icons.palette_outlined;
    case 'code':
      return Icons.code;
    case 'storage':
      return Icons.storage_outlined;
    default:
      return Icons.school_outlined;
  }
}

/// Kurulum günlüğü ve hata yardım kartı.
class LogPanel extends StatefulWidget {
  const LogPanel({super.key, required this.state});
  final AppState state;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final scroll = ScrollController();

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
    });
    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: const Color(0xFF0F1419),
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          Container(
            color: const Color(0xFF1A2129),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 16, color: Colors.white70),
                const SizedBox(width: 8),
                Text(s.busy ? 'Çalışıyor...' : 'Günlük',
                    style: const TextStyle(color: Colors.white70)),
                if (s.busy) ...[
                  const SizedBox(width: 10),
                  const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ],
                const Spacer(),
                IconButton(
                  tooltip: 'Günlüğü kopyala (hocana göndermek için)',
                  iconSize: 18,
                  color: Colors.white70,
                  icon: const Icon(Icons.copy_all),
                  onPressed: () => _copy(context, s),
                ),
                IconButton(
                  tooltip: 'Kapat',
                  iconSize: 18,
                  color: Colors.white70,
                  icon: const Icon(Icons.close),
                  onPressed: s.busy ? null : s.hideLog,
                ),
              ],
            ),
          ),
          if (s.lastHelp != null) _HelpCard(help: s.lastHelp!),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.all(12),
              itemCount: s.logs.length,
              itemBuilder: (_, i) => SelectableText(
                s.logs[i],
                style: const TextStyle(
                    color: Color(0xFF7EE787),
                    fontFamily: 'Consolas',
                    fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, AppState s) async {
    await Clipboard.setData(ClipboardData(text: s.logs.join('\n')));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Günlük panoya kopyalandı.')));
    }
  }
}

class _HelpCard extends StatelessWidget {
  const _HelpCard({required this.help});
  final dynamic help;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF3B2A12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade700),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline, color: Colors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(help.title as String,
                    style: const TextStyle(
                        color: Colors.amber, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(help.explain as String,
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => Engine.openUrl(help.url as String),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Kaynağı oku'),
          ),
        ],
      ),
    );
  }
}
