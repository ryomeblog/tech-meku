import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// 端末に保存する設定（shared_preferences）。興味タグもここ（サーバーには送らない）
class Settings extends ChangeNotifier {
  Settings._();
  static final Settings instance = Settings._();

  late SharedPreferences _p;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  /// バックグラウンド isolate では他 isolate の書き込みを読むため再読込する
  Future<void> reload() => _p.reload();

  void _changed() => notifyListeners();

  // ---- 興味タグ（最大10）
  static const maxInterestTags = 10;
  List<String> get interestTags => _p.getStringList('interestTags') ?? const [];
  Future<void> setInterestTags(List<String> tags) async {
    await _p.setStringList('interestTags', tags.take(maxInterestTags).toList());
    _changed();
  }

  bool get onboarded => _p.getBool('onboarded') ?? false;
  Future<void> setOnboarded() async {
    await _p.setBool('onboarded', true);
    _changed();
  }

  /// 未設定時のランダムタグ（直前の起動で選ばれたもの。定期自動DLが使う）
  List<String> get randomTags => _p.getStringList('randomTags') ?? const [];
  Future<void> setRandomTags(List<String> tags) => _p.setStringList('randomTags', tags);

  // ---- DL
  int get fetchCount => _p.getInt('fetchCount') ?? 50;
  Future<void> setFetchCount(int v) async {
    await _p.setInt('fetchCount', v);
    _changed();
  }

  bool siteEnabled(SourceType s) => _p.getBool('site_${s.name}') ?? true;
  Future<void> setSiteEnabled(SourceType s, bool v) async {
    await _p.setBool('site_${s.name}', v);
    _changed();
  }

  List<SourceType> get enabledSites => SourceType.external.where(siteEnabled).toList();

  bool get autoDl => _p.getBool('autoDl') ?? true;
  Future<void> setAutoDl(bool v) async {
    await _p.setBool('autoDl', v);
    _changed();
  }

  bool get wifiOnly => _p.getBool('wifiOnly') ?? true;
  Future<void> setWifiOnly(bool v) async {
    await _p.setBool('wifiOnly', v);
    _changed();
  }

  // ---- ストレージ
  int get storageLimitGb => _p.getInt('storageLimitGb') ?? 3;
  Future<void> setStorageLimitGb(int v) async {
    await _p.setInt('storageLimitGb', v);
    _changed();
  }

  int get storageLimitBytes => storageLimitGb * 1024 * 1024 * 1024;

  // ---- 表示
  ThemeMode get themeMode => ThemeMode.values.firstWhere((m) => m.name == _p.getString('themeMode'), orElse: () => ThemeMode.system);
  Future<void> setThemeMode(ThemeMode m) async {
    await _p.setString('themeMode', m.name);
    _changed();
  }

  /// 文字サイズ（全文表示とカードの倍率）
  double get textScale => _p.getDouble('textScale') ?? 1.0;
  Future<void> setTextScale(double v) async {
    await _p.setDouble('textScale', v);
    _changed();
  }

  // ---- 一括DLの状態
  int? get lastBatchAt => _p.getInt('lastBatchAt');
  Future<void> setLastBatchAt(int v) => _p.setInt('lastBatchAt', v);

  /// 自動補充で新規0件だったとき、この時刻まで再実行しない（設計判断 #9）
  int get swipeCooldownUntil => _p.getInt('swipeCooldownUntil') ?? 0;
  Future<void> setSwipeCooldownUntil(int v) => _p.setInt('swipeCooldownUntil', v);

  /// 自動補充の初回にモバイル通信量の案内を出したか（設計判断 #15）
  bool get mobileNoticeShown => _p.getBool('mobileNoticeShown') ?? false;
  Future<void> setMobileNoticeShown() => _p.setBool('mobileNoticeShown', true);

  /// 投稿前の利用規約への同意（設計判断 #3）
  bool get termsAccepted => _p.getBool('termsAccepted') ?? false;
  Future<void> setTermsAccepted() async {
    await _p.setBool('termsAccepted', true);
    _changed();
  }

  /// サイトごとの連続失敗回数（「仕様変更の可能性」の表示に使う）
  int failures(SourceType s) => _p.getInt('fail_${s.name}') ?? 0;
  Future<void> setFailures(SourceType s, int n) => _p.setInt('fail_${s.name}', n);

  /// Qiita の 429 による一時停止の期限
  int get qiitaPausedUntil => _p.getInt('qiitaPausedUntil') ?? 0;
  Future<void> setQiitaPausedUntil(int v) => _p.setInt('qiitaPausedUntil', v);

  // ---- 汎用 JSON
  Map<String, dynamic>? getJson(String key) {
    final s = _p.getString(key);
    return s == null ? null : jsonDecode(s) as Map<String, dynamic>;
  }

  Future<void> setJson(String key, Map<String, dynamic> v) => _p.setString(key, jsonEncode(v));
}
