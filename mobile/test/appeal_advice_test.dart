import 'package:fitloop/api_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses appeal agent advice into readable fields', () {
    const raw = '''
{
  "decision": "REJECT",
  "confidence": 0.92,
  "evidence": [
    "记录 #25 时长仅 9 秒，距离 0.0 km，异常原因：无有效轨迹点。",
    "申诉理由为「GPS信号异常」，但未提供证据或 URL。"
  ],
  "risk_flags": ["DISTANCE_INVALID", "REPEAT_INVALID_SESSION"],
  "reason": "无有效轨迹且缺少佐证材料，不建议改判为有效。"
}
''';

    final advice = AppealAdvice.tryParse(raw);

    expect(advice, isNotNull);
    expect(advice!.decision, 'REJECT');
    expect(advice.decisionLabel, '建议拒绝');
    expect(advice.confidencePercent, 92);
    expect(advice.reason, contains('不建议改判'));
    expect(advice.evidence, hasLength(2));
    expect(advice.riskFlags, contains('DISTANCE_INVALID'));
  });

  test('returns null for malformed appeal advice json', () {
    expect(AppealAdvice.tryParse(null), isNull);
    expect(AppealAdvice.tryParse(''), isNull);
    expect(AppealAdvice.tryParse('{"decision":"MAYBE"}'), isNull);
    expect(AppealAdvice.tryParse('not-json'), isNull);
  });

  test('formats chinese decision labels', () {
    expect(
      AppealAdvice.tryParse(
        '{"decision":"APPROVE","confidence":1,"evidence":["ok"],"reason":"通过"}',
      )!.decisionLabel,
      '建议批准',
    );
    expect(
      AppealAdvice.tryParse(
        '{"decision":"NEED_MORE_INFO","confidence":0.5,"evidence":["缺材料"],"reason":"补充"}',
      )!.decisionLabel,
      '建议补充材料',
    );
  });
}
