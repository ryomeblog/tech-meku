import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 共有メニュー（Android の ACTION_SEND）から受け取ったテキストを通知する（v2.4、設計書 8.6）
class ShareReceiver {
  ShareReceiver._();
  static final ShareReceiver instance = ShareReceiver._();

  static const _channel = MethodChannel('techmeku/share');

  /// 受け取ったテキスト。画面側が受け取ったら clear する
  final ValueNotifier<String?> text = ValueNotifier(null);

  Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText' && call.arguments is String) text.value = call.arguments as String;
    });
    try {
      final t = await _channel.invokeMethod<String>('getInitialSharedText');
      if (t != null && t.isNotEmpty) text.value = t;
    } on MissingPluginException {
      // テストや Android 以外では何もしない
    } on PlatformException {
      // 取得できなくてもアプリは動かす
    }
  }

  void clear() => text.value = null;
}
