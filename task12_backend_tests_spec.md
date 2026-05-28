# 任务 12：后端集成测试补充 — Claude 执行规范

## 背景

FitLoop 后端有 8 个 Controller，其中 6 个有对应的 Service 层测试，但 **`SportController`** 和 **`AvatarController`** 缺少 controller 层集成测试。现有测试体系 47 个 @Test 覆盖了 Service 核心逻辑，但缺少端到端的 API 请求-响应验证。

## 目标

为下面两个 Controller 补充 `@WebMvcTest` 风格的集成测试：

1. **`SportController`** — `POST /session/start`、`POST /session/track`、`POST /session/finish`
2. **`AvatarController`** — `POST /api/user/avatar`（multipart 文件上传）

## 总要求

- 不要修改任何生产代码
- 不要修改已有的测试代码
- 保持现有测试风格（参考 `SocialServiceTest.java` 或 `AppealServiceTest.java`）
- `mvn test` 必须全部通过（47 + 新 = 全绿）
- 使用 `@WebMvcTest` + `@MockBean` Service + MockMvc（不要 `@SpringBootTest`——不需要启动 MySQL）

---

## 步骤 1：新建 SportControllerTest.java

**位置：** `backend/src/test/java/com/fitloop/sport/SportControllerTest.java`

### 1.1 测试类骨架

```java
package com.fitloop.sport;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fitloop.security.JwtService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.Map;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(SportController.class)
class SportControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockitoBean
    private SportService sportService;

    @MockitoBean
    private JwtService jwtService;

    // token: 固定 test user ID = 1
    private final String testToken = "Bearer test-jwt-token";
    private final int testUserId = 1;

    private String asJson(Map<String, Object> map) throws Exception {
        return objectMapper.writeValueAsString(map);
    }
}
```

### 1.2 测试前准备

在 `@BeforeEach` 或直接在测试方法中 mock `JwtService.extractUserId()`：

```java
// 在每个测试方法开始 mock JWT
when(jwtService.extractUserId("test-jwt-token")).thenReturn(testUserId);
```

因为 `AuthSupport` 会调用 `JwtService.extractUserId()` 来获取当前用户——参考 `SecurityConfig` 和 `AuthSupport` 的实现。

### 1.3 测试 1：POST /session/start — 成功

```java
@Test
void startSession_shouldReturnSessionId() throws Exception {
    when(sportService.start(anyString(), eq(testUserId)))
        .thenReturn("session-uuid-123");

    mockMvc.perform(post("/session/start")
            .header("Authorization", testToken)
            .contentType(MediaType.APPLICATION_JSON)
            .content(asJson(Map.of("sportType", "running"))))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value(0))
        .andExpect(jsonPath("$.data.sessionId").value("session-uuid-123"));
}
```

### 1.4 测试 2：POST /session/finish — 成功

```java
@Test
void finishSession_shouldReturnResult() throws Exception {
    var result = new SportService.FinishResult(1, 1800, 3500.0, 250.0);
    when(sportService.finish(eq(testUserId), eq("session-uuid-123"), anyInt(), anyDouble()))
        .thenReturn(result);

    mockMvc.perform(post("/session/finish")
            .header("Authorization", testToken)
            .contentType(MediaType.APPLICATION_JSON)
            .content(asJson(Map.of(
                "sessionId", "session-uuid-123",
                "durationSeconds", 1800,
                "weightKg", 60.0
            ))))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value(0))
        .andExpect(jsonPath("$.data.durationSeconds").value(1800));
}
```

### 1.5 测试 3：POST /session/track — 有权限检查则测试 401

如果 `SportController` 的 track 方法在 SecurityConfig 中要求认证（看 security 配置中 `/session/**` 是否被 `anyRequest().authenticated()` 覆盖）——通常是的。

```java
@Test
void track_withoutAuth_shouldReturn401() throws Exception {
    mockMvc.perform(post("/session/track")
            .contentType(MediaType.APPLICATION_JSON)
            .content("[{\"lat\": 30.5, \"lng\": 104.0, \"timestamp\": \"2026-05-27T10:00:00Z\"}]"))
        .andExpect(status().isUnauthorized());
}
```

注意：因为 `@WebMvcTest` 不加载 SecurityConfig，Security 的 filter chain 不会被应用。这个测试可以跳过 OR 改为测试请求体格式校验（但更好的做法是确认当前 SecurityConfig 的行为）。

