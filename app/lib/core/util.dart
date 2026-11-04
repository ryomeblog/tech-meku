import 'package:uuid/uuid.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

int nowMs() => DateTime.now().millisecondsSinceEpoch;

const hourMs = 60 * 60 * 1000;
const dayMs = 24 * hourMs;

/// URL の正規化（doc/design.md 6.5）：クエリ・フラグメントを除去し、末尾スラッシュをなくす
String normalizeUrl(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null) return url.trim();
  var path = u.path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return Uri(scheme: u.scheme.toLowerCase(), host: u.host.toLowerCase(), port: u.hasPort ? u.port : null, path: path).toString();
}

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

String two(int n) => n.toString().padLeft(2, '0');

String formatDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}/${two(d.month)}/${two(d.day)}';
}

String formatClock(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
  return sameDay ? '今日 ${d.hour}:${two(d.minute)}' : '${d.month}/${d.day} ${d.hour}:${two(d.minute)}';
}

/// 「あと 3時間12分」
String remaining(int untilMs, {int? now}) {
  final diff = untilMs - (now ?? nowMs());
  if (diff <= 0) return '公開終了';
  final h = diff ~/ hourMs;
  final m = (diff % hourMs) ~/ 60000;
  if (h >= 24) return 'あと ${h ~/ 24}日${h % 24}時間';
  if (h > 0) return 'あと $h時間$m分';
  return 'あと $m分';
}

/// 「HH:MM 後」形式（投稿上限のエラー表示用）
String waitText(int untilMs) {
  final diff = (untilMs - nowMs()).clamp(0, 1 << 62);
  final h = diff ~/ hourMs;
  final m = ((diff % hourMs) + 59999) ~/ 60000;
  return '$h:${two(m)}';
}

String relativeTime(int ms) {
  final diff = nowMs() - ms;
  if (diff < 60000) return 'たった今';
  if (diff < hourMs) return '${diff ~/ 60000}分前';
  if (diff < dayMs) return '${diff ~/ hourMs}時間前';
  if (diff < 7 * dayMs) return '${diff ~/ dayMs}日前';
  return formatDate(ms);
}
