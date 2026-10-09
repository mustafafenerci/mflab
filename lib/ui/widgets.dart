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
                if (!s.busy && s.logs.isNotEmpty) _AskAiButton(state: s),
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

/// Günlüğü hazır bir Türkçe istemle panoya kopyalar ve seçilen yapay zekâ sitesini açar.
class _AskAiButton extends StatelessWidget {
  const _AskAiButton({required this.state});
  final AppState state;

  static const _targets = <(String, String)>[
    ('Claude', 'https://claude.ai/new'),
    ('ChatGPT', 'https://chatgpt.com/'),
    ('Gemini', 'https://gemini.google.com/app'),
    ('Copilot', 'https://copilot.microsoft.com/'),
  ];

  @override
  Widget build(BuildContext context) {
    final failed = state.installFailed;
    return PopupMenuButton<String>(
      tooltip: 'Sorunu yapay zekâya sor',
      onSelected: (url) async {
        await Clipboard.setData(ClipboardData(text: state.buildAiPrompt()));
        await Engine.openUrl(url);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              duration: Duration(seconds: 8),
              content: Text(
                  'Sorun özeti panoya kopyalandı. Açılan sayfada sohbet kutusuna yapıştır (Ctrl+V) ve gönder.')));
        }
      },
      itemBuilder: (_) => [
        for (final t in _targets)
          PopupMenuItem(value: t.$2, child: Text('${t.$1} ile sor')),
      ],
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: failed ? Colors.amber.shade700 : Colors.transparent,
          border: Border.all(
              color: failed ? Colors.amber.shade700 : Colors.white38),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome,
              size: 15, color: failed ? Colors.black : Colors.white70),
          const SizedBox(width: 6),
          Text('Yapay zekâya sor',
              style: TextStyle(
                  fontSize: 12,
                  color: failed ? Colors.black : Colors.white70)),
        ]),
      ),
    );
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

/// Üzerine gelip birkaç saniye bekleyince açıklama gösteren sarmalayıcı.
/// Hızlı açılan, kısa ipuçları için normal `tooltip:` kullanılır; bu, uzun açıklamalar içindir.
class HoverHint extends StatelessWidget {
  const HoverHint({super.key, required this.message, required this.child});
  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: message,
      waitDuration: const Duration(seconds: 4),
      showDuration: const Duration(seconds: 12),
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: TextStyle(color: cs.onInverseSurface, fontSize: 13, height: 1.35),
      child: child,
    );
  }
}
