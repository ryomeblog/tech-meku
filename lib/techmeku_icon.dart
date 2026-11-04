import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// All TechMeku icon names. SVG files are in assets/icons/{variant}/.
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

class TechMekuIcon extends StatelessWidget {
  const TechMekuIcon({super.key, required this.name, this.active = false, this.muted = false, this.size = 24, this.semanticLabel});
  final TechMekuIconName name;
  final bool active;
  final bool muted;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final variant = active ? 'active' : (muted ? 'muted' : 'default');
    return SvgPicture.asset(
      'assets/icons/$variant/${name.name}.svg',
      width: size,
      height: size,
      semanticsLabel: semanticLabel,
    );
  }
}
