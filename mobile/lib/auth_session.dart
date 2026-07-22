class UserSession {
  const UserSession({
    required this.token,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
    required this.nickname,
    this.avatarUrl,
    this.role = 'USER',
  });

  final String token;
  final String refreshToken;
  final DateTime expiresAt;
  final int userId;
  final String nickname;
  final String? avatarUrl;
  final String role;

  bool get isAdmin => role == 'ADMIN';

  bool expiresWithin(Duration window, DateTime now) =>
      !expiresAt.isAfter(now.toUtc().add(window));

  UserSession copyWith({
    String? token,
    String? refreshToken,
    DateTime? expiresAt,
    int? userId,
    String? nickname,
    String? avatarUrl,
    String? role,
  }) {
    return UserSession(
      token: token ?? this.token,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      userId: userId ?? this.userId,
      nickname: nickname ?? this.nickname,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
    );
  }
}

abstract interface class SessionStore {
  Future<UserSession?> load();

  Future<void> save(UserSession session);

  Future<void> clear();
}

abstract interface class SessionAwareApi {
  Stream<UserSession?> get sessionChanges;

  Future<UserSession?> restoreSession();

  Future<void> logoutSession();
}
