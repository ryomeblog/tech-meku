import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../core/net.dart';
import '../core/settings.dart';
import '../models/models.dart';
import 'batch.dart';
import 'stock.dart';

const _taskName = 'techmeku.dailyDownload';

/// 定期自動DL（doc/design.md 5.8）。バックグラウンド isolate で動く
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Settings.instance.init();
      await Settings.instance.reload();
      if (!Settings.instance.autoDl) return true;
      await NetStatus.instance.init();
      await StockRepo.instance.init();
      await StockRepo.instance.purgeExpiredCache();
      if (NetStatus.instance.online) await BatchRunner.instance.run(BatchTrigger.scheduled);
      return true;
    } catch (_) {
      return false;
    }
  });
}

class Scheduler {
  static bool _initialized = false;

  /// 設定に合わせて 1 日 1 回のタスクを登録し直す（「Wi-Fi時のみ」なら unmetered）
  static Future<void> apply() async {
    try {
      if (!_initialized) {
        await Workmanager().initialize(callbackDispatcher);
        _initialized = true;
      }
      final s = Settings.instance;
      if (!s.autoDl) {
        await Workmanager().cancelByUniqueName(_taskName);
        return;
      }
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: const Duration(days: 1),
        initialDelay: const Duration(hours: 1),
        constraints: Constraints(networkType: s.wifiOnly ? NetworkType.unmetered : NetworkType.connected, requiresStorageNotLow: true),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } catch (e) {
      debugPrint('scheduler: $e');
    }
  }
}
