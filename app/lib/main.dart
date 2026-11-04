import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/net.dart';
import 'core/settings.dart';
import 'core/theme.dart';
import 'services/auth.dart';
import 'services/scheduler.dart';
import 'services/stock.dart';
import 'services/tags.dart';
import 'ui/shell.dart';
import 'ui/tags/tag_select_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Settings.instance.init();
  await NetStatus.instance.init();
  await StockRepo.instance.init();
  await AuthService.instance.init();
  await TagService.instance.onLaunch();
  // 起動時に期限切れのキャッシュを削除（5.9）
  await StockRepo.instance.purgeExpiredCache();
  runApp(const TechMekuApp());
  Scheduler.apply();
  AuthService.instance.refresh();
}

class TechMekuApp extends StatelessWidget {
  const TechMekuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Settings.instance,
      builder: (context, _) {
        final s = Settings.instance;
        return MaterialApp(
          title: 'TechMeku',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: s.themeMode,
          builder: (context, child) {
            final dark = Theme.of(context).brightness == Brightness.dark;
            SystemChrome.setSystemUIOverlayStyle(dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark);
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(s.textScale.clamp(0.8, 1.3))),
              child: child!,
            );
          },
          home: const _Root(),
        );
      },
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _onboarded = Settings.instance.onboarded;

  @override
  Widget build(BuildContext context) {
    // 初回起動で興味タグを選ぶ（スキップ可）
    if (!_onboarded) return TagSelectPage(onboarding: true, onDone: () => setState(() => _onboarded = true));
    return const Shell();
  }
}
