--------------------------10eafc020df97be7
Content-Disposition: form-data; name="content"

# FitLoop 阶段 1 — 开发任务说明书

> **目标：** 由 Claude（或其他 AI 编码助手）安全、完整、可靠地完成 FitLoop 第一阶段开发。
> **预计工时：** ~12h
> **核心任务：** 补齐 4 种打卡方式 + 多运动类型 + 验证码系统

---

## 📖 目录

1. [项目背景](#1-项目背景)
2. [架构红线](#2-架构红线)
3. [阶段 1 需求清单](#3-阶段-1-需求清单)
4. [代码文件索引](#4-代码文件索引)
5. [任务 A：多运动类型支持](#5-任务-a多运动类型支持)
6. [任务 B：传感器打卡（计步器/跳绳）](#6-任务-b传感器打卡计步器跳绳)
7. [任务 C：拍照打卡](#7-任务-c拍照打卡)
8. [任务 D：手动打卡](#8-任务-d手动打卡)
9. [任务 E：手机验证码注册/登录](#9-任务-e手机验证码注册登录)
10. [测试规范](#10-测试规范)
11. [Git 流程](#11-git-流程)
12. [常见陷阱与排查](#12-常见陷阱与排查)

---

## 1. 项目背景

FitLoop 是一个校园运动打卡与健康管理应用。

| 维度 | 值 |
|------|-----|
| **前端** | Flutter（Dart），Android 8.0+ / iOS 13.0+ |
| **后端** | Spring Boot 3.3.5（Java 17） |
| **数据库** | MySQL 8.0（生产）/ H2（测试） |
| **缓存** | Redis 6.2 |
| **鉴权** | JWT（Spring Security） |
| **部署** | Docker Compose（MySQL + Redis + Backend + Nginx） |
| **CI** | GitHub Actions（`flutter analyze + test` + `mvn test`） |
| **GitHub** | `https://github.com/chenxl6822/FitLoop` |
| **当前 HEAD** | `b903b09` — feat: add splash screen and onboarding pages |
| **Git 远程** | `origin/main`（已推送） |

### 当前状态

- 12 个基础任务已全部完成（11 commits）
- Flutter: 9 widget tests, 0 analyze issues
- Backend: 47 @Test, 9 test files，全部通过
- 需求实现度 **~65%**，P0 缺口：多打卡方式、多运动类型、验证码

---

## 2. 架构红线

> ⚠️ **以下规则必须严格遵守。违反将导致 Code Review 不通过。**

### 2.1 前端（Flutter）

1. **无状态管理框架** — 绝对不用 Provider / Riverpod / GetX / BLoC。全部用 `setState` + 构造注入。
2. **所有 UI 页面在 `main.dart`** — 不拆分文件。这是一个已知技术债务，阶段 1 仍保持。
3. **网络调用** — 绝大多数用 `dart:io HttpClient` 封装在 `api_client.dart` 的 `_get()` / `_post()` / `_put()`。
   - 只有头像上传用 `http.MultipartRequest`（已有先例）。
4. **离线数据** — 全部经过 `SharedPreferences`，通过 `LocalCache` / `SyncQueue` 管理。
5. **新增的枚举/label** — 统一放在 `_kValues` 常量 map 或页面顶部的 static const 中，方便维护。

### 2.2 后端（Spring Boot）

1. **不使用 `@SpringBootTest`** — 测试全部用 `@DataJpaTest`（Service 层）+ `@WebMvcTest`（Controller 层）。
2. **测试数据库** — H2 内存数据库（`application-test.yml` 已配置），不需要 MySQL。
3. **统一响应** — 全部通过 `ApiResponse.ok(data)` 返回。
4. **鉴权** — 通过 `AuthSupport.currentUserId()` 获取当前用户 ID，Controller 参数不需要显式传 userId。
5. **DTO** — 用 Java `record` 类型，统一放在 `*Dtos.java` 文件中。
6. **实体** — JPA `@Entity` + getter/setter 风格（非 @Data）。

### 2.3 禁止修改的稳定模块

以下文件已经稳定，**除非功能需求明确要求修改，否则不要动**：

- `api_client.dart` — 接口定义和 models (可新增方法，不修改已有签名)
- `local_cache.dart` — 缓存逻辑稳定
- `connectivity_service.dart` — 网络探测稳定
- `sync_queue.dart` — 离线队列稳定
- `stats_charts.dart` — 图表组件稳定
- `reminder_scheduler.dart` — 通知调度稳定

---

## 3. 阶段 1 需求清单

| ID | 需求 | 级别 | 状态 |
|----|------|------|------|
| **1.1** | 多运动类型：跑步/骑行/健走/跳绳/自定义 | P0 | ❌ |
| **1.2** | 传感器打卡-计步器（基于 `sensor` API） | P0 | ❌ |
| **1.3** | 传感器打卡-跳绳计数 | P0 | ❌ |
| **1.4** | 拍照打卡（上传运动照片作为凭证） | P0 | ❌ |
| **1.5** | 手动打卡（自行输入运动数据：时长/距离/卡路里） | P0 | ❌ |
| **1.6** | 手机验证码注册 | P0 | ❌ |
| **1.7** | 手机验证码登录 | P0 | ❌ |
| **1.8** | 完整测试覆盖（前端+后端） | P0 | ❌ |

### 需求详解

#### 3.1 多运动类型

当前只有 `"running"` 一种（硬编码在 `SportSessionPage` 的 `sportType: 'running'`）。

需要支持的 5 种类型：

| 类型键 | 中文名 | 场景 |
|--------|--------|------|
| `running` | 跑步 | GPS/手动 |
| `cycling` | 骑行 | GPS/手动 |
| `walking` | 健走 | 计步器/手动 |
| `rope_skipping` | 跳绳 | 跳绳计数/手动 |
| `custom` | 自定义 | 手动 |

MET 值（后端 `CalorieCalculator` **已有**，需要验证覆盖）：
- running → 8.0
- cycling → 6.8
- walking → 3.8
- rope_skipping → 11.0
- custom → 4.5（默认）

用户需要在开始打卡前选择运动类型。UI 上用一个 `DropdownButton` 或 `SegmentedButton` 来切换。

#### 3.2 传感器打卡-计步器

Android 原生计步传感器（`TYPE_STEP_DETECTOR` / `TYPE_STEP_COUNTER`）。

- 用 `pedometer` 或 `sensors_plus` 包获取步数
- 开始打卡时记录初始步数
- 结束打卡时计算步数差 → 估算距离（平均步长 ≈ 身高×0.45，默认 0.7m）
- 距离(km) = 步数 × 步长(m) / 1000
- 卡路里 = MET × 体重 × 时长(h)
- 上传 `checkinMode: 'sensor'`

#### 3.3 传感器打卡-跳绳计数

类似计步器方案，但用专用的 `sensor: rope_skipping` 模式。

- 可用手机加速度传感器计算跳跃次数（或用计步器近似）
- 每次跳 ≈ 消耗 0.1-0.2 kcal（按体重计算）
- 跳绳计数 → 估算时长 / 频率

简单实现：让用户手动输入跳绳次数，系统估算卡路里。

#### 3.4 拍照打卡

用户从相册选择或拍摄一张运动照片作为打卡凭证。

- 复用 `image_picker`（已在 pubspec.yaml + api_client 中集成）
- 开始打卡 → 选择运动类型 → 选择拍照 → 上传图片 → 调用后端创建打卡记录
- 图片上传复用 `uploadAvatar` 的 `http.MultipartRequest` 模式（但 POST 到 `/api/sport/photo`）
- 上传成功后拿到 photoUrl，写入打卡记录
- `checkinMode: 'photo'`

#### 3.5 手动打卡

不需要传感器/GPS，用户直接输入：

- 运动时长（分钟）
- 运动距离（公里，可选）
- 运动消耗（卡路里，可选）
- 备注

用表单页面完成，`checkinMode: 'manual'`。

#### 3.6 手机验证码注册/登录

后端新增：
- `SmsCode` 实体：phone + code + expiresAt + used
- `POST /api/sms/send` — 生成 6 位随机码，存数据库，返回成功（实际不发送短信，仅调试）
- 注册/登录时 `loginType: 'code'` 走验证码验证

前端新增：
- 注册页新增验证码输入框 + 获取验证码按钮（60s 倒计时）
- 登录页新增验证码登录 Tab

---

## 4. 代码文件索引

### 前端文件（需修改）

| 文件 | 行数 | 改动内容 |
|------|------|----------|
| `mobile/lib/main.dart` | ~2400 | 新增运动类型选择 UI，传感器打卡 UI，手动打卡表单，拍照打卡 UI，验证码 UI |
| `mobile/lib/api_client.dart` | ~1070 | 新增 `startSport` 参数化（已支持），新增 `finishSportWithPhoto` 方法，新增验证码 API |
| `mobile/pubspec.yaml` | — | 新增 `sensors_plus` / `pedometer` 包依赖 |

### 后端文件（需修改或新增）

| 文件 | 改动 |
|------|------|
| `SportService.java` | 支持 photo/checkinMode/sportType 扩展（已有基础），新增传感器/手动打卡逻辑 |
| `SportController.java` | 新增 photo 上传端点，验证码端点 |
| `SportRecord.java` | 已有 photoUrl/checkinMode/sportType 字段，可能需补充备注字段 |
| `CalorieCalculator.java` | **已有** 5 种运动类型 MET，验证即可 |
| `UserService.java` | 新增验证码注册/登录逻辑 |
| `UserController.java` | 新增验证码端点 |
| **NEW** `SmsCode.java` | 验证码实体 |
| **NEW** `SmsCodeRepository.java` | 验证码 Repository |
| **NEW** `SmsService.java` | 验证码发送/验证逻辑 |

### 测试文件（需新增或修改）

| 文件 | 内容 |
|------|------|
| `SportServiceTest.java` | 新增多运动类型、多打卡方式测试 |
| `SportControllerTest.java` | 新增 Controller 层测试（创建新文件） |
| `UserServiceTest.java` | 新增验证码测试 |
| `widget_test.dart` | 新增多运动类型、打卡方式 UI 测试 |

---

## 5. 任务 A：多运动类型支持

### 后端改动

**CalorieCalculator.java** — 验证（已有，不需修改）：

```java
public double estimate(String sportType, double weightKg, long durationSeconds) {
    double met = switch (sportType.toLowerCase(Locale.ROOT)) {
        case "running", "跑步" -> 8.0;
        case "cycling", "骑行" -> 6.8;
        case "walking", "健走" -> 3.8;
        case "rope_skipping", "跳绳" -> 11.0;
        default -> 4.5; // custom / 自定义
    };
    return round(met * weightKg * durationSeconds / 3600.0);
}
```

**SportService.java** — 验证 `start()` 方法，sportType 和 checkinMode 已经通过 request 传入，不需要修改。但需要确认 `finish()` 方法在 `checkinMode = 'manual'` 或 `'sensor'` 时能正常工作（没有 GPS 轨迹也能结束）。

**改动点：** `finish()` 方法应处理 trackJson 为空的情况（手动/传感器打卡无轨迹）：

```java
// 在 finish() 中，在调用 summarize() 前加判断
List<Map<String, Object>> points = readTrack(record);
TrackSummary summary;
if (points.isEmpty()) {
    summary = new TrackSummary(0.0, false, null);
} else {
    summary = summarize(points);
}
```

### 前端改动

**main.dart — `SportSessionPage` 顶部新增运动类型选择器：**

```dart
// 运动类型常量（放在 SportSessionPage 外部，类顶部）
const _sportTypes = {
  'running': '跑步',
  'cycling': '骑行',
  'walking': '健走',
  'rope_skipping': '跳绳',
  'custom': '自定义',
};

// 在 State 中新增字段
String _selectedSportType = 'running';
```

UI 在开始打卡按钮上方加一个选择器（DropdownButton / SegmentedButton / Chip row）：

```dart
// 仅在未开始运动时显示
if (_sessionId == null) ...[
  Text('选择运动类型：'),
  DropdownButton<String>(
    value: _selectedSportType,
    items: _sportTypes.entries.map((e) => DropdownMenuItem(
      value: e.key,
      child: Text(e.value),
    )).toList(),
    onChanged: (v) => setState(() => _selectedSportType = v!),
  ),
],
```

**打卡方式选择：** 当前打卡方式默认 `'gps'`。改为让用户点击开始打卡时选择方式：

```dart
// 弹出一个 modal bottom sheet，让用户选择打卡方式
Future<String?> _chooseCheckinMode() {
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(
        leading: Icon(Icons.location_on),
        title: Text('GPS 定位打卡'),
        subtitle: Text('适合跑步、骑行等室外运动'),
        onTap: () => Navigator.pop(ctx, 'gps'),
      ),
      ListTile(
        leading: Icon(Icons.directions_walk),
        title: Text('传感器打卡'),
        subtitle: Text('计步器/跳绳计数'),
        onTap: () => Navigator.pop(ctx, 'sensor'),
      ),
      ListTile(
        leading: Icon(Icons.camera_alt),
        title: Text('拍照打卡'),
        subtitle: Text('上传运动照片作为凭证'),
        onTap: () => Navigator.pop(ctx, 'photo'),
      ),
      ListTile(
        leading: Icon(Icons.edit),
        title: Text('手动打卡'),
        subtitle: Text('自行输入运动数据'),
        onTap: () => Navigator.pop(ctx, 'manual'),
      ),
    ]),
  );
}
```

**修改 _toggle() 方法：** 用 `_selectedSportType` 替代硬编码 `'running'`，用 `_selectedCheckinMode` 替代硬编码 `'gps'`。

**后端已支持：** `SportDtos.StartSessionRequest` 已有 `@NotBlank String sportType` 和 `@NotBlank String checkinMode`，`SportRecord` 实体也有对应字段。所以只要前端传对，后端无需改。

---

## 6. 任务 B：传感器打卡（计步器/跳绳）

### 前端改动

**pubspec.yaml — 新增依赖：**

```yaml
dependencies:
  sensors_plus: ^6.0.0   # 或 pedometer: ^4.0.0
```

注意：优先使用 `sensors_plus`，它同时支持计步器和加速度传感器。

**main.dart — 新增传感器服务抽象和实现：**

```dart
// 在 LocationService 同级位置新增
abstract class PedometerService {
  Stream<int> get stepCountStream;
  Future<int> get currentStepCount;
  void dispose();
}

class AndroidPedometerService implements PedometerService {
  int _initialSteps = 0;
  
  @override
  Future<int> get currentStepCount async {
    // 使用 sensors_plus 或 MethodChannel 读取当前步数
    // 简化实现：第一次获取记录初始值，后续差值 = 运动步数
    return 0;
  }
  
  @override
  Stream<int> get stepCountStream => Stream.periodic(
    const Duration(seconds: 5), (_) => /* 当前步数 */ 0
  );
  
  @override
  void dispose() {}
}
```

**传感器打卡流程：**
1. 用户选择「传感器打卡」
2. 显示运动类型选择器（默认健走/跳绳）
3. 点击开始 → 读取初始步数 → 计时
4. 实时显示当前步数（如果是跳绳模式，显示估算次数）
5. 点击结束 → 计算步数差 → 估算距离和卡路里 → 调用 finishSport
6. `checkinMode: 'sensor'`

**传感器打卡UI（在 SportSessionPage 中）：**

```dart
// 新增状态
int _stepCount = 0;
int _initialSteps = 0;

// 在 _toggle() 中添加 sensor 分支
if (_selectedCheckinMode == 'sensor') {
  // 计步器逻辑
  // 不需要 GPS 权限，不需要 locationService
  // 直接用 stepCountStream 监听
}
```

### 后端改动

**SportService.java — 确保传感器打卡无需轨迹也能完成：**

```java
// finish() 方法中，对 checkinMode 为 'sensor' 或 'manual' 或 'photo' 的处理：
// 如果 trackJson 为空，直接按传入参数计算距离/卡路里
if ("sensor".equals(record.getCheckinMode()) || "manual".equals(record.getCheckinMode())) {
    // 不校验轨迹数据
    // 距离和卡路里由前端提供或按默认公式计算
}
```

---

## 7. 任务 C：拍照打卡

### 前端改动

**main.dart — 拍照打卡流程：**

1. 用户选择「拍照打卡」
2. 选择运动类型
3. 点击「拍照」
4. 调用 `ImagePicker().pickImage(source: ImageSource.camera)`（或 gallery）
5. 拿到照片后，上传到后端获取 photoUrl
6. 带上 photoUrl 调用 startSport
7. 短暂显示运动进行中（计时器）
8. 用户点击结束 → 输入估算的时长和距离 → 调用 finishSport
9. `checkinMode: 'photo'`

**api_client.dart — 新增照片上传方法：**

```dart
@override
Future<String> uploadSportPhoto({
  required String token,
  required String imagePath,
}) async {
  final uri = Uri.parse('$baseUrl/api/sport/photo');
  final multipart = http.MultipartRequest('POST', uri);
  multipart.headers['Authorization'] = 'Bearer $token';
  multipart.files.add(await http.MultipartFile.fromPath('file', imagePath));
  final streamed = await multipart.send();
  final response = await http.Response.fromStream(streamed);
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  if (body['code'] != 0) {
    throw ApiException(body['message'] as String? ?? '上传照片失败');
  }
  return body['data'] as String; // photoUrl
}
```

### 后端改动

**SportService.java / SportController.java — 新增照片上传端点：**

```java
// SportController.java
@PostMapping("/photo")
public ApiResponse<String> uploadPhoto(@RequestParam("file") MultipartFile file) {
    String url = sportService.savePhoto(AuthSupport.currentUserId(), file);
    return ApiResponse.ok(url);
}
```

**SportService.java：**

```java
public String savePhoto(Long userId, MultipartFile file) {
    // 1. 验证文件类型（jpg/png）
    // 2. 验证文件大小（< 10MB）
    // 3. 生成文件名：photo_{userId}_{timestamp}.jpg
    // 4. 保存到本地 uploads/photos/ 目录（头像同理存本地）
    //    生产环境应改为 COS/OSS
    // 5. 返回可访问的 URL
    String filename = "photo_" + userId + "_" + Instant.now().toEpochMilli() + ".jpg";
    Path target = Path.of(uploadDir, filename);
    Files.copy(file.getInputStream(), target, StandardCopyOption.REPLACE_EXISTING);
    return "/uploads/photos/" + filename;
}
```

**注意：** 头像上传后端已有 `AvatarController`，照片上传逻辑类似，参考 `AvatarController.java`。

---

## 8. 任务 D：手动打卡

### 前端改动

**main.dart — 手动打卡表单：**

手动打卡不需要实时追踪，直接弹一个表单让用户填写：

```dart
Future<Map<String, dynamic>?> _showManualCheckinForm() async {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom,
        left: 16, right: 16, top: 16,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          decoration: InputDecoration(labelText: '运动时长（分钟）'),
          keyboardType: TextInputType.number,
          controller: _durationController,
        ),
        TextField(
          decoration: InputDecoration(labelText: '运动距离（公里，可选）'),
          keyboardType: TextInputType.number,
          controller: _distanceController,
        ),
        TextField(
          decoration: InputDecoration(labelText: '消耗卡路里（可选）'),
          keyboardType: TextInputType.number,
          controller: _calorieController,
        ),
        TextField(
          decoration: InputDecoration(labelText: '备注（可选）'),
          controller: _noteController,
        ),
        SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, {
            'durationMinutes': int.tryParse(_durationController.text) ?? 30,
            'distanceKm': double.tryParse(_distanceController.text),
            'calorie': double.tryParse(_calorieController.text),
            'note': _noteController.text,
          }),
          child: Text('提交'),
        ),
        SizedBox(height: 16),
      ]),
    ),
  );
}
```

**手动打卡流程（在 _toggle 中添加 manual 分支）：**

1. 用户选择「手动打卡」
2. 弹出表单让用户输入数据
3. 点击提交 → 调用 `startSport(token, sportType, 'manual')` 创建一个 session
4. 再立即调用 `finishSport`，传入用户填写的 duration/distance/calorie
5. `checkinMode: 'manual'`

### 后端改动

**SportService.java — finish() 中，如果 checkinMode 为 manual，跳过 GPS 轨迹校验，直接使用前端传入的数据：**

```java
// 在 finish() 中
if ("manual".equals(record.getCheckinMode())) {
    // 手动打卡不需要轨迹校验
    // 距离/卡路里直接用前端传入值或 CalorieCalculator 计算
}
```

**SportRecord.java — 可选：新增备注字段：**

```java
@Column(length = 500)
private String note;

// + getter/setter
```

---

## 9. 任务 E：手机验证码注册/登录

### 后端 — 新增文件

**SmsCode.java（实体）：**

```java
@Entity
public class SmsCode {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Column(nullable = false, length = 20)
    private String phone;
    
    @Column(nullable = false, length = 6)
    private String code;
    
    @Column(nullable = false)
    private Instant expiresAt;  // 发送后5分钟过期
    
    private boolean used = false;
    
    private Instant createdAt = Instant.now();
    
    // getter/setter ...
}
```

**SmsCodeRepository.java：**

```java
public interface SmsCodeRepository extends JpaRepository<SmsCode, Long> {
    Optional<SmsCode> findTopByPhoneAndCodeAndUsedFalseOrderByCreatedAtDesc(
        String phone, String code);
    
    void deleteByPhone(String phone);
}
```

**SmsService.java：**

```java
@Service
public class SmsService {
    private final SmsCodeRepository smsCodes;
    
    public SmsService(SmsCodeRepository smsCodes) {
        this.smsCodes = smsCodes;
    }
    
    /** 发送验证码（调试模式，不真实发短信，返回到响应中方便测试） */
    @Transactional
    public String sendCode(String phone) {
        // 1. 验证手机号格式（11位数字，以1开头）
        if (!phone.matches("^1\\d{10}$")) {
            throw new IllegalArgumentException("手机号格式不正确");
        }
        // 2. 检查60秒内是否发过（防刷）
        // 3. 生成6位随机码
        String code = String.format("%06d", ThreadLocalRandom.current().nextInt(0, 999999));
        SmsCode entity = new SmsCode();
        entity.setPhone(phone);
        entity.setCode(code);
        entity.setExpiresAt(Instant.now().plus(5, ChronoUnit.MINUTES));
        smsCodes.save(entity);
        return code; // 调试模式返回验证码；生产环境应返回 "ok" 且真实发短信
    }
    
    /** 验证验证码 */
    public boolean verifyCode(String phone, String code) {
        Optional<SmsCode> opt = smsCodes.findTopByPhoneAndCodeAndUsedFalseOrderByCreatedAtDesc(phone, code);
        if (opt.isEmpty()) return false;
        SmsCode entity = opt.get();
        if (entity.isUsed()) return false;
        if (Instant.now().isAfter(entity.getExpiresAt())) return false;
        entity.setUsed(true);
        smsCodes.save(entity);
        return true;
    }
}
```

**短信控制层：**

```java
@RestController
@RequestMapping("/api/sms")
public class SmsController {
    private final SmsService smsService;
    
    public SmsController(SmsService smsService) {
        this.smsService = smsService;
    }
    
    @PostMapping("/send")
    public ApiResponse<Map<String, String>> send(@RequestBody Map<String, String> body) {
        String phone = body.get("phone");
        String code = smsService.sendCode(phone);
        // 调试模式返回 code 方便测试。生产环境上线前删掉 code 返回
        return ApiResponse.ok(Map.of(
            "message", "验证码已发送",
            "debugCode", code
        ));
    }
}
```

**UserService.java — 修改 login() 以支持验证码登录：**

验证码登录逻辑已有基础的 codeLogin 分支（`"code".equalsIgnoreCase(request.loginType())`），需要注入 SmsService 并在 codeLogin 分支中验证：

```java
// 在 UserService 中注入 SmsService
private final SmsService smsService;

// login() 方法中 codeLogin 分支：
if (codeLogin) {
    if (!smsService.verifyCode(user.getPhone(), request.password())) {
        throw new IllegalArgumentException("验证码错误或已过期");
    }
}
```

### 前端改动

**api_client.dart — 新增验证码接口：**

```dart
// 在 FitLoopApi 抽象类中新增
Future<Map<String, String>> sendSmsCode({required String phone});

// 在 HttpFitLoopApi 实现中
@override
Future<Map<String, String>> sendSmsCode({required String phone}) async {
  final body = await _post('/api/sms/send', {'phone': phone});
  final data = body['data'] as Map<String, dynamic>;
  return {
    'message': data['message'] as String,
    if (data.containsKey('debugCode')) 'debugCode': data['debugCode'] as String,
  };
}
```

**修改 login 方法支持验证码登录：**

当前 `login()` 方法用 `loginType: 'password'`。通过登录页面的 Tab 切换，验证码登录时传 `loginType: 'code'`：

```dart
@override
Future<UserSession> login({
  required String account,
  required String password,
  String loginType = 'password',  // 新增可选参数
}) async {
  final body = await _post('/api/auth/login', {
    'account': account,
    'password': password,
    'loginType': loginType,
  });
  // ... 其余不变
}
```

**main.dart — 登录/注册页面新增验证码 UI：**

- 登录页面增加 Tab：「密码登录」|「验证码登录」
- 验证码登录：输入手机号 → 获取验证码（60s 倒计时）→ 输入验证码 → 登录
- 注册页面增加验证码输入框

---

## 10. 测试规范

### 10.1 通用原则

- 每个新功能/修改必须有对应的测试
- 所有测试必须能通过 `flutter analyze && flutter test`（前端）和 `mvn test`（后端）
- Controller 层测试只测路由和参数校验，不测业务逻辑

### 10.2 后端测试

**新增 SportControllerTest.java：**

```java
@WebMvcTest(SportController.class)
@Import(SportService.class)
class SportControllerTest {
    // 测试各个端点正常返回
    // 测试参数校验失败
    // 覆盖多种 sportType 和 checkinMode
}
```

**扩展 SportServiceTest — 新增测试方法：**

```java
@Test
void startWithCyclingType() { ... }

@Test
void finishWithNoTrackPoints_manualMode() { ... }

@Test
void finishWithNoTrackPoints_sensorMode() { ... }

@Test
void calorieEstimateForAllSportTypes() { ... }
```

**新增 SmsServiceTest：**

```java
@DataJpaTest
@Import(SmsService.class)
class SmsServiceTest {
    @Test
    void sendCodeGenerates6Digits() { ... }
    
    @Test
    void verifyValidCode() { ... }
    
    @Test
    void verifyExpiredCode() { ... }
    
    @Test
    void verifyUsedCode() { ... }
}
```

### 10.3 前端测试

**扩展 widget_test.dart 或新增测试文件：**

```dart
testWidgets('sport type selector shows options', (tester) async { ... });
testWidgets('manual checkin form validates input', (tester) async { ... });
testWidgets('photo checkin mode triggers image picker', (tester) async { ... });
```

### 10.4 运行测试命令

```bash
# 前端
cd mobile && flutter analyze && flutter test

# 后端
cd backend && mvn test
```

---

## 11. Git 流程

### 提交规范

```
格式: feat(scope): 简短描述
scope: mobile/backend

示例:
feat(mobile): add checkin mode selector UI
feat(backend): add SMS verification code system
```

### 提交前检查清单

- [ ] `flutter analyze` — 0 issues
- [ ] `flutter test` — 全部通过
- [ ] `mvn test` — 全部通过
- [ ] 代码未违反「架构红线」
- [ ] 没有硬编码的 API 地址 / 密钥 / Token
- [ ] 新增依赖已添加到 pubspec.yaml 或 pom.xml

### 提交顺序建议（按依赖关系）

```
1. feat(backend): add SMS verification code entity and service
2. feat(backend): add sport photo upload endpoint
3. feat(backend): handle sensor/manual checkin mode in SportService
4. feat(mobile): add sensors_plus dependency and pedometer service
5. feat(mobile): add sport type selector and checkin mode picker
6. feat(mobile): add sensor checkin with step counter
7. feat(mobile): add photo checkin flow
8. feat(mobile): add manual checkin form
9. feat(mobile): add SMS verification code UI for login/register
10. test: add tests for phase 1 features
```

---

## 12. 常见陷阱与排查

### 12.1 Flutter 陷阱

| 陷阱 | 现象 | 解决 |
|------|------|------|
| `sensors_plus` 在 iOS 上 require 额外权限 | iOS 编译失败 | 检查 Info.plist 插件文档 |
| `image_picker` 在模拟器无摄像头 | 拍照崩溃 | 用 `ImageSource.gallery` 回退 |
| 手动打卡表单 TextField 被键盘遮挡 | 输入不方便 | 用 `SingleChildScrollView` 包裹 |
| 热重载后 SharedPreferences 数据丢失 | 预期内 | 生产环境正常 |

### 12.2 后端陷阱

| 陷阱 | 现象 | 解决 |
|------|------|------|
| 验证码按时间找最新的 `ORDER BY created_at DESC` | 查到错误的码 | 确认 `findTopByPhoneAndCodeAndUsedFalseOrderByCreatedAtDesc` JPA 方法名正确 |
| 文件上传路径不存在 | 500 错误 | 启动时确保 `uploads/photos/` 目录存在 |
| Multipart 文件大小超限 | 400 错误 | `spring.servlet.multipart.max-file-size=10MB` |
| `@WebMvcTest` 不加载 Security | 测试跳过鉴权 | 正常，Controller 测试只测路由 |

### 12.3 关键错误处理

```dart
// 所有网络调用必须 try-catch
try {
  await widget.api.startSport(...);
} on ApiException catch (e) {
  setState(() => _status = e.message);
} catch (e) {
  setState(() => _status = '网络异常，请稍后重试');
  // 如果是已经开始打卡的情况，走离线同步
  await SyncQueue.enqueueFinish(record);
}
```

---

## 附录 A：当前项目结构快照

```
/tmp/FitLoop
├── mobile/
│   ├── lib/
│   │   ├── main.dart              # 2400行 — 所有UI页面
│   │   ├── api_client.dart        # 1070行 — API调用
│   │   ├── splash_screen.dart     # 87行 — 启动页
│   │   ├── onboarding_screen.dart # 166行 — 引导页
│   │   ├── stats_charts.dart      # 319行 — 图表
│   │   ├── sync_queue.dart        # 173行 — 离线队列
│   │   ├── local_cache.dart       # 135行 — 本地缓存
│   │   ├── reminder_scheduler.dart # 105行 — 通知调度
│   │   └── connectivity_service.dart # 70行 — 网络探测
│   ├── test/
│   │   └── widget_test.dart       # 623行 — 前端测试
│   └── pubspec.yaml
├── backend/
│   ├── src/main/java/com/fitloop/
│   │   ├── sport/   (SportController, Service, Record, CalorieCalculator)
│   │   ├── user/    (UserController, Service, Info, AvatarController)
│   │   ├── social/  (SocialController, Service, Friend)
│   │   ├── stats/   (StatsController, Service, HealthData)
│   │   ├── appeal/  (AppealController, Service)
│   │   ├── target/  (TargetController, Service)
│   │   ├── reminder/ (ReminderController, Service)
│   │   ├── security/ (Jwt, SecurityConfig)
│   │   └── common/  (ApiResponse, GlobalExceptionHandler)
│   └── src/test/java/com/fitloop/
│       └── (9 个测试文件，47 个 @Test)
├── deploy/
│   ├── docker-compose.yml
│   ├── nginx.conf
│   └── .env.example
└── .github/workflows/ci.yml
```

## 附录 B：阶段 1 完成检查清单

- [ ] 5 种运动类型可选
- [ ] 4 种打卡方式（GPS/传感器/拍照/手动）可用
- [ ] 打卡记录正确存储 sportType 和 checkinMode
- [ ] 手机验证码发送和验证功能
- [ ] 验证码登录/注册可用
- [ ] 所有前端页面无 Analyze 错误
- [ ] 所有新增后端测试通过
- [ ] 所有前端测试通过
- [ ] 所有已有回归测试通过
- [ ] git push 到 origin/main

---

*文档版本：v1.0 — 撰写于 2026-05-28*

--------------------------10eafc020df97be7--
