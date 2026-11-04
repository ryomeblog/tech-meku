// ignore_for_file: constant_identifier_names
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'theme.dart';

/// TechMeku Icon Kit のアイコン名。SVG は assets/icons/default/ にある。
enum TechMekuIconName {
  home,
  file_text,
  plus_square,
  user,
  settings,
  layers,
  bookmark,
  bookmark_filled,
  users,
  heart,
  heart_filled,
  comment,
  download,
  check_circle,
  share,
  external_link,
  flag,
  search,
  more,
  back,
  close,
  check,
  edit,
  trash,
  filter,
  sliders,
  calendar,
  tag,
  eye,
  eye_off,
  book_open,
  library,
  database,
  refresh,
  wifi,
  wifi_off,
  loader,
  info,
  warning,
  clock,
  plus,
  minus,
  chevron_down,
  chevron_right,
  upload,
  image,
  code,
  preview,
  send,
  log_in,
  log_out,
  shield,
  user_x,
  rotate_ccw,
  lock,
  smartphone,
  cloud_off,
  alert_octagon,
  help,
  list,
  arrow_up,
  file_check,
}

/// TechMeku Icon Kit のアイコン。
///
/// Icon Kit の SVG は色が固定（ダーク背景向け）のため、default の SVG を読み込み
/// テーマ色で着色する（doc/design.md 8.6）。[color] を渡すとその色で描く。
class TechMekuIcon extends StatelessWidget {
  const TechMekuIcon(this.name, {super.key, this.active = false, this.muted = false, this.size = 24, this.color, this.semanticLabel});
  final TechMekuIconName name;
  final bool active;
  final bool muted;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = TmColors.of(context);
    final c = color ?? (active ? t.active : (muted ? t.muted : IconTheme.of(context).color ?? t.ink));
    return SvgPicture.asset(
      'assets/icons/default/${name.name}.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
    );
  }
}
