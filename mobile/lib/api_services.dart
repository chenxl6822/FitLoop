import 'api_models.dart';
import 'auth_session.dart';

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

  Future<AgentRunCreated> createCoachRun({
    required String token,
    required String objective,
  });

  Future<AgentRunDetail> getAgentRun({
    required String token,
    required String runId,
  });

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

  Future<AgentProposalDecision> confirmAgentProposal({
    required String token,
    required int proposalId,
  });

  Future<AgentProposalDecision> rejectAgentProposal({
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
