import 'package:flutter/material.dart';

import '../../core/net.dart';
import '../../core/techmeku_icon.dart';
import '../../core/theme.dart';
import '../common/widgets.dart';
import 'posts_feed.dart';
import 'recommend_feed.dart';
import 'stock_feed.dart';

/// ホーム：おすすめ ／ ストック ／ みんなの投稿（2.1）
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  // 起動時はおすすめ。起動時にオフラインなら自動でストック
  late final TabController _tabs = TabController(length: 3, vsync: this, initialIndex: NetStatus.instance.online ? 0 : 1);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TmColors.of(context);
    Tab tab(I icon, String label, int i) => Tab(
          child: AnimatedBuilder(
            animation: _tabs,
            builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
              TechMekuIcon(icon, size: 18, active: _tabs.index == i),
              const SizedBox(width: 4),
              Text(label),
            ]),
          ),
        );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          TabBar(
            controller: _tabs,
            labelColor: c.active,
            unselectedLabelColor: c.ink,
            indicatorColor: c.active,
            dividerColor: c.line,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            tabs: [tab(I.layers, 'おすすめ', 0), tab(I.bookmark, 'ストック', 1), tab(I.users, 'みんなの投稿', 2)],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              physics: const NeverScrollableScrollPhysics(), // 縦スワイプと干渉させない
              children: const [RecommendFeed(), StockFeed(), PostsFeed()],
            ),
          ),
        ]),
      ),
    );
  }
}
