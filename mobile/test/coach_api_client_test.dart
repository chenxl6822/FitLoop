import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fitloop/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ignores malformed coach result JSON', () {
    expect(CoachAdvice.tryParse('{not-json'), isNull);
    expect(CoachAdvice.tryParse('{"answer":""}'), isNull);
  });

  test('creates a coach run and parses the user-visible result', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handled = Completer<void>();
    var requestCount = 0;

    server.listen((request) async {
      requestCount += 1;
      try {
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer user-jwt');
        request.response.headers.contentType = ContentType.json;

        if (requestCount == 1) {
          expect(request.method, 'POST');
          expect(request.uri.path, '/api/v1/agent/coach/runs');
          final payload = jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
          expect(payload, {
            'objective': '为下周安排两次循序渐进的跑步训练',
          });
          request.response.write(jsonEncode({
            'code': 0,
            'message': 'ok',
            'data': {
              'runId': 'coach-run-1',
              'type': 'COACH',
              'status': 'QUEUED',
              'traceId': 'trace-1',
            },
          }));
        } else {
          expect(request.method, 'GET');
          expect(request.uri.path, '/api/v1/agent/runs/coach-run-1');
          request.response.write(jsonEncode({
            'code': 0,
            'message': 'ok',
            'data': {
              'runId': 'coach-run-1',
              'type': 'COACH',
              'status': 'WAITING_APPROVAL',
              'traceId': 'trace-1',
              'resultJson': jsonEncode({
                'answer': '建议安排两次低到中等强度训练。',
                'rationale': ['近期训练负荷较低。'],
                'safety_notices': ['如有疼痛或眩晕，请立即停止。'],
                'proposal': {
                  'title': '下周跑步计划',
                  'goal': '安全恢复跑步习惯',
                  'days': [],
                },
              }),
              'errorMessage': null,
              'proposals': [
                {
                  'proposalId': 7,
                  'actionType': 'CREATE_TRAINING_PLAN',
                  'payloadJson': '{"title":"下周跑步计划"}',
                  'status': 'PENDING',
                  'requiresAdmin': false,
                  'decidedByUserId': null,
                  'decidedAt': null,
                  'decisionNote': null,
                },
              ],
            },
          }));
        }
      } finally {
        await request.response.close();
        if (requestCount == 2 && !handled.isCompleted) handled.complete();
      }
    });

    final api = HttpFitLoopApi(baseUrl: 'http://127.0.0.1:${server.port}');

    final created = await api.createCoachRun(
      token: 'user-jwt',
      objective: '为下周安排两次循序渐进的跑步训练',
    );
    final run = await api.getAgentRun(token: 'user-jwt', runId: created.runId);

    expect(created.status, 'QUEUED');
    expect(run.status, 'WAITING_APPROVAL');
    expect(run.advice?.answer, '建议安排两次低到中等强度训练。');
    expect(run.advice?.safetyNotices, ['如有疼痛或眩晕，请立即停止。']);
    expect(run.proposals.single.requiresAdmin, isFalse);

    await handled.future;
    await server.close(force: true);
  });
}
