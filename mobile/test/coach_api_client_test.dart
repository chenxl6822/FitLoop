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

  test('parses only a complete and known training plan payload', () {
    final preview = TrainingPlanPreview.tryParse(jsonEncode({
      'title': '下周跑步计划',
      'goal': '安全恢复跑步习惯',
      'days': [
        {
          'day': 1,
          'session_type': '轻松跑',
          'duration_minutes': 30,
          'intensity': 'LOW',
          'notes': '以能轻松交谈为准',
        },
      ],
    }));

    expect(preview?.title, '下周跑步计划');
    expect(preview?.goal, '安全恢复跑步习惯');
    expect(preview?.days.single.sessionType, '轻松跑');
    expect(preview?.days.single.durationMinutes, 30);
    expect(preview?.days.single.intensity, 'LOW');
    expect(preview?.days.single.notes, '以能轻松交谈为准');

    expect(
      TrainingPlanPreview.tryParse(
        '{"title":"计划","goal":"目标","days":[]}',
      ),
      isNull,
    );
    expect(
      TrainingPlanPreview.tryParse(jsonEncode({
        'title': '计划',
        'goal': '目标',
        'days': [
          {
            'day': 1,
            'session_type': '跑步',
            'duration_minutes': 30,
            'intensity': 'LOW',
            'internal_token': 'must-not-be-accepted',
          },
        ],
      })),
      isNull,
    );
  });

  test('fails closed when a proposal expiry cannot be verified', () {
    const missing = AgentProposalItem(
      proposalId: 1,
      actionType: 'CREATE_TRAINING_PLAN',
      payloadJson: '{}',
      status: 'PENDING',
      requiresAdmin: false,
    );
    const missingZone = AgentProposalItem(
      proposalId: 2,
      actionType: 'CREATE_TRAINING_PLAN',
      payloadJson: '{}',
      status: 'PENDING',
      requiresAdmin: false,
      expiresAt: '2100-01-01T00:00:00',
    );
    const future = AgentProposalItem(
      proposalId: 3,
      actionType: 'CREATE_TRAINING_PLAN',
      payloadJson: '{}',
      status: 'PENDING',
      requiresAdmin: false,
      expiresAt: '2100-01-01T00:00:00Z',
    );

    expect(missing.expiresAt, isNull);
    expect(missing.isExpiredAt(DateTime.utc(2026)), isTrue);
    expect(missingZone.expiresAt, isNull);
    expect(missingZone.isExpiredAt(DateTime.utc(2026)), isTrue);
    expect(future.isExpiredAt(DateTime.utc(2026)), isFalse);
    expect(future.isExpiredAt(DateTime.utc(2100)), isTrue);
  });

  test('creates, reads, confirms, and rejects coach proposals', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handled = Completer<void>();
    var requestCount = 0;

    server.listen((request) async {
      requestCount += 1;
      try {
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer user-jwt',
        );
        request.response.headers.contentType = ContentType.json;

        switch (requestCount) {
          case 1:
            expect(request.method, 'POST');
            expect(request.uri.path, '/api/v1/agent/coach/runs');
            final payload = jsonDecode(
              await utf8.decoder.bind(request).join(),
            ) as Map<String, dynamic>;
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
          case 2:
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
                    'title': '不可执行的结果摘要标题',
                    'goal': '不得用作确认预览',
                    'days': [],
                  },
                }),
                'errorMessage': null,
                'proposals': [
                  {
                    'proposalId': 7,
                    'actionType': 'CREATE_TRAINING_PLAN',
                    'payloadJson': jsonEncode({
                      'title': '下周跑步计划',
                      'goal': '安全恢复跑步习惯',
                      'days': [
                        {
                          'day': 1,
                          'session_type': '轻松跑',
                          'duration_minutes': 30,
                          'intensity': 'LOW',
                          'notes': '以能轻松交谈为准',
                        },
                      ],
                    }),
                    'status': 'PENDING',
                    'requiresAdmin': false,
                    'expiresAt': '2100-01-01T00:00:00Z',
                    'decidedByUserId': null,
                    'decidedAt': null,
                    'decisionNote': null,
                  },
                ],
              },
            }));
          case 3:
            expect(request.method, 'POST');
            expect(request.uri.path, '/api/v1/agent/actions/7/confirm');
            expect(
              jsonDecode(await utf8.decoder.bind(request).join()),
              <String, dynamic>{},
            );
            request.response.write(jsonEncode({
              'code': 0,
              'message': 'ok',
              'data': {
                'proposalId': 7,
                'status': 'CONFIRMED',
                'affectedResourceId': 42,
              },
            }));
          case 4:
            expect(request.method, 'POST');
            expect(request.uri.path, '/api/v1/agent/actions/8/reject');
            expect(
              jsonDecode(await utf8.decoder.bind(request).join()),
              {'reason': '暂不采用此计划'},
            );
            request.response.write(jsonEncode({
              'code': 0,
              'message': 'ok',
              'data': {
                'proposalId': 8,
                'status': 'REJECTED',
                'affectedResourceId': null,
              },
            }));
          default:
            fail('Unexpected request #$requestCount');
        }
      } catch (error, stackTrace) {
        if (!handled.isCompleted) {
          handled.completeError(error, stackTrace);
        }
      } finally {
        await request.response.close();
        if (requestCount == 4 && !handled.isCompleted) handled.complete();
      }
    });

    final api = HttpFitLoopApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
    );

    final created = await api.createCoachRun(
      token: 'user-jwt',
      objective: '为下周安排两次循序渐进的跑步训练',
    );
    final run = await api.getAgentRun(
      token: 'user-jwt',
      runId: created.runId,
    );
    final confirmed = await api.confirmAgentProposal(
      token: 'user-jwt',
      proposalId: 7,
    );
    final rejected = await api.rejectAgentProposal(
      token: 'user-jwt',
      proposalId: 8,
      reason: '暂不采用此计划',
    );

    expect(created.status, 'QUEUED');
    expect(run.status, 'WAITING_APPROVAL');
    expect(run.advice?.answer, '建议安排两次低到中等强度训练。');
    expect(run.advice?.safetyNotices, ['如有疼痛或眩晕，请立即停止。']);
    expect(run.proposals.single.requiresAdmin, isFalse);
    expect(run.proposals.single.expiresAt, DateTime.utc(2100));
    expect(
      run.proposals.single.trainingPlanPreview?.title,
      '下周跑步计划',
    );
    expect(confirmed.affectedResourceId, 42);
    expect(confirmed.status, 'CONFIRMED');
    expect(rejected.affectedResourceId, isNull);
    expect(rejected.status, 'REJECTED');

    await handled.future;
    await server.close(force: true);
  });

  test('surfaces service unavailability for all coach endpoints', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <String>[];

    server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'title': 'Service Unavailable',
          'status': HttpStatus.serviceUnavailable,
          'detail': 'agent temporarily unavailable',
        }));
      await request.response.close();
    });

    final api = HttpFitLoopApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
    final unavailable = isA<ApiException>().having(
      (error) => error.message,
      'message',
      'agent temporarily unavailable',
    );

    await expectLater(
      api.createCoachRun(token: 'user-jwt', objective: 'safe plan'),
      throwsA(unavailable),
    );
    await expectLater(
      api.getAgentRun(token: 'user-jwt', runId: 'coach-run-1'),
      throwsA(unavailable),
    );
    await expectLater(
      api.confirmAgentProposal(token: 'user-jwt', proposalId: 7),
      throwsA(unavailable),
    );
    await expectLater(
      api.rejectAgentProposal(
        token: 'user-jwt',
        proposalId: 8,
        reason: 'not now',
      ),
      throwsA(unavailable),
    );

    expect(requests, [
      'POST /api/v1/agent/coach/runs',
      'GET /api/v1/agent/runs/coach-run-1',
      'POST /api/v1/agent/actions/7/confirm',
      'POST /api/v1/agent/actions/8/reject',
    ]);
  });
}
