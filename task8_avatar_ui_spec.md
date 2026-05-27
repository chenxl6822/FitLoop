# 任务 8：头像上传 UI 实现规范

## 背景

FitLoop 后端已存在 `AvatarController.java`（POST `/api/user/avatar`，multipart），Flutter 端缺少上传 UI、image_picker 集成、API 调用、头像本地持久化。

## 改动清单

### 1. pubspec.yaml

在 `dependencies:` 段添加：

```yaml
  image_picker: ^1.1.2
```

### 2. api_client.dart 新增

**a. `UserSession` 扩展「avatarUrl」字段**

```dart
const UserSession({
  required this.token,
  required this.userId,
  required this.nickname,
  this.avatarUrl,           // 新增，nullable
});
final String? avatarUrl;
```

**b. `FitLoopApi` 抽象类增加抽象方法**

```dart
Future<String> uploadAvatar({
  required String token,
  required String imagePath,
});

Future<UserProfileResponse> getUserProfile({required String token});
```

**c. `HttpFitLoopApi` 实现新增方法**

```dart
// uploadAvatar: multipart/form-data 上传（注意 HttpFitLoopApi 用 dart:io HttpClient）
// 不需要改造整个架构，用 MultipartRequest 即可。
Future<String> uploadAvatar({
  required String token,
  required String imagePath,
}) async {
  final uri = Uri.parse('$baseUrl/api/user/avatar');
  final request = await _client.postUrl(uri);
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  // 构造 multipart body (注意 _client 是 HttpClient，MultipartRequest 不可复用，
  // 改用 HttpClientRequest 手动写 multipart 或另起 http package 的 MultipartRequest)
  // 推荐方案：在 uploadAvatar 内单独使用 `package:http/http.dart` 的 MultipartRequest
  // 因为 dart:io HttpClientRequest 手动写 multipart 很麻烦且容易错。
  final multipart = http.MultipartRequest('POST', uri);
  multipart.headers['Authorization'] = 'Bearer $token';
  multipart.files.add(await http.MultipartFile.fromPath('file', imagePath));
  final streamed = await multipart.send();
  final response = await http.Response.fromStream(streamed);
  // 解析 ApiResponse 格式
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  if (body['code'] != 0) throw ApiException(body['message'] as String? ?? '上传失败');
  return body['data'] as String;
}

// getUserProfile: GET /api/user/profile 获取用户详情（含 avatarUrl）
Future<UserProfileResponse> getUserProfile({required String token}) async {
  final data = await _get('/api/user/profile', token: token);
  return UserProfileResponse.fromJson(data['data'] as Map<String, dynamic>);
}
```

> 注意：需要在文件头 `import 'package:http/http.dart' as http;`（如果未导入）。
> 在 pubspec.yaml 中确认或添加 `http: ^1.2.1` 依赖。

**d. 新增响应模型**

```dart
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
```

### 3. main.dart — ProfilePage 改动

**a. ProfilePage 构造函数**

- 保持现有参数不变（`api`, `reminderScheduler`, `session`）
- 新增 None

**b. ProfilePage 构建**

在 `_PageScaffold` 的 `children` 最顶部（排在"账号状态"卡片之前）**插入头像区块**：

```
□ ┌──────────────────────┐
  │     [圆形头像 80x80]  │
  │    昵称 (widget.session.nickname)  │
  │    [点击更换头像]     │
  └──────────────────────┘
```

实现要点：

- 使用 `CircleAvatar(radius: 40, backgroundImage: NetworkImage(...))` 展示头像
- 没有头像时显示 `Icon(Icons.person, size: 48)` 的占位图
- 头像区块可点击：弹出 `showModalBottomSheet` 让用户选择"拍照"或"从相册选择"
- 选图后调用 `widget.api.uploadAvatar()`，成功后更新状态

**c. 状态变量**

```dart
String? _avatarUrl;
bool _uploading = false;
```

- `_avatarUrl` 初始化值：优先从 `widget.session.avatarUrl`，其次从缓存读取

**d. 交互流程**

```
点击头像块 → BottomSheet(拍照 | 从相册选择)
     ↓ 选择图片
showUploadingIndicator
     ↓ 调用 api.uploadAvatar(token, imagePath)
     ↓ 成功
更新 _avatarUrl
缓存头像URL到 SharedPreferences（key: 'avatarUrl_${userId}'）
     ↓ 失败
SnackBar 显示错误
```

**e. 退出登录时清理**

已有的 `TokenStorage.clear()` 调用中增加：

```dart
await LocalCache.clearAll(); // 或仅清除头像缓存的 key
```

### 4. local_cache.dart — 新增头像缓存方法（可选）

如果 ProfilePage 直接从 api.getUserProfile() 加载，也可不额外缓存。

建议简单做法：在成功后 `SharedPreferences` 缓存一次，下次启动直接读取。

## 验收标准

- [x] `flutter pub get` 成功后无编译错误
- [x] `flutter analyze` 0 问题
- [x] `flutter test` 全部通过（现有 8 test，可能需要 mock uploadAvatar）
- [ ] 我的页面展示圆形头像（有图显示图片，无图显示占位图标）
- [ ] 点击头像弹出选图对话框（拍照/相册）
- [ ] 选择图片后显示上传中状态
- [ ] 上传成功后头像实时刷新
- [ ] 重启 App 头像持久化（从 SharedPreferences 或 getUserProfile 加载）

## 测试要求

更新 `widget_test.dart`：
- 在 `_MockApi` 类中新增 `uploadAvatar` 和 `getUserProfile` 的 mock 实现
- 保证现有 8 个 test 全部通过，不新增 test（保持覆盖率不降即可）

## 代码规范

- 样式与现有 Material3 主题一致（主色 `#1F8A70`）
- 中文提示文字用简体中文
- 遵循现有 `_PageScaffold` 布局模式
- 不需要单独的 `profile_page.dart` 文件，ProfilePage 保留在 main.dart 中（项目当前架构如此）
