import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const defaultApiBaseUrl = String.fromEnvironment(
  'FITLOOP_API_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

abstract class FitLoopApi {
  Future<UserSession> login({
    required String account,
    required String password,
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

  Future<UserSearchResponse> searchUsers({required String token, required String query});

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

  Future<String> uploadSportPhoto({
    required String token,
    required String imagePath,
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
    String loginType = 'password',
  }) async {
    final body = await _post('/api/auth/login', {
      'account': account,
      'password': password,
      'loginType': loginType,
    });
    final data = body['data'] as Map<String, dynamic>;
    final profile = data['userProfile'] as Map<String, dynamic>;
    return UserSession(
      token: data['token'] as String,
      userId: profile['userId'] as int,
      nickname: profile['nickname'] as String? ?? 'FitLoop 用户',
      avatarUrl: profile['avatarUrl'] as String?,
    );
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
          .map((e) =>
              TargetReminderResponse.fromJson(e as Map<String, dynamic>))
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
  Future<void> addFriend({required String token, required int friendUserId}) async {
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
    try {
      final uri = Uri.parse('$baseUrl/api/user/avatar');
      final client = http.Client();
      try {
        final multipart = http.MultipartRequest('POST', uri);
        multipart.headers['Authorization'] = 'Bearer $token';
        multipart.files
            .add(await http.MultipartFile.fromPath('file', safePath));
        final streamed =
            await client.send(multipart).timeout(const Duration(seconds: 30));
        final response = await http.Response.fromStream(streamed);
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['code'] != 0) {
          throw ApiException(body['message'] as String? ?? '上传失败');
        }
        return body['data'] as String;
      } finally {
        client.close();
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('头像上传失败，请检查网络后重试');
    }
  }

  @override
  Future<UserProfileResponse> getUserProfile({required String token}) async {
    final data = await _get('/api/user/profile', token: token);
    return UserProfileResponse.fromJson(data['data'] as Map<String, dynamic>);
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
  Future<String> uploadSportPhoto({
    required String token,
    required String imagePath,
  }) async {
    final safePath = await _safeFilePath(imagePath);
    try {
      final uri = Uri.parse('$baseUrl/api/sport/photo');
      final client = http.Client();
      try {
        final multipart = http.MultipartRequest('POST', uri);
        multipart.headers['Authorization'] = 'Bearer $token';
        multipart.files
            .add(await http.MultipartFile.fromPath('file', safePath));
        final streamed =
            await client.send(multipart).timeout(const Duration(seconds: 30));
        final response = await http.Response.fromStream(streamed);
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['code'] != 0) {
          throw ApiException(body['message'] as String? ?? '上传照片失败');
        }
        return body['data'] as String;
      } finally {
        client.close();
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('照片上传失败，请检查网络后重试');
    }
  }

  Future<String> _safeFilePath(String imagePath) async {
    // Try to handle content:// URIs by reading bytes to a temp file
    try {
      final file = File(imagePath);
      if (!await file.exists() && imagePath.startsWith('content://')) {
        // content:// URIs can't be read via dart:io File on Android
        // Fall through and let MultipartFile.fromPath handle it
        return imagePath;
      }
      // For valid file paths, copy to temp to ensure clean upload
      final bytes = await file.readAsBytes();
      final dir = Directory.systemTemp;
      final tempFile = File(
          '${dir.path}/fitloop_upload_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(bytes);
      return tempFile.path;
    } catch (_) {
      // If anything fails, return original path and let the upload try
      return imagePath;
    }
  }

  Future<Map<String, dynamic>> _put(String path,
      {Map<String, dynamic>? body, String? token}) async {
    final request = await _client.putUrl(Uri.parse('$baseUrl$path'));
    _setHeaders(request, token);
    request.write(jsonEncode(body ?? <String, dynamic>{}));
    return _send(request);
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

  /// 提取后端错误消息；HTTP 40x/50x 统一前置处理
  String _extractErrorMessage(Map<String, dynamic> body, int statusCode) {
    // 优先用后端返回的 message
    if (body.containsKey('message') && body['message'] is String && (body['message'] as String).isNotEmpty) {
      return body['message'] as String;
    }
    // 后端 code != 0 但没有 message
    if (statusCode >= 500) return '服务器开小差了，请稍后重试';
    if (statusCode == 401 || statusCode == 403) return '登录状态已过期，请重新登录';
    return '请求失败（$statusCode）';
  }

  Future<Map<String, dynamic>> _send(HttpClientRequest request) async {
    try {
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      final body = text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(_extractErrorMessage(body, response.statusCode));
      }
      if (body['code'] != 0 && body['code'] != 200) {
        throw ApiException(_extractErrorMessage(body, response.statusCode));
      }
      return body;
    } on SocketException {
      throw ApiException('无法连接服务器，请检查网络或稍后重试');
    } on HttpException {
      throw ApiException('无法连接服务器，请检查网络或稍后重试');
    }
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
    this.avatarUrl,
  });

  final String token;
  final int userId;
  final String nickname;
  final String? avatarUrl;
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
