import 'package:flutter/material.dart';
import 'techmeku_icon.dart';

/// Place this on the right edge of the vertical-swipe article card.
class TechMekuActionRail extends StatelessWidget {
  const TechMekuActionRail({super.key, required this.isCommunityPost,
    required this.liked, required this.saved,
    required this.onLike, required this.onDownload, required this.onShare,
    this.onComment, this.onOriginal, this.onReport});
  final bool isCommunityPost, liked, saved;
  final VoidCallback onLike, onDownload, onShare;
  final VoidCallback? onComment, onOriginal, onReport;

  @override
  Widget build(BuildContext context) {
    Widget action(TechMekuIconName icon, String label, VoidCallback? onTap, {bool active=false}) {
      return SizedBox(
        width: 54,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Material(color: const Color(0xFF1C2431), shape: const CircleBorder(),
            child: InkWell(customBorder: const CircleBorder(), onTap: onTap,
              child: SizedBox(width: 44, height: 44,
                child: Center(child: TechMekuIcon(name: icon, active: active, size: 24))))),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFFE5E7EB))),
        ]),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      action(liked ? TechMekuIconName.heart_filled : TechMekuIconName.heart, 'いいね', onLike, active: liked),
      if (isCommunityPost) ...[const SizedBox(height: 10), action(TechMekuIconName.comment, 'コメント', onComment)],
      const SizedBox(height: 10),
      action(saved ? TechMekuIconName.check_circle : TechMekuIconName.download,
        saved ? '保存済' : 'DL', onDownload, active: saved),
      const SizedBox(height: 10), action(TechMekuIconName.share, '共有', onShare),
      if (isCommunityPost) ...[
        const SizedBox(height: 10), action(TechMekuIconName.flag, '通報', onReport),
      ] else ...[
        const SizedBox(height: 10), action(TechMekuIconName.external_link, '元記事', onOriginal),
      ]
    ]);
  }
}
