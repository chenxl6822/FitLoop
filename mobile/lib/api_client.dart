import 'dart:convert';
import 'dart:io';

const defaultApiBaseUrl = String.fromEnvironment(
  'FITLOOP_API_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

abstract class FitLoopApi {
  Future<UserSession> login({
    required String account,
    required String password,
  });

  Future<void> register({
    required String account,
    required String password,
    required String nickname,
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
  });

  Future<SportStats> sportStats({required String token});

  Future<List<SportTarget>> currentTargets({required String token});

  Future<SportTarget> createTarget({
    required String token,
    required String periodType,
    required String metric,
    required double targetValue,
  });

  Future<MedalSummary> medalSummary({required String token});

  Future<RankingResult> ranking({
    required String token,
    String scope = 'personal',
    String period = 'week',
    int page = 1,
    int size = 20,
  });
}

class HttpFitLoopApi implements FitLoopApi {
  HttpFitLoopApi({this.baseUrl = defaultApiBaseUrl});

  final String baseUrl;
  final HttpClient _client = HttpClient();

  @override
  Future<UserSession> login({
    required String account,
    required String password,
  }) async {
    final body = await _post('/api/auth/login', {
      'account': account,
      'password': password,
      'loginType': 'password',
    });
    final data = body['data'] as Map<String, dynamic>;
    final profile = data['userProfile'] as Map<String, dynamic>;
    return UserSession(
      token: data['token'] as String,
      userId: profile['userId'] as int,
      nickname: profile['nickname'] as String? ?? 'FitLoop 用户',
    );
  }

  @override
  Future<void> register({
    required String account,
    required String password,
    required String nickname,
  }) async {
    final isEmail = account.contains('@');
    await _post('/api/user/register', {
      if (isEmail) 'email': account else 'phone': account,
      'password': password,
      'nickname': nickname,
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
  }) async {
    final body = await _post(
      '/api/sport/session/finish',
      {
        'sessionId': sessionId,
        'durationSeconds': durationSeconds,
        'weightKg': weightKg,
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
  Future<MedalSummary> medalSummary({required String token}) async {
    final body = await _get('/api/social/medal', token: token);
    final data = body['data'] as Map<String, dynamic>;
    return MedalSummary.fromJson(data);
  }

  @override
  Future<RankingResult> ranking({
    required String token,
    String scope = 'personal',
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

  Future<Map<String, dynamic>> _get(String path, {String? token}) async {
    final request = await _client.getUrl(Uri.parse('$baseUrl$path'));
    _setHeaders(request, token);
    return _send(request);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload, {
    String? token,
  }) async {
    final request = await _client.postUrl(Uri.parse('$baseUrl$path'));
    _setHeaders(request, token);
    request.write(jsonEncode(payload));
    return _send(request);
  }

  void _setHeaders(HttpClientRequest request, String? token) {
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
  }

  Future<Map<String, dynamic>> _send(HttpClientRequest request) async {
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    final body = text.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(text) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('请求失败：HTTP ${response.statusCode}');
    }
    if (body['code'] != 0) {
      throw ApiException(body['message'] as String? ?? '请求失败');
    }
    return body;
  }
}

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UserSession {
  const UserSession({
    required this.token,
    required this.userId,
    required this.nickname,
  });

  final String token;
  final int userId;
  final String nickname;
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
  });

  final int recordId;
  final int status;
  final int durationSeconds;
  final double distanceKm;
  final double calorie;
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
