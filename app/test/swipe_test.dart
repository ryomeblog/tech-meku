import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techmeku/ui/common/widgets.dart';

void main() {
  late PageController controller;

  Future<void> pump(WidgetTester tester) async {
    controller = PageController();
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        height: 800,
        child: SwipePager(
          controller: controller,
          itemCount: 5,
          itemBuilder: (_, i) => Center(child: Text('page $i')),
        ),
      ),
    ));
  }

  // ゆっくり（勢いなし）ドラッグして離す
  Future<void> slowDrag(WidgetTester tester, double dy) async {
    final g = await tester.startGesture(const Offset(200, 400));
    for (var i = 1; i <= 20; i++) {
      await g.moveBy(Offset(0, dy / 20));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets('ゆっくりでも画面の 25% 動かせば次のページへ進む', (tester) async {
    await pump(tester);
    await slowDrag(tester, -0.25 * 600);
    expect(controller.page, 1);
  });

  testWidgets('10% だけなら元のページに戻る', (tester) async {
    await pump(tester);
    await slowDrag(tester, -0.10 * 600);
    expect(controller.page, 0);
  });

  testWidgets('前のページへも 25% で戻れる', (tester) async {
    await pump(tester);
    controller.jumpToPage(2);
    await tester.pump();
    await slowDrag(tester, 0.25 * 600);
    expect(controller.page, 1);
  });

  testWidgets('強く払っても 1 ページずつ進む', (tester) async {
    await pump(tester);
    await tester.fling(find.text('page 0'), const Offset(0, -500), 5000);
    await tester.pumpAndSettle();
    expect(controller.page, 1);
  });
}
