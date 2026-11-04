import 'package:flutter/material.dart';

import '../core/techmeku_icon.dart';
import 'common/widgets.dart';
import 'home/home_page.dart';
import 'posts/editor_page.dart';
import 'posts/my_posts_page.dart';
import 'profile/profile_page.dart';
import 'settings/settings_page.dart';

/// ボトムナビ：ホーム ／ 自分の投稿 ／ ＋新規投稿 ／ プロフィール ／ 設定
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  int _myPostsVisit = 0;

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