**建议：** 如果 `@WebMvcTest` 条件下 Security filter 不生效，就不要测 401，只测 happy path。

### 1.6 测试 4：start — 缺少 sportType 参数

```java
@Test
void startSession_withoutSportType_shouldReturn400() throws Exception {
    mockMvc.perform(post("/session/start")
            .header("Authorization", testToken)
            .contentType(MediaType.APPLICATION_JSON)
            .content(asJson(Map.of())))
        .andExpect(status().isBadRequest());
}
```

**注意：** 如果 SportController 不做参数校验（即请求体不是 `@Valid` 且没有 `@NotNull` 约束），就不会返回 400——如果是这种状况，就别写测试 400，不写假的测试。

---

## 步骤 2：新建 AvatarControllerTest.java

**位置：** `backend/src/test/java/com/fitloop/user/AvatarControllerTest.java`

### 2.1 背景

`AvatarController` 使用 `MultipartFile` 上传，需使用 `MockMultipartFile`。参考：

```java
package com.fitloop.user;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.mock.web.MockMultipartFile;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(AvatarController.class)
class AvatarControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private UserService userService;

    @MockitoBean
    private JwtService jwtService;

    private final String testToken = "Bearer test-jwt-token";
    private final int testUserId = 1;
}
```

### 2.2 测试 1：上传成功

```java
@Test
void uploadAvatar_shouldReturnUrl() throws Exception {
    when(jwtService.extractUserId("test-jwt-token")).thenReturn(testUserId);
    when(userService.updateAvatar(eq(testUserId), any()))
        .thenReturn("/uploads/avatars/1_new.jpg");

    var file = new MockMultipartFile(
        "file",
        "test.jpg",
        "image/jpeg",
        "fake-image-content".getBytes()
    );

    mockMvc.perform(multipart("/api/user/avatar")
            .file(file)
            .header("Authorization", testToken))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value(0))
        .andExpect(jsonPath("$.data").value("/uploads/avatars/1_new.jpg"));
}
```

### 2.3 测试 2：上传非图片文件 — 校验失败

Sprint Boot 的 `MultipartFile` 不做 mime 类型校验。如果 `AvatarController` 没有手动检查 content type 或文件后缀，这个测试会失败。

**建议：** 如果 `AvatarController` 没有文件类型校验，这个测试不要写。写出来会绿不了。

```java
// 只有当 Controller 有文件校验逻辑时才写
@Test
void uploadAvatar_withNonImage_shouldReturnError() throws Exception {
    // 先看看 Controller 实现里有没有 check file type，没有就不写
}
```

### 2.4 测试 3：无 token — 401

同 SportController 的情况，`@WebMvcTest` 不带 Security filter。可以跳过。

---

## 接受/拒绝策略

| 情况 | 处理 |
|------|------|
| `@WebMvcTest` 下 Security 没加载 | 不测 401，只测 happy path |
| Controller 没有参数校验 | 不测 400，只测单个 happy path |
| 文件大小限制在 Controller 层不生效（`MultipartProperties` 在 `@WebMvcTest` 不加载） | 不测大文件 |
| 上述提到的任何测试写出来会假绿/假红 | **不要写** |

**规则：只写一定会绿的测试。不写凑数的测试。**

---

## 验证

```bash
cd backend
mvn test
# 确认 47 + 新测试 = 全部通过
# 总 @Test 数应在 47 ~ 54 之间
```

---

## 范围边界（不做的事）

- ❌ 不修改任何生产代码（Controller / Service / Repository / 配置）
- ❌ 不修改现有测试文件
- ❌ 不使用 `@SpringBootTest`（太慢，需要 MySQL）
- ❌ 不使用 `@AutoConfigureMockMvc`（应该用 `@WebMvcTest`）
- ❌ 不写涉及 Security filter chain 的 401/403 测试（`@WebMvcTest` 不加载它）
- ❌ 不写涉及 RequestBody `@Valid` 校验的测试（除非确认生效）
- ❌ 不测试文件大小限制（`spring.servlet.multipart.max-file-size` 在 `@WebMvcTest` 中可能不生效）

## 最终验收

```bash
cd backend
mvn test 2>&1 | tail -10
# "BUILD SUCCESS" + 无 failures

# 确认新测试文件存在
ls -la src/test/java/com/fitloop/sport/SportControllerTest.java
ls -la src/test/java/com/fitloop/user/AvatarControllerTest.java
```
