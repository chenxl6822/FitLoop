package com.fitloop;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fitloop.security.JwtService;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.http.MediaType;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc(addFilters = false)
@ActiveProfiles("test")
@TestPropertySource(properties = "fitloop.verification.debug-return=true")
class FitLoopApiIntegrationTest {
    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private JwtService jwtService;

    @MockitoBean
    private JavaMailSender mailSender;

    @Test
    void registersLogsInAndFinishesSportSession() throws Exception {
        String phone = "13800000000";
        String smsBody = mockMvc.perform(post("/api/sms/send")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("phone", phone))))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();
        String code = objectMapper.readTree(smsBody).at("/data/debugCode").asText();
        assertThat(code).isNotBlank();

        mockMvc.perform(post("/api/user/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "phone", phone,
                                "password", "pass1234",
                                "nickname", "测试用户",
                                "code", code))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.userId").exists());

        String loginBody = mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("account", phone, "password", "pass1234", "loginType", "password"))))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();
        String token = objectMapper.readTree(loginBody).at("/data/token").asText();
        assertThat(token).isNotBlank();
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(jwtService.verify(token), null, List.of()));

        String startBody = mockMvc.perform(post("/api/sport/session/start")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("sportType", "running", "checkinMode", "gps"))))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();
        JsonNode start = objectMapper.readTree(startBody);
        String sessionId = start.at("/data/sessionId").asText();

        mockMvc.perform(post("/api/sport/session/track")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "sessionId", sessionId,
                                "lat", 31.2304,
                                "lng", 121.4737,
                                "accuracy", 20,
                                "timestamp", Instant.now().toString()))))
                .andExpect(status().isOk());

        mockMvc.perform(post("/api/sport/session/finish")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("sessionId", sessionId, "durationSeconds", 1800, "weightKg", 60))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.recordId").exists())
                .andExpect(jsonPath("$.data.calorie").value(240.0));

        mockMvc.perform(get("/api/stat/sport")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.checkinCount").value(1));
    }

    @Test
    void sendsEmailVerificationCode() throws Exception {
        mockMvc.perform(post("/api/verification/send")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "channel", "email",
                                "target", "fitloop-user@example.com",
                                "purpose", "register"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.message").value("验证码已生成（调试模式）"))
                .andExpect(jsonPath("$.data.debugCode").isNotEmpty());

        verify(mailSender).send(any(SimpleMailMessage.class));
    }

    private String json(Object value) throws Exception {
        return objectMapper.writeValueAsString(value);
    }
}
