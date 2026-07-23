import 'dart:convert';

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

class AgentRunCreated {
  const AgentRunCreated({
    required this.runId,
    required this.type,
    required this.status,
    required this.traceId,
  });

  factory AgentRunCreated.fromJson(Map<String, dynamic> json) {
    return AgentRunCreated(
      runId: json['runId'] as String,
      type: json['type'] as String,
      status: json['status'] as String,
      traceId: json['traceId'] as String,
    );
  }

  final String runId;
  final String type;
  final String status;
  final String traceId;
}

class AgentRunDetail {
  const AgentRunDetail({
    required this.runId,
    required this.type,
    required this.status,
    required this.traceId,
    this.resultJson,
    this.errorMessage,
    this.proposals = const <AgentProposalItem>[],
  });

  factory AgentRunDetail.fromJson(Map<String, dynamic> json) {
    final proposalJson =
        json['proposals'] as List<dynamic>? ?? const <dynamic>[];
    return AgentRunDetail(
      runId: json['runId'] as String,
      type: json['type'] as String,
      status: json['status'] as String,
      traceId: json['traceId'] as String,
      resultJson: json['resultJson'] as String?,
      errorMessage: json['errorMessage'] as String?,
      proposals: proposalJson
          .map((item) =>
              AgentProposalItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  final String runId;
  final String type;
  final String status;
  final String traceId;
  final String? resultJson;
  final String? errorMessage;
  final List<AgentProposalItem> proposals;

  CoachAdvice? get advice => CoachAdvice.tryParse(resultJson);

  bool get shouldPoll =>
      status == 'QUEUED' || status == 'RUNNING' || status == 'FAILED_RETRYABLE';
}

class CoachAdvice {
  const CoachAdvice({
    required this.answer,
    required this.rationale,
    required this.safetyNotices,
  });

  static CoachAdvice? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final answer = decoded['answer'];
      if (answer is! String || answer.trim().isEmpty) return null;
      return CoachAdvice(
        answer: answer.trim(),
        rationale: _stringList(decoded['rationale']),
        safetyNotices: _stringList(decoded['safety_notices']),
      );
    } catch (_) {
      return null;
    }
  }

  static List<String> _stringList(Object? value) {
    if (value is! List<dynamic>) return const <String>[];
    return value.whereType<String>().map((item) => item.trim()).where(
      (item) {
        return item.isNotEmpty;
      },
    ).toList(growable: false);
  }

  final String answer;
  final List<String> rationale;
  final List<String> safetyNotices;
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

class TrainingPlanDayPreview {
  const TrainingPlanDayPreview({
    required this.day,
    required this.sessionType,
    required this.durationMinutes,
    required this.intensity,
    this.notes,
  });

  final int day;
  final String sessionType;
  final int durationMinutes;
  final String intensity;
  final String? notes;
}

class TrainingPlanPreview {
  const TrainingPlanPreview({
    required this.title,
    required this.goal,
    required this.days,
  });

  static const _topLevelFields = <String>{'title', 'goal', 'days'};
  static const _dayFields = <String>{
    'day',
    'session_type',
    'duration_minutes',
    'intensity',
    'notes',
  };
  static const _requiredDayFields = <String>{
    'day',
    'session_type',
    'duration_minutes',
    'intensity',
  };
  static const _knownIntensities = <String>{'LOW', 'MODERATE', 'HIGH'};

  static TrainingPlanPreview? tryParse(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded.keys.toSet().difference(_topLevelFields).isNotEmpty ||
          !_topLevelFields.every(decoded.containsKey)) {
        return null;
      }

      final title = decoded['title'];
      final goal = decoded['goal'];
      final rawDays = decoded['days'];
      if (!_validRequiredString(title, 120) ||
          !_validRequiredString(goal, 300) ||
          rawDays is! List<dynamic> ||
          rawDays.isEmpty ||
          rawDays.length > 28) {
        return null;
      }

      final days = <TrainingPlanDayPreview>[];
      for (final rawDay in rawDays) {
        if (rawDay is! Map<String, dynamic> ||
            rawDay.keys.toSet().difference(_dayFields).isNotEmpty ||
            !_requiredDayFields.every(rawDay.containsKey)) {
          return null;
        }

        final day = rawDay['day'];
        final sessionType = rawDay['session_type'];
        final durationMinutes = rawDay['duration_minutes'];
        final intensity = rawDay['intensity'];
        final notes = rawDay['notes'];
        if (day is! int ||
            day < 1 ||
            day > 28 ||
            !_validRequiredString(sessionType, 80) ||
            durationMinutes is! int ||
            durationMinutes < 5 ||
            durationMinutes > 180 ||
            intensity is! String ||
            !_knownIntensities.contains(intensity) ||
            !_validOptionalString(notes, 300)) {
          return null;
        }

        days.add(
          TrainingPlanDayPreview(
            day: day,
            sessionType: sessionType as String,
            durationMinutes: durationMinutes,
            intensity: intensity,
            notes: notes as String?,
          ),
        );
      }

      return TrainingPlanPreview(
        title: title as String,
        goal: goal as String,
        days: List.unmodifiable(days),
      );
    } catch (_) {
      return null;
    }
  }

  static bool _validRequiredString(Object? value, int maxLength) {
    return value is String &&
        value.trim().isNotEmpty &&
        value.length <= maxLength;
  }

  static bool _validOptionalString(Object? value, int maxLength) {
    return value == null || (value is String && value.length <= maxLength);
  }

  final String title;
  final String goal;
  final List<TrainingPlanDayPreview> days;
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
    String? expiresAt,
  }) : _expiresAt = expiresAt;

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
      expiresAt: json['expiresAt'] as String?,
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
  final String? _expiresAt;

  DateTime? get expiresAt {
    final raw = _expiresAt;
    if (raw == null || !RegExp(r'(?:Z|[+-]\d{2}:\d{2})$').hasMatch(raw)) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }

  TrainingPlanPreview? get trainingPlanPreview {
    return TrainingPlanPreview.tryParse(payloadJson);
  }

  bool isExpiredAt(DateTime now) {
    final expiration = expiresAt;
    return expiration == null || !expiration.isAfter(now.toUtc());
  }
}

class AgentProposalDecision {
  const AgentProposalDecision({
    required this.proposalId,
    required this.status,
    this.affectedResourceId,
  });

  factory AgentProposalDecision.fromJson(Map<String, dynamic> json) {
    return AgentProposalDecision(
      proposalId: json['proposalId'] as int,
      status: json['status'] as String,
      affectedResourceId: json['affectedResourceId'] as int?,
    );
  }

  final int proposalId;
  final String status;
  final int? affectedResourceId;
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
