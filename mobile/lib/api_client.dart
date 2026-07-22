import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_session.dart';
import 'secure_session_storage.dart';

export 'auth_session.dart';

abstract class FitLoopApi {
  Future<UserSession> login({
    required String account,
    String? password,
    String? code,
    String loginType = 'password',
  });

  Future<void> register({
    required String account,
    required String password,
    required String nickname,
    String? code,
  });

  Future<SportStart> startSport({
    required String token,
    required String sportType,
    required String checkinMode,
  });

  Future<void> uploadTrackPoint({
    required String token,
    required TrackPoint point,
  });

  Future<SportRecord> finishSport({
    required String token,
    required String sessionId,
    required int durationSeconds,
    required double weightKg,
    double? distanceKm,
    double? calorie,
    String? note,
    String? photoUrl,
  });

  Future<SportStats> sportStats({required String token});

  Future<List<SportRecord>> listSportRecords({required String token});

  Future<List<SportTarget>> currentTargets({required String token});

  Future<SportTarget> createTarget({
    required String token,
    required String periodType,
    required String metric,
    required double targetValue,
  });

  Future<void> deleteTarget({
    required String token,
    required int targetId,
  });

  Future<SportTarget> editTarget({
    required String token,
    required int targetId,
    required String periodType,
    required String metric,
    required double targetValue,
  });

  Future<MedalSummary> medalSummary({required String token});

  Future<RankingResult> ranking({
    required String token,
    String scope = 'friends',
    String period = 'week',
    int page = 1,
    int size = 20,
  });

  Future<HealthData> addHealthData({
    required String token,
    double? weightKg,
    double? sleepHours,
    String? dietNote,
    required String dataDate,
  });

  Future<TargetReminderListResponse> targetReminders({required String token});

  Future<void> acknowledgeTargetReminder({
    required String token,
    required int targetId,
  });

  Future<ReminderListResponse> listReminders({required String token});

  Future<ReminderConfig> upsertReminder({
    required String token,
    required int remindId,
    required String type,
    String? time,
    String? cycle,
    bool? enabled,
  });

  Future<FriendListResponse> listFriends({required String token});

  Future<UserSearchResponse> searchUsers(
      {required String token, required String query});

  Future<void> addFriend({required String token, required int friendUserId});

  Future<AppealListResponse> listAppeals({required String token});

  Future<void> createAppeal(
      {required String token, required int recordId, required String reason});

  Future<SportHistoryResponse> sportHistory({
    required String token,
    String period = 'week',
    String metric = 'all',
  });

  Future<WeightHistoryResponse> weightHistory({
    required String token,
    int days = 30,
  });

  Future<String> uploadAvatar({
    required String token,
    required String imagePath,
  });

  Future<UserProfileResponse> getUserProfile({required String token});

  Future<Map<String, String>> sendSmsCode({required String phone});

  Future<Map<String, String>> sendVerificationCode({
    required String channel,
    required String target,
    required String purpose,
  });

  Future<void> resetPassword({
    required String account,
    required String code,
    required String newPassword,
  });

  Future<String> uploadSportPhoto({
    required String token,
    required String imagePath,
  });

  Future<FeatureFlags> fetchFeatureFlags();

  Future<FeedbackItem> submitFeedback({
    required String token,
    required String type,
    required String content,
    String? contact,
  });

  Future<FeedbackListResponse> listFeedback({required String token});

  Future<AdminStats> adminGetStats({required String token});

  Future<AdminUserListResponse> adminListUsers({
    required String token,
    int page = 0,
    int size = 20,
  });

  Future<AdminUserDetail> adminGetUserDetail({
    required String token,
    required int userId,
  });

  Future<FeedbackListResponse> adminListFeedback({required String token});

  Future<void> adminUpdateFeedback({
    required String token,
    required int feedbackId,
    required String status,
    String? adminNote,
  });

  Future<AdminAppealPage> adminListAppeals({
    required String token,
    String? status,
    int page = 0,
    int size = 20,
  });

  Future<void> adminReviewAppeal({
    required String token,
    required int appealId,
    required String status,
    String? reviewNote,
  });

  Future<String> adminStartAppealAgentReview({
    required String token,
    required int appealId,
  });

  Future<AdminAgentRunPage> adminListAgentRuns({
    required String token,
    String? type,
    String? status,
    int page = 0,
    int size = 20,
  });

  Future<AgentRunAudit> adminGetAgentRunAudit({
    required String token,
    required String runId,
  });

  Future<void> adminConfirmAgentProposal({
    required String token,
    required int proposalId,
  });

  Future<void> adminRejectAgentProposal({
    required String token,
    required int proposalId,
    String? reason,
  });

  Future<AdminAuditPage> adminListAuditLogs({
    required String token,
    String? resourceType,
    String? resourceId,
    int page = 0,
    int size = 20,
  });
}

class HttpFitLoopApi implements FitLoopApi, SessionAwareApi {
  HttpFitLoopApi({
    String? baseUrl,
    SessionStore? sessionStore,
    DateTime Function()? now,
  })  : baseUrl = baseUrl ?? ApiConfig.baseUrl,
        _sessionStore = sessionStore ?? const SecureSessionStore(),
        _now = now ?? DateTime.now;

  final String baseUrl;
  final SessionStore _sessionStore;
  final DateTime Function() _now;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  final StreamController<UserSession?> _sessionController =
      StreamController<UserSession?>.broadcast();

  static const _refreshWindow = Duration(seconds: 30);

  UserSession? _session;
  Future<UserSession>? _refreshInFlight;

  @override
  Stream<UserSession?> get sessionChanges => _sessionController.stream;

  @override
  Future<UserSession?> restoreSession() async {
    final restored = await _sessionStore.load();
    _session = restored;
    return restored;
  }

