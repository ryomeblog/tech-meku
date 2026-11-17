import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:techmeku/core/config.dart';

void main() {
  test('設定画面のバージョンと pubspec.yaml のバージョンが一致する', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*([0-9.]+)\+\d+', multiLine: true).firstMatch(pubspec);
    expect(m, isNotNull);
    expect(AppConfig.appVersion, m!.group(1));
  });
}
