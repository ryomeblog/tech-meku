import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/config.dart';
import 'api.dart';

/// Google ログインとセッション（doc/design.md 7.3）
///
/// アプリは ID トークンだけをサーバーに送る。メール・氏名・画像はアプリでも保存しない。
class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _storage = FlutterSecureStorage();
  static const _kToken = 'session';
  static const _kNick = 'nickname';

  bool _gsiReady = false;
  String? nickname;
  bool banned = false;
  int activePostCount = 0;

  bool get loggedIn => Api.instance.token != null;

  Future<void> init() async {
    Api.instance.token = await _storage.read(key: _kToken);
    nickname = await _storage.read(key: _kNick);
    Api.instance.onUnauthorized = () => logout();
  }

  Future<void> _ensureGsi() async {
    if (_gsiReady) return;
    await GoogleSignIn.instance.initialize(serverClientId: AppConfig.googleServerClientId);
    _gsiReady = true;
  }

  /// Google でログイン。キャンセル時は false
  Future<bool> login() async {
    await _ensureGsi();
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      throw ApiException(0, 'GOOGLE', 'Google ログインに失敗しました（${e.code.name}）');
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) throw ApiException(0, 'GOOGLE', 'Google の ID トークンを取得できませんでした');
    final (token, nick) = await Api.instance.loginWithGoogle(idToken);
    // Google 側のセッションは保持しない（次回もアカウント選択から）
    await GoogleSignIn.instance.signOut().catchError((_) {});
    Api.instance.token = token;
    nickname = nick;
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kNick, value: nick);
    await refresh();
    return true;
  }

  Future<void> refresh() async {
    if (!loggedIn) return;
    try {
      final me = await Api.instance.me();
      nickname = me['nickname'] as String?;
      banned = me['banned'] as bool? ?? false;
      activePostCount = me['activePostCount'] as int? ?? 0;
      await _storage.write(key: _kNick, value: nickname);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> updateNickname(String n) async {
    await Api.instance.updateNickname(n);
    nickname = n;
    await _storage.write(key: _kNick, value: n);
    notifyListeners();
  }

  Future<void> logout() async {
    Api.instance.token = null;
    nickname = null;
    banned = false;
    activePostCount = 0;
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kNick);
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    await Api.instance.deleteAccount();
    await logout();
  }
}