  @override
  Future<void> logoutSession() async {
    final refreshToken = _session?.refreshToken;
    try {
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _executeJson(
          'POST',
          '/api/v1/auth/logout',
          payload: {'refreshToken': refreshToken},
        );
      }
    } catch (_) {
      // Local logout must always succeed. A rotating refresh token expires on
      // the server even when the revocation request cannot reach it.
    } finally {
      await _invalidateSession();
    }
  }

  @override
  Future<UserSession> login({
    required String account,
    String? password,
    String? code,
    String loginType = 'password',
  }) async {
    final isCodeLogin = loginType.toLowerCase() == 'code';
    final response = await _executeJson(
      'POST',
      '/api/v1/auth/login',
      payload: {
      'account': account,
      'loginType': loginType,
      if (isCodeLogin) 'code': code else 'password': password,
      },
    );
    final session = _sessionFromAuthPayload(_expectDirect(response));
    await _acceptSession(session);
    return session;
  }

  @override
  Future<void> register({
    required String account,
    required String password,
    required String nickname,
    String? code,
  }) async {
    final isEmail = account.contains('@');
    await _post('/api/user/register', {
      if (isEmail) 'email': account else 'phone': account,
      'password': password,
      'nickname': nickname,
      if (code != null) 'code': code,
    });
  }

  @override
  Future<SportStart> startSport({
    required String token,
    required String sportType,
    required String checkinMode,
  }) async {
    final body = await _post(
      '/api/sport/session/start',
      {'sportType': sportType, 'checkinMode': checkinMode},
      token: token,
    );
    final data = body['data'] as Map<String, dynamic>;
    return SportStart(
      sessionId: data['sessionId'] as String,
      startTime: data['startTime'] as String,
    );
  }

  @override
  Future<void> uploadTrackPoint({
    required String token,
    required TrackPoint point,
  }) async {
    await _post(
      '/api/sport/session/track',
      point.toJson(),
      token: token,
    );
  }

  @override
  Future<SportRecord> finishSport({
    required String token,
    required String sessionId,
    required int durationSeconds,
    required double weightKg,
    double? distanceKm,
    double? calorie,
    String? note,
    String? photoUrl,
  }) async {
    final body = await _post(
      '/api/sport/session/finish',
      {
        'sessionId': sessionId,
        'durationSeconds': durationSeconds,
        'weightKg': weightKg,
        if (distanceKm != null) 'distanceKm': distanceKm,
        if (calorie != null) 'calorie': calorie,
        if (note != null && note.isNotEmpty) 'note': note,
        if (photoUrl != null) 'photoUrl': photoUrl,
      },
      token: token,
    );
    final data = body['data'] as Map<String, dynamic>;
    return SportRecord(
      recordId: data['recordId'] as int,
      status: data['status'] as int,
      durationSeconds: data['durationSeconds'] as int,
      distanceKm: (data['distanceKm'] as num).toDouble(),
      calorie: (data['calorie'] as num).toDouble(),
    );
  }

  @override
  Future<SportStats> sportStats({required String token}) async {
    final body = await _get('/api/stat/sport', token: token);
    final data = body['data'] as Map<String, dynamic>;
    return SportStats(
      checkinCount: data['checkinCount'] as int,
      durationSeconds: data['durationSeconds'] as int,
      distanceKm: (data['distanceKm'] as num).toDouble(),
      calorie: (data['calorie'] as num).toDouble(),
    );
  }

  @override
  Future<List<SportRecord>> listSportRecords({required String token}) async {
    final body = await _get('/api/sport/list', token: token);
    final data = body['data'] as Map<String, dynamic>;
    final records = data['records'] as List<dynamic>;
    return records
        .map((item) => SportRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<SportTarget>> currentTargets({required String token}) async {
    final body = await _get('/api/targets/current', token: token);
    final data = body['data'] as Map<String, dynamic>;
    final targets = data['targets'] as List<dynamic>;
    return targets
        .map((item) => SportTarget.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<SportTarget> createTarget({
    required String token,
    required String periodType,
    required String metric,
    required double targetValue,
  }) async {
    final body = await _post(
      '/api/targets',
      {
        'periodType': periodType,
        'metric': metric,
        'targetValue': targetValue,
      },
      token: token,
    );
    final data = body['data'] as Map<String, dynamic>;
    return SportTarget.fromJson(data);
  }

  @override
  Future<void> deleteTarget({
    required String token,
    required int targetId,
  }) async {
    await _delete('/api/targets/$targetId', token: token);
  }

  @override
  Future<SportTarget> editTarget({
    required String token,
    required int targetId,
    required String periodType,
    required String metric,
    required double targetValue,
  }) async {
    final body = await _put(
      '/api/targets/$targetId',
      body: {
        'periodType': periodType,
        'metric': metric,
        'targetValue': targetValue,
      },
      token: token,
    );
    final data = body['data'] as Map<String, dynamic>;
    return SportTarget.fromJson(data);
  }

  @override
  Future<MedalSummary> medalSummary({required String token}) async {
    final body = await _get('/api/social/medal', token: token);
    final data = body['data'] as Map<String, dynamic>;
    return MedalSummary.fromJson(data);
  }

  @override
  Future<RankingResult> ranking({
    required String token,
    String scope = 'friends',
    String period = 'week',
    int page = 1,
    int size = 20,
  }) async {
    final path = Uri(
      path: '/api/social/ranking',
      queryParameters: {
        'scope': scope,
        'period': period,
        'page': '$page',
        'size': '$size',
      },
    ).toString();
    final body = await _get(path, token: token);
    final data = body['data'] as Map<String, dynamic>;
    return RankingResult.fromJson(data);
  }

  @override
  Future<HealthData> addHealthData({
    required String token,
    double? weightKg,
    double? sleepHours,
    String? dietNote,
    required String dataDate,
  }) async {
    final body = await _post(
      '/api/stat/health',
      {
        if (weightKg != null) 'weightKg': weightKg,
        if (sleepHours != null) 'sleepHours': sleepHours,
        if (dietNote != null && dietNote.isNotEmpty) 'dietNote': dietNote,
        'dataDate': dataDate,
      },
      token: token,
    );
    final data = body['data'] as Map<String, dynamic>;
    return HealthData.fromJson(data);
  }

  @override
  Future<TargetReminderListResponse> targetReminders({
    required String token,
  }) async {
    final body = await _get('/api/reminders/targets', token: token);
    final data = body['data'] as Map<String, dynamic>;
    final targets = data['targets'] as List<dynamic>;
    return TargetReminderListResponse(
      targets: targets
          .map(
              (e) => TargetReminderResponse.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<void> acknowledgeTargetReminder({
    required String token,
    required int targetId,
  }) async {
    await _put('/api/reminders/targets/$targetId/read', token: token);
  }

  @override
  Future<ReminderListResponse> listReminders({required String token}) async {
    final body = await _get('/api/reminders', token: token);
    final data = body['data'] as Map<String, dynamic>;
    final list = data['reminders'] as List<dynamic>;
    return ReminderListResponse(
      reminders: list
          .map((e) => ReminderConfig.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<ReminderConfig> upsertReminder({
    required String token,
    required int remindId,
    required String type,
    String? time,
    String? cycle,
    bool? enabled,
  }) async {
    final body = await _put(
      '/api/reminders/$remindId',
      body: {
        'type': type,
        if (time != null) 'time': time,
        if (cycle != null) 'cycle': cycle,
        if (enabled != null) 'enabled': enabled,
      },
      token: token,
    );
    final data = body['data'] as Map<String, dynamic>;
    return ReminderConfig.fromJson(data);
  }

  @override
  Future<FriendListResponse> listFriends({required String token}) async {
    final body = await _get('/api/social/friends', token: token);
    final data = body['data'] as Map<String, dynamic>;
    final list = data['friends'] as List<dynamic>;
    return FriendListResponse(
      friends: list
          .map((e) => FriendInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<UserSearchResponse> searchUsers({
    required String token,
    required String query,
  }) async {
    final path = Uri(
      path: '/api/social/friends/search',
      queryParameters: {'q': query},
    ).toString();
    final body = await _get(path, token: token);
    final data = body['data'] as Map<String, dynamic>;
    final list = data['users'] as List<dynamic>;
    return UserSearchResponse(
      users: list
          .map((e) => UserSearchItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<void> addFriend(
      {required String token, required int friendUserId}) async {
    await _post(
      '/api/social/friend',
      {'friendUserId': friendUserId},
      token: token,
    );
  }

  @override
  Future<AppealListResponse> listAppeals({required String token}) async {
    final body = await _get('/api/appeals', token: token);
    final data = body['data'] as Map<String, dynamic>;
    final list = data['appeals'] as List<dynamic>;
    return AppealListResponse(
      appeals: list
          .map((e) => AppealResponse.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<void> createAppeal(
      {required String token,
      required int recordId,
      required String reason}) async {
    await _post(
      '/api/appeals',
      {'recordId': recordId, 'reason': reason},
      token: token,
    );
  }

  @override
  Future<SportHistoryResponse> sportHistory({
    required String token,
    String period = 'week',
    String metric = 'all',
  }) async {
    final path = Uri(
      path: '/api/stat/sport/history',
      queryParameters: {'period': period, 'metric': metric},
    ).toString();
    final body = await _get(path, token: token);
    final data = body['data'] as Map<String, dynamic>;
    return SportHistoryResponse.fromJson(data);
  }

  @override
  Future<WeightHistoryResponse> weightHistory({
    required String token,
    int days = 30,
  }) async {
    final path = Uri(
      path: '/api/stat/health/history',
      queryParameters: {'days': '$days'},
    ).toString();
    final body = await _get(path, token: token);
    final data = body['data'] as Map<String, dynamic>;
    return WeightHistoryResponse.fromJson(data);
  }

  @override
  Future<String> uploadAvatar({
    required String token,
    required String imagePath,
  }) async {
    final safePath = await _safeFilePath(imagePath);
    final result = await _uploadMultipart(
      path: '/api/user/avatar',
      token: token,
      imagePath: safePath,
      failureMessage: '头像上传失败，请检查网络后重试',
    );
    return _absoluteUrl(result) ?? '';
  }

  @override
  Future<UserProfileResponse> getUserProfile({required String token}) async {
    final data = await _get('/api/user/profile', token: token);
    final profile =
        UserProfileResponse.fromJson(data['data'] as Map<String, dynamic>);
    return UserProfileResponse(
      userId: profile.userId,
      nickname: profile.nickname,
      avatarUrl: _absoluteUrl(profile.avatarUrl),
    );
  }

  @override
  Future<Map<String, String>> sendSmsCode({required String phone}) async {
    final body = await _post('/api/sms/send', {'phone': phone});
    final data = body['data'] as Map<String, dynamic>;
    return {
      'message': data['message'] as String,
      if (data.containsKey('debugCode'))
        'debugCode': data['debugCode'] as String,
    };
  }

  @override
  Future<Map<String, String>> sendVerificationCode({
    required String channel,
    required String target,
    required String purpose,
  }) async {
    final body = await _post('/api/verification/send', {
      'channel': channel,
      'target': target,
      'purpose': purpose,
    });
    final data = body['data'] as Map<String, dynamic>;
    return {
      'message': data['message'] as String,
      if (data.containsKey('debugCode') && data['debugCode'] != null)
        'debugCode': data['debugCode'] as String,
    };
  }

  @override
  Future<void> resetPassword({
    required String account,
    required String code,
    required String newPassword,
  }) async {
    await _post('/api/auth/password/reset', {
      'account': account,
      'code': code,
      'newPassword': newPassword,
    });
  }

  @override
  Future<String> uploadSportPhoto({
    required String token,
    required String imagePath,
  }) async {
    final safePath = await _safeFilePath(imagePath);
    final result = await _uploadMultipart(
      path: '/api/sport/photo',
      token: token,
      imagePath: safePath,
      failureMessage: '照片上传失败，请检查网络后重试',
    );
    return _absoluteUrl(result) ?? '';
  }

  @override
  Future<FeatureFlags> fetchFeatureFlags() async {
    final body = await _get('/api/config/features');
    final data = body['data'] as Map<String, dynamic>;
    return FeatureFlags(
      smsEnabled: data['smsEnabled'] as bool,
    );
  }

  @override
  Future<FeedbackItem> submitFeedback({
    required String token,
    required String type,
    required String content,
    String? contact,
  }) async {
    final body = await _post(
        '/api/feedback',
        {
          'type': type,
          'content': content,
          if (contact != null && contact.isNotEmpty) 'contact': contact,
        },
        token: token);
    final data = body['data'] as Map<String, dynamic>;
    return FeedbackItem.fromJson(data);
  }

  @override
  Future<FeedbackListResponse> listFeedback({required String token}) async {
    final body = await _get('/api/feedback', token: token);
    final data = body['data'] as Map<String, dynamic>;
    final list = data['feedbacks'] as List<dynamic>;
    return FeedbackListResponse(
      feedbacks: list
          .map((e) => FeedbackItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<String> _safeFilePath(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists() && imagePath.startsWith('content://')) {
        // content:// URIs can't be read via dart:io File on Android
        // Fall through and let MultipartFile.fromPath handle it
        return imagePath;
      }
      // Preserve original extension if valid, otherwise default to .jpg
      String ext = '.jpg';
      final lower = imagePath.toLowerCase();
      if (lower.endsWith('.jpeg')) {
        ext = '.jpeg';
      } else if (lower.endsWith('.png')) {
        ext = '.png';
      } else if (lower.endsWith('.jpg')) {
        ext = '.jpg';
      }
      // For valid file paths, copy to temp to ensure clean upload
      final bytes = await file.readAsBytes();
      final dir = Directory.systemTemp;
      final tempFile = File(
          '${dir.path}/fitloop_upload_${DateTime.now().millisecondsSinceEpoch}$ext');
      await tempFile.writeAsBytes(bytes);
      return tempFile.path;
    } catch (_) {
      // If anything fails, return original path and let the upload try
      return imagePath;
    }
  }

  Future<Map<String, dynamic>> _delete(String path, {String? token}) async {
    return _request('DELETE', path, token: token);
  }

  Future<Map<String, dynamic>> _put(String path,
      {Map<String, dynamic>? body, String? token}) async {
    return _request('PUT', path,
        payload: body ?? <String, dynamic>{}, token: token);
  }

  Future<Map<String, dynamic>> _get(String path, {String? token}) async {
    return _request('GET', path, token: token);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload, {
    String? token,
  }) async {
    return _request('POST', path, payload: payload, token: token);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? payload,
    String? token,
  }) async {
    var accessToken = await _accessTokenForRequest(token);
    var response = await _executeJson(
      method,
      path,
      payload: payload,
      token: accessToken,
    );
    if (response.statusCode == HttpStatus.unauthorized &&
        token != null &&
        _session != null) {
      final refreshed = await _refreshSession(rejectedToken: accessToken);
      accessToken = refreshed.token;
      response = await _executeJson(
        method,
        path,
        payload: payload,
        token: accessToken,
      );
    }
    return _expectEnvelope(response);
  }

  Future<String?> _accessTokenForRequest(String? fallbackToken) async {
    if (fallbackToken == null) return null;
    final current = _session;
    if (current == null) return fallbackToken;
    if (current.expiresWithin(_refreshWindow, _now())) {
      return (await _refreshSession()).token;
    }
    return current.token;
  }

  Future<UserSession> _refreshSession({String? rejectedToken}) async {
    final current = _session;
    if (current == null) {
      throw ApiException('登录状态已过期，请重新登录');
    }
    if (rejectedToken != null && current.token != rejectedToken) {
      return current;
  }
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final pending = _performRefresh(current);
    _refreshInFlight = pending;
    try {
      return await pending;
    } finally {
      if (identical(_refreshInFlight, pending)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<UserSession> _performRefresh(UserSession current) async {
    final response = await _executeJson(
      'POST',
      '/api/v1/auth/refresh',
      payload: {'refreshToken': current.refreshToken},
    );
    if (response.statusCode == HttpStatus.unauthorized ||
        response.statusCode == HttpStatus.forbidden) {
      await _invalidateSession();
      throw ApiException('登录状态已过期，请重新登录');
    }
    final refreshed = _sessionFromAuthPayload(_expectDirect(response));
    await _acceptSession(refreshed);
    return refreshed;
  }

  UserSession _sessionFromAuthPayload(Map<String, dynamic> data) {
    final profile = data['userProfile'];
    final token = data['token'];
    final refreshToken = data['refreshToken'];
    final expiresIn = data['expiresIn'];
    if (profile is! Map<String, dynamic> ||
        token is! String ||
        token.isEmpty ||
        refreshToken is! String ||
        refreshToken.isEmpty ||
        expiresIn is! num) {
      throw const FormatException('Invalid authentication response');
    }
    return UserSession(
      token: token,
      refreshToken: refreshToken,
      expiresAt: _now().toUtc().add(Duration(seconds: expiresIn.toInt())),
      userId: profile['userId'] as int,
      nickname: profile['nickname'] as String? ?? 'FitLoop 用户',
      avatarUrl: _absoluteUrl(profile['avatarUrl'] as String?),
      role: data['role'] as String? ?? 'USER',
    );
  }

  Future<void> _acceptSession(UserSession value) async {
    await _sessionStore.save(value);
    _session = value;
    _sessionController.add(value);
  }

  Future<void> _invalidateSession() async {
    _session = null;
    await _sessionStore.clear();
    _sessionController.add(null);
  }

  Future<_JsonHttpResponse> _executeJson(
    String method,
    String path, {
    Map<String, dynamic>? payload,
    String? token,
  }) async {
    try {
      final request = await _client.openUrl(method, Uri.parse('$baseUrl$path'));
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
      if (payload != null) request.write(jsonEncode(payload));
      return _send(request);
    } on SocketException {
      throw ApiException('无法连接服务器，请检查网络或稍后重试');
    } on HttpException {
      throw ApiException('无法连接服务器，请检查网络或稍后重试');
    }
  }

  Map<String, dynamic> _expectEnvelope(_JsonHttpResponse response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
          _extractErrorMessage(response.body, response.statusCode));
    }
    if (response.body['code'] != 0 && response.body['code'] != 200) {
      throw ApiException(
          _extractErrorMessage(response.body, response.statusCode));
    }
    return response.body;
  }

  Map<String, dynamic> _expectDirect(_JsonHttpResponse response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
          _extractErrorMessage(response.body, response.statusCode));
    }
    return response.body;
  }

  Future<String> _uploadMultipart({
    required String path,
    required String token,
    required String imagePath,
    required String failureMessage,
  }) async {
    try {
      var accessToken = await _accessTokenForRequest(token);
      var response = await _sendMultipart(path, imagePath, accessToken!);
      if (response.statusCode == HttpStatus.unauthorized && _session != null) {
        final refreshed = await _refreshSession(rejectedToken: accessToken);
        accessToken = refreshed.token;
        response = await _sendMultipart(path, imagePath, accessToken);
      }
      final body = _expectEnvelope(response);
      return body['data'] as String? ?? '';
    } catch (error) {
      if (error is ApiException) rethrow;
      throw ApiException(failureMessage);
    }
  }

  Future<_JsonHttpResponse> _sendMultipart(
      String path, String imagePath, String token) async {
    final client = http.Client();
    try {
      final multipart =
          http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
      multipart.headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      multipart.files.add(await http.MultipartFile.fromPath('file', imagePath));
      final streamed =
          await client.send(multipart).timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      final body = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
      return _JsonHttpResponse(response.statusCode, body);
    } finally {
      client.close();
    }
  }

  /// 提取后端错误消息；HTTP 40x/50x 统一前置处理
  String _extractErrorMessage(Map<String, dynamic> body, int statusCode) {
    // 优先用后端返回的 message
    if (body.containsKey('message') &&
        body['message'] is String &&
        (body['message'] as String).isNotEmpty) {
      return body['message'] as String;
    }
    if (body.containsKey('detail') &&
        body['detail'] is String &&
        (body['detail'] as String).isNotEmpty) {
      return body['detail'] as String;
    }
    // 后端 code != 0 但没有 message
    if (statusCode >= 500) return '服务器开小差了，请稍后重试';
    if (statusCode == 401 || statusCode == 403) return '登录状态已过期，请重新登录';
    return '请求失败（$statusCode）';
  }

  @override
  Future<AdminStats> adminGetStats({required String token}) async {
    final body = await _get('/api/admin/stats', token: token);
    final data = body['data'] as Map<String, dynamic>;
    return AdminStats.fromJson(data);
  }

  @override
  Future<AdminUserListResponse> adminListUsers({
    required String token,
    int page = 0,
    int size = 20,
  }) async {
    final path = '/api/admin/users?page=$page&size=$size';
    final body = await _get(path, token: token);
    final data = body['data'] as Map<String, dynamic>;
    return AdminUserListResponse.fromJson(data);
  }

  @override
  Future<AdminUserDetail> adminGetUserDetail({
    required String token,
    required int userId,
  }) async {
    final body = await _get('/api/admin/users/$userId', token: token);
    final data = body['data'] as Map<String, dynamic>;
    return AdminUserDetail.fromJson(data);
  }

  @override
  Future<FeedbackListResponse> adminListFeedback(
      {required String token}) async {
    final body = await _get('/api/admin/feedback', token: token);
    final data = body['data'] as Map<String, dynamic>;
    final list = data['feedbacks'] as List<dynamic>;
    return FeedbackListResponse(
      feedbacks: list
          .map((e) => FeedbackItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<void> adminUpdateFeedback({
    required String token,
    required int feedbackId,
    required String status,
    String? adminNote,
  }) async {
    await _put(
      '/api/admin/feedback/$feedbackId',
      token: token,
      body: {
        'status': status,
        if (adminNote != null) 'adminNote': adminNote,
      },
    );
  }

  @override
  Future<AdminAppealPage> adminListAppeals({
    required String token,
    String? status,
    int page = 0,
    int size = 20,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'size': '$size',
      if (status != null && status.isNotEmpty) 'status': status,
    };
    final uri = Uri(path: '/api/v1/admin/appeals', queryParameters: query);
    final body = await _get(uri.toString(), token: token);
    return AdminAppealPage.fromJson(body['data'] as Map<String, dynamic>);
  }

  @override
  Future<void> adminReviewAppeal({
    required String token,
    required int appealId,
    required String status,
    String? reviewNote,
  }) async {
    await _put('/api/v1/admin/appeals/$appealId', token: token, body: {
      'status': status,
      if (reviewNote != null) 'reviewNote': reviewNote,
    });
  }

  @override
  Future<String> adminStartAppealAgentReview({
    required String token,
    required int appealId,
  }) async {
    final body = await _post(
        '/api/v1/admin/appeals/$appealId/agent-review', const {},
        token: token);
    return (body['data'] as Map<String, dynamic>)['runId'] as String;
  }

  @override
  Future<AdminAgentRunPage> adminListAgentRuns({
    required String token,
    String? type,
    String? status,
    int page = 0,
    int size = 20,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'size': '$size',
      if (type != null && type.isNotEmpty) 'type': type,
      if (status != null && status.isNotEmpty) 'status': status,
    };
    final uri = Uri(path: '/api/v1/admin/agent/runs', queryParameters: query);
    final body = await _get(uri.toString(), token: token);
    return AdminAgentRunPage.fromJson(body['data'] as Map<String, dynamic>);
  }

  @override
  Future<AgentRunAudit> adminGetAgentRunAudit({
    required String token,
    required String runId,
  }) async {
    final body =
        await _get('/api/v1/admin/agent/runs/$runId/audit', token: token);
    return AgentRunAudit.fromJson(body['data'] as Map<String, dynamic>);
  }

  @override
  Future<void> adminConfirmAgentProposal({
    required String token,
    required int proposalId,
  }) async {
    await _post('/api/v1/agent/actions/$proposalId/confirm', const {},
        token: token);
  }

  @override
  Future<void> adminRejectAgentProposal({
    required String token,
    required int proposalId,
    String? reason,
  }) async {
    await _post(
        '/api/v1/agent/actions/$proposalId/reject',
        {
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
        token: token);
  }

  @override
  Future<AdminAuditPage> adminListAuditLogs({
    required String token,
    String? resourceType,
    String? resourceId,
    int page = 0,
    int size = 20,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'size': '$size',
      if (resourceType != null && resourceType.isNotEmpty)
        'resourceType': resourceType,
      if (resourceId != null && resourceId.isNotEmpty) 'resourceId': resourceId,
    };
    final uri = Uri(path: '/api/v1/admin/audit-logs', queryParameters: query);
    final body = await _get(uri.toString(), token: token);
    return AdminAuditPage.fromJson(body['data'] as Map<String, dynamic>);
  }

  String? _absoluteUrl(String? url) {
    if (url == null || url.isEmpty) return url;
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme) return url;
    if (!url.startsWith('/')) return url;
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$base$url';
  }

  Future<_JsonHttpResponse> _send(HttpClientRequest request) async {
    try {
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      final body = text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>;
      return _JsonHttpResponse(response.statusCode, body);
    } on SocketException {
      throw ApiException('无法连接服务器，请检查网络或稍后重试');
    } on HttpException {
      throw ApiException('无法连接服务器，请检查网络或稍后重试');
    } on FormatException {
      throw ApiException('服务器响应异常，请稍后重试');
    }
  }
}

class _JsonHttpResponse {
  const _JsonHttpResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, dynamic> body;
}

class FeatureFlags {
  const FeatureFlags({required this.smsEnabled});

  final bool smsEnabled;
}

class FeedbackItem {
  const FeedbackItem({
    required this.feedbackId,
    required this.type,
    required this.content,
    this.contact,
    required this.status,
    this.adminNote,
    required this.createdAt,
  });

  factory FeedbackItem.fromJson(Map<String, dynamic> json) {
    return FeedbackItem(
      feedbackId: json['feedbackId'] as int,
      type: json['type'] as String,
      content: json['content'] as String,
      contact: json['contact'] as String?,
      status: json['status'] as String,
      adminNote: json['adminNote'] as String?,
      createdAt: json['createdAt'] as String,
    );
  }

  final int feedbackId;
  final String type;
  final String content;
  final String? contact;
  final String status;
  final String? adminNote;
  final String createdAt;
}

class FeedbackListResponse {
  const FeedbackListResponse({required this.feedbacks});

  final List<FeedbackItem> feedbacks;
}

class AdminStats {
  const AdminStats({
    required this.totalUsers,
    required this.todayNewUsers,
    required this.totalSportRecords,
    required this.todayCheckins,
    required this.pendingFeedbackCount,
  });

  factory AdminStats.fromJson(Map<String, dynamic> json) {
    return AdminStats(
      totalUsers: json['totalUsers'] as int,
      todayNewUsers: json['todayNewUsers'] as int,
      totalSportRecords: json['totalSportRecords'] as int,
      todayCheckins: json['todayCheckins'] as int,
      pendingFeedbackCount: json['pendingFeedbackCount'] as int,
    );
  }

  final int totalUsers;
  final int todayNewUsers;
  final int totalSportRecords;
  final int todayCheckins;
  final int pendingFeedbackCount;
}

class AdminUserListItem {
  const AdminUserListItem({
    required this.userId,
    required this.nickname,
    this.phone,
    this.email,
    this.points,
    this.level,
    this.createdAt,
  });

  factory AdminUserListItem.fromJson(Map<String, dynamic> json) {
    return AdminUserListItem(
      userId: json['userId'] as int,
      nickname: json['nickname'] as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      points: json['points'] as int?,
      level: json['level'] as int?,
      createdAt: json['createdAt'] as String?,
    );
  }

  final int userId;
  final String nickname;
  final String? phone;
  final String? email;
  final int? points;
  final int? level;
  final String? createdAt;
}

class AdminUserListResponse {
  const AdminUserListResponse({
    required this.users,
    required this.total,
  });

  factory AdminUserListResponse.fromJson(Map<String, dynamic> json) {
    final list = json['users'] as List<dynamic>;
    return AdminUserListResponse(
      users: list
          .map((e) => AdminUserListItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
    );
  }

  final List<AdminUserListItem> users;
  final int total;
}

class AdminUserDetail {
  const AdminUserDetail({
    required this.userId,
    required this.nickname,
    this.phone,
    this.email,
    this.avatarUrl,
    this.createdAt,
    required this.sportRecordCount,
    required this.targetCount,
    required this.totalDurationSeconds,
    required this.totalDistanceKm,
  });

  factory AdminUserDetail.fromJson(Map<String, dynamic> json) {
    return AdminUserDetail(
      userId: json['userId'] as int,
      nickname: json['nickname'] as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      createdAt: json['createdAt'] as String?,
      sportRecordCount: json['sportRecordCount'] as int,
      targetCount: json['targetCount'] as int,
      totalDurationSeconds: json['totalDurationSeconds'] as int,
      totalDistanceKm: (json['totalDistanceKm'] as num).toDouble(),
    );
  }

  final int userId;
  final String nickname;
  final String? phone;
  final String? email;
  final String? avatarUrl;
  final String? createdAt;
  final int sportRecordCount;
  final int targetCount;
  final int totalDurationSeconds;
  final double totalDistanceKm;
}

class AdminAppealItem {
  const AdminAppealItem({
    required this.appealId,
    required this.userId,
    required this.recordId,
    required this.reason,
    this.evidenceUrl,
    required this.status,
    this.reviewNote,
    required this.createdAt,
  });

  factory AdminAppealItem.fromJson(Map<String, dynamic> json) {
    return AdminAppealItem(
      appealId: json['appealId'] as int,
      userId: json['userId'] as int,
      recordId: json['recordId'] as int,
      reason: json['reason'] as String,
      evidenceUrl: json['evidenceUrl'] as String?,
      status: json['status'] as String,
      reviewNote: json['reviewNote'] as String?,
      createdAt: json['createdAt'] as String,
    );
  }

  final int appealId;
  final int userId;
  final int recordId;
  final String reason;
  final String? evidenceUrl;
  final String status;
  final String? reviewNote;
  final String createdAt;
}

class AdminAppealPage {
  const AdminAppealPage({required this.items, required this.totalElements});

  factory AdminAppealPage.fromJson(Map<String, dynamic> json) {
    return AdminAppealPage(
      items: (json['items'] as List<dynamic>)
          .map((item) => AdminAppealItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      totalElements: json['totalElements'] as int,
    );
  }

  final List<AdminAppealItem> items;
  final int totalElements;
}

class AdminAgentRunItem {
  const AdminAgentRunItem({
    required this.runId,
    required this.type,
    required this.status,
    required this.subjectUserId,
    this.subjectResourceId,
    required this.traceId,
    this.model,
    this.promptVersion,
    this.latencyMs,
    this.errorMessage,
    required this.createdAt,
  });

  factory AdminAgentRunItem.fromJson(Map<String, dynamic> json) {
    return AdminAgentRunItem(
      runId: json['runId'] as String,
      type: json['type'] as String,
      status: json['status'] as String,
      subjectUserId: json['subjectUserId'] as int,
      subjectResourceId: json['subjectResourceId'] as int?,
      traceId: json['traceId'] as String,
      model: json['model'] as String?,
      promptVersion: json['promptVersion'] as String?,
      latencyMs: json['latencyMs'] as int?,
      errorMessage: json['errorMessage'] as String?,
      createdAt: json['createdAt'] as String,
    );
  }

  final String runId;
  final String type;
  final String status;
  final int subjectUserId;
  final int? subjectResourceId;
  final String traceId;
  final String? model;
  final String? promptVersion;
  final int? latencyMs;
  final String? errorMessage;
  final String createdAt;
}

class AdminAgentRunPage {
  const AdminAgentRunPage({required this.items, required this.totalElements});

  factory AdminAgentRunPage.fromJson(Map<String, dynamic> json) {
    return AdminAgentRunPage(
      items: (json['items'] as List<dynamic>)
          .map((item) =>
              AdminAgentRunItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      totalElements: json['totalElements'] as int,
    );
  }

  final List<AdminAgentRunItem> items;
  final int totalElements;
}

class AgentProposalItem {
  const AgentProposalItem({
    required this.proposalId,
    required this.actionType,
    required this.payloadJson,
    required this.status,
    required this.requiresAdmin,
    this.decidedByUserId,
    this.decidedAt,
    this.decisionNote,
  });

  factory AgentProposalItem.fromJson(Map<String, dynamic> json) {
    return AgentProposalItem(
      proposalId: json['proposalId'] as int,
      actionType: json['actionType'] as String,
      payloadJson: json['payloadJson'] as String,
      status: json['status'] as String,
      requiresAdmin: json['requiresAdmin'] as bool,
      decidedByUserId: json['decidedByUserId'] as int?,
      decidedAt: json['decidedAt'] as String?,
      decisionNote: json['decisionNote'] as String?,
    );
  }

  final int proposalId;
  final String actionType;
  final String payloadJson;
  final String status;
  final bool requiresAdmin;
  final int? decidedByUserId;
  final String? decidedAt;
  final String? decisionNote;
}

class AgentToolAuditItem {
  const AgentToolAuditItem({
    required this.toolName,
    required this.succeeded,
    this.durationMs,
    this.errorMessage,
  });

  factory AgentToolAuditItem.fromJson(Map<String, dynamic> json) {
    return AgentToolAuditItem(
      toolName: json['toolName'] as String,
      succeeded: json['succeeded'] as bool,
      durationMs: json['durationMs'] as int?,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  final String toolName;
  final bool succeeded;
  final int? durationMs;
  final String? errorMessage;
}

class AgentRunAudit {
  const AgentRunAudit({
    required this.runId,
    required this.status,
    this.resultJson,
    this.model,
    this.promptVersion,
    required this.proposals,
    required this.toolCalls,
  });

  factory AgentRunAudit.fromJson(Map<String, dynamic> json) {
    final run = json['run'] as Map<String, dynamic>;
    return AgentRunAudit(
      runId: run['runId'] as String,
      status: run['status'] as String,
      resultJson: run['resultJson'] as String?,
      model: run['model'] as String?,
      promptVersion: run['promptVersion'] as String?,
      proposals: (run['proposals'] as List<dynamic>)
          .map((item) =>
              AgentProposalItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      toolCalls: (json['toolCalls'] as List<dynamic>)
          .map((item) =>
              AgentToolAuditItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  final String runId;
  final String status;
  final String? resultJson;
  final String? model;
  final String? promptVersion;
  final List<AgentProposalItem> proposals;
  final List<AgentToolAuditItem> toolCalls;
}

class AdminAuditEntry {
  const AdminAuditEntry({
    required this.actorUserId,
    required this.action,
    required this.resourceType,
    required this.resourceId,
    this.detailsJson,
    required this.createdAt,
  });

  factory AdminAuditEntry.fromJson(Map<String, dynamic> json) {
    return AdminAuditEntry(
      actorUserId: json['actorUserId'] as int,
      action: json['action'] as String,
      resourceType: json['resourceType'] as String,
      resourceId: json['resourceId'] as String,
      detailsJson: json['detailsJson'] as String?,
      createdAt: json['createdAt'] as String,
    );
  }

  final int actorUserId;
  final String action;
  final String resourceType;
  final String resourceId;
  final String? detailsJson;
  final String createdAt;
}

class AdminAuditPage {
  const AdminAuditPage({required this.items, required this.totalElements});

  factory AdminAuditPage.fromJson(Map<String, dynamic> json) {
    return AdminAuditPage(
      items: (json['items'] as List<dynamic>)
          .map((item) => AdminAuditEntry.fromJson(item as Map<String, dynamic>))
          .toList(),
      totalElements: json['totalElements'] as int,
    );
  }

  final List<AdminAuditEntry> items;
  final int totalElements;
}

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SportStart {
  const SportStart({required this.sessionId, required this.startTime});

  final String sessionId;
  final String startTime;
}

class TrackPoint {
  const TrackPoint({
    required this.sessionId,
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.timestamp,
  });

  final String sessionId;
  final double lat;
  final double lng;
  final double accuracy;
  final DateTime timestamp;

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'lat': lat,
      'lng': lng,
      'accuracy': accuracy,
      'timestamp': timestamp.toUtc().toIso8601String(),
    };
  }
}

class SportRecord {
  const SportRecord({
    required this.recordId,
    required this.status,
    required this.durationSeconds,
    required this.distanceKm,
    required this.calorie,
    this.sportType,
    this.abnormalReason,
    this.startedAt,
  });

  factory SportRecord.fromJson(Map<String, dynamic> json) {
    return SportRecord(
      recordId: json['recordId'] as int,
      status: json['status'] as int,
      durationSeconds: json['durationSeconds'] as int,
      distanceKm: (json['distanceKm'] as num).toDouble(),
      calorie: (json['calorie'] as num).toDouble(),
      sportType: json['sportType'] as String?,
      abnormalReason: json['abnormalReason'] as String?,
      startedAt: json['startedAt'] == null
          ? null
          : DateTime.parse(json['startedAt'] as String),
    );
  }

  final int recordId;
  final int status;
  final int durationSeconds;
  final double distanceKm;
  final double calorie;
  final String? sportType;
  final String? abnormalReason;
  final DateTime? startedAt;
}

class SportStats {
  const SportStats({
    required this.checkinCount,
    required this.durationSeconds,
    required this.distanceKm,
    required this.calorie,
  });

  final int checkinCount;
  final int durationSeconds;
  final double distanceKm;
  final double calorie;
}

class SportTarget {
  const SportTarget({
    required this.targetId,
    required this.periodType,
    required this.metric,
    required this.targetValue,
    required this.completedValue,
    required this.progress,
    required this.startDate,
    required this.endDate,
    required this.status,
  });

  factory SportTarget.fromJson(Map<String, dynamic> json) {
    return SportTarget(
      targetId: json['targetId'] as int,
      periodType: json['periodType'] as String,
      metric: json['metric'] as String,
      targetValue: (json['targetValue'] as num).toDouble(),
      completedValue: (json['completedValue'] as num).toDouble(),
      progress: (json['progress'] as num).toDouble(),
      startDate: json['startDate'] as String,
      endDate: json['endDate'] as String,
      status: json['status'] as String,
    );
  }

  final int targetId;
  final String periodType;
  final String metric;
  final double targetValue;
  final double completedValue;
  final double progress;
  final String startDate;
  final String endDate;
  final String status;
}

class MedalSummary {
  const MedalSummary({
    required this.points,
    required this.level,
    required this.medals,
  });

  factory MedalSummary.fromJson(Map<String, dynamic> json) {
    final medals = json['medals'] as List<dynamic>;
    return MedalSummary(
      points: json['points'] as int,
      level: json['level'] as int,
      medals: medals.map((item) => item as String).toList(),
    );
  }

  final int points;
  final int level;
  final List<String> medals;
}

class RankingResult {
  const RankingResult({
    required this.scope,
    required this.period,
    required this.rows,
  });

  factory RankingResult.fromJson(Map<String, dynamic> json) {
    final rows = json['rankingList'] as List<dynamic>;
    return RankingResult(
      scope: json['scope'] as String,
      period: json['period'] as String,
      rows: rows
          .map((item) => RankingRow.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  final String scope;
  final String period;
  final List<RankingRow> rows;
}

class RankingRow {
  const RankingRow({
    required this.rank,
    required this.userId,
    required this.nickname,
    required this.distanceKm,
    required this.calorie,
  });

  factory RankingRow.fromJson(Map<String, dynamic> json) {
    return RankingRow(
      rank: json['rank'] as int,
      userId: json['userId'] as int,
      nickname: json['nickname'] as String,
      distanceKm: (json['distanceKm'] as num).toDouble(),
      calorie: (json['calorie'] as num).toDouble(),
    );
  }

  final int rank;
  final int userId;
  final String nickname;
  final double distanceKm;
  final double calorie;
}

class TargetReminderResponse {
  const TargetReminderResponse({
    required this.targetId,
    required this.periodType,
    required this.metric,
    required this.targetValue,
    required this.completedValue,
    required this.progress,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.due,
    required this.acknowledged,
    this.remindTime,
    required this.message,
  });

  factory TargetReminderResponse.fromJson(Map<String, dynamic> json) {
    return TargetReminderResponse(
      targetId: json['targetId'] as int,
      periodType: json['periodType'] as String,
      metric: json['metric'] as String,
      targetValue: (json['targetValue'] as num).toDouble(),
      completedValue: (json['completedValue'] as num).toDouble(),
      progress: (json['progress'] as num).toDouble(),
      startDate: json['startDate'] as String,
      endDate: json['endDate'] as String,
      status: json['status'] as String,
      due: json['due'] as bool,
      acknowledged: json['acknowledged'] as bool,
      remindTime: json['remindTime'] as String?,
      message: json['message'] as String,
    );
  }

  final int targetId;
  final String periodType;
  final String metric;
  final double targetValue;
  final double completedValue;
  final double progress;
  final String startDate;
  final String endDate;
  final String status;
  final bool due;
  final bool acknowledged;
  final String? remindTime;
  final String message;
}

class TargetReminderListResponse {
  const TargetReminderListResponse({required this.targets});

  final List<TargetReminderResponse> targets;
}

class ReminderConfig {
  const ReminderConfig({
    required this.id,
    required this.type,
    this.time,
    required this.cycle,
    required this.enabled,
  });

  factory ReminderConfig.fromJson(Map<String, dynamic> json) {
    return ReminderConfig(
      id: json['id'] as int,
      type: json['type'] as String,
      time: json['time'] as String?,
      cycle: json['cycle'] as String,
      enabled: json['enabled'] as bool,
    );
  }

  final int id;
  final String type;
  final String? time;
  final String cycle;
  final bool enabled;

  String get label {
    switch (type) {
      case 'sport':
        return '运动'; // runner icon
      case 'sit':
        return '久坐'; // chair icon
      case 'drink':
        return '喝水'; // water icon
      case 'sleep':
        return '睡眠'; // bed icon
      default:
        return type;
    }
  }
}

class ReminderListResponse {
  const ReminderListResponse({required this.reminders});

  final List<ReminderConfig> reminders;
}

class FriendInfo {
  const FriendInfo({
    required this.friendId,
    required this.friendUserId,
    required this.nickname,
    required this.points,
    required this.level,
    required this.status,
  });

  factory FriendInfo.fromJson(Map<String, dynamic> json) {
    return FriendInfo(
      friendId: json['friendId'] as int,
      friendUserId: json['friendUserId'] as int,
      nickname: json['nickname'] as String,
      points: json['points'] as int,
      level: json['level'] as int,
      status: json['status'] as String,
    );
  }

  final int friendId;
  final int friendUserId;
  final String nickname;
  final int points;
  final int level;
  final String status;
}

class FriendListResponse {
  const FriendListResponse({required this.friends});

  final List<FriendInfo> friends;
}

class UserSearchItem {
  const UserSearchItem({
    required this.userId,
    required this.nickname,
    required this.points,
    required this.level,
    required this.isFriend,
  });

  factory UserSearchItem.fromJson(Map<String, dynamic> json) {
    return UserSearchItem(
      userId: json['userId'] as int,
      nickname: json['nickname'] as String,
      points: json['points'] as int,
      level: json['level'] as int,
      isFriend: json['isFriend'] as bool,
    );
  }

  final int userId;
  final String nickname;
  final int points;
  final int level;
  final bool isFriend;
}

class UserSearchResponse {
  const UserSearchResponse({required this.users});

  final List<UserSearchItem> users;
}

class AppealResponse {
  const AppealResponse({
    required this.appealId,
    required this.recordId,
    required this.reason,
    this.evidenceUrl,
    required this.status,
    this.reviewNote,
    required this.createdAt,
    this.updatedAt,
  });

  factory AppealResponse.fromJson(Map<String, dynamic> json) {
    return AppealResponse(
      appealId: json['appealId'] as int,
      recordId: json['recordId'] as int,
      reason: json['reason'] as String,
      evidenceUrl: json['evidenceUrl'] as String?,
      status: json['status'] as String,
      reviewNote: json['reviewNote'] as String?,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String?,
    );
  }

  final int appealId;
  final int recordId;
  final String reason;
  final String? evidenceUrl;
  final String status;
  final String? reviewNote;
  final String createdAt;
  final String? updatedAt;

  String get statusLabel {
    switch (status) {
      case 'pending':
        return '审核中';
      case 'approved':
        return '已通过';
      case 'rejected':
        return '已驳回';
      default:
        return status;
    }
  }
}

class AppealListResponse {
  const AppealListResponse({required this.appeals});

  final List<AppealResponse> appeals;
}

class HealthData {
  const HealthData({
    required this.healthId,
    this.weightKg,
    this.sleepHours,
    this.dietNote,
    required this.dataDate,
  });

  factory HealthData.fromJson(Map<String, dynamic> json) {
    return HealthData(
      healthId: json['healthId'] as int,
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      sleepHours: (json['sleepHours'] as num?)?.toDouble(),
      dietNote: json['dietNote'] as String?,
      dataDate: json['dataDate'] as String,
    );
  }

  final int healthId;
  final double? weightKg;
  final double? sleepHours;
  final String? dietNote;
  final String dataDate;
}

class SportHistoryPoint {
  const SportHistoryPoint({
    required this.date,
    required this.count,
    required this.durationSeconds,
    required this.distanceKm,
    required this.calorie,
  });

  factory SportHistoryPoint.fromJson(Map<String, dynamic> json) {
    return SportHistoryPoint(
      date: json['date'] as String,
      count: json['count'] as int,
      durationSeconds: json['durationSeconds'] as int,
      distanceKm: (json['distanceKm'] as num).toDouble(),
      calorie: (json['calorie'] as num).toDouble(),
    );
  }

  final String date;
  final int count;
  final int durationSeconds;
  final double distanceKm;
  final double calorie;
}

class SportHistoryResponse {
  const SportHistoryResponse({
    required this.period,
    required this.metric,
    required this.points,
  });

  factory SportHistoryResponse.fromJson(Map<String, dynamic> json) {
    final list = json['points'] as List<dynamic>;
    return SportHistoryResponse(
      period: json['period'] as String,
      metric: json['metric'] as String,
      points: list
          .map((e) => SportHistoryPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final String period;
  final String metric;
  final List<SportHistoryPoint> points;
}

class WeightHistoryPoint {
  const WeightHistoryPoint({required this.date, this.weightKg});

  factory WeightHistoryPoint.fromJson(Map<String, dynamic> json) {
    return WeightHistoryPoint(
      date: json['date'] as String,
      weightKg: (json['weightKg'] as num?)?.toDouble(),
    );
  }

  final String date;
  final double? weightKg;
}

class WeightHistoryResponse {
  const WeightHistoryResponse({required this.points});

  factory WeightHistoryResponse.fromJson(Map<String, dynamic> json) {
    final list = json['points'] as List<dynamic>;
    return WeightHistoryResponse(
      points: list
          .map((e) => WeightHistoryPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final List<WeightHistoryPoint> points;
}

class UserProfileResponse {
  const UserProfileResponse({
    required this.userId,
    required this.nickname,
    this.avatarUrl,
  });

  final int userId;
  final String nickname;
  final String? avatarUrl;

  factory UserProfileResponse.fromJson(Map<String, dynamic> json) =>
      UserProfileResponse(
        userId: (json['userId'] as num).toInt(),
        nickname: json['nickname'] as String,
        avatarUrl: json['avatarUrl'] as String?,
      );
}
