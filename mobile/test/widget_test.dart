import 'package:fitloop/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders FitLoop dashboard shell', (tester) async {
    await tester.pumpWidget(const FitLoopApp());

    expect(find.text('FitLoop'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);

    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('运动'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('社交'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });
}
