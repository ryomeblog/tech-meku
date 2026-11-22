import 'package:flutter/material.dart';

import '../core/techmeku_icon.dart';
import '../services/share_receiver.dart';
import 'common/widgets.dart';
import 'home/home_page.dart';
import 'posts/editor_page.dart';
import 'posts/my_posts_page.dart';
import 'profile/profile_page.dart';
import 'settings/settings_page.dart';
import 'stock/url_save_sheet.dart';

/// ボトムナビ：ホーム ／ 自分の投稿 ／ ＋新規投稿 ／ プロフィール ／ 設定
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  int _myPostsVisit = 0;

  @override
  void initState() {
    super.initState();
    ShareReceiver.instance.text.addListener(_onShared);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onShared());
  }

  @override
  void dispose() {
    ShareReceiver.instance.text.removeListener(_onShared);
    super.dispose();
  }

  /// 共有メニューから URL を受け取ったら、ホームの上に S17 を開く（v2.4）
  void _onShared() {
    final text = ShareReceiver.instance.text.value;
    if (text == null || !mounted) return;
    ShareReceiver.instance.clear();
    Navigator.of(context).popUntil((r) => r.isFirst);
    UrlSaveSheet.show(context, initialText: text);
  }

  void _select(int i) {
    if (i == 2) {
      // ＋新規投稿は投稿エディタを直接開く（設計判断 #13）
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditorPage()));
      return;
    }
    setState(() {
      // 自分の投稿は開くたびに読み込み直す（他の画面でのコメント・いいねを反映）
      if (i == 1) _myPostsVisit++;
      _index = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    NavigationDestination d(I icon, String label, int i) => NavigationDestination(
          icon: TechMekuIcon(icon, size: 24),
          selectedIcon: TechMekuIcon(icon, size: 24, active: true),
          label: label,
          tooltip: label,
        );
    return Scaffold(
      body: IndexedStack(index: _index, children: [
        const HomePage(),
        MyPostsPage(key: ValueKey(_myPostsVisit)),
        const SizedBox(),
        const ProfilePage(),
        const SettingsPage(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          d(I.home, 'ホーム', 0),
          d(I.file_text, '自分の投稿', 1),
          d(I.plus_square, '新規投稿', 2),
          d(I.user, 'プロフィール', 3),
          d(I.settings, '設定', 4),
        ],
      ),
    );
  }
}
