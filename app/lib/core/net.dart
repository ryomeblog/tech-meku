import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// 通信状態。オフライン判定と Wi-Fi 判定に使う
class NetStatus extends ChangeNotifier {
  NetStatus._();
  static final NetStatus instance = NetStatus._();

  final _conn = Connectivity();
  List<ConnectivityResult> _results = const [];
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool get online => _results.any((r) => r != ConnectivityResult.none);
  bool get onWifi => _results.contains(ConnectivityResult.wifi) || _results.contains(ConnectivityResult.ethernet);

  Future<void> init() async {
    try {
      _results = await _conn.checkConnectivity();
    } catch (_) {
      _results = const [ConnectivityResult.wifi];
    }
    _sub ??= _conn.onConnectivityChanged.listen((r) {
      final was = online;
      _results = r;
      if (was != online) notifyListeners();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
