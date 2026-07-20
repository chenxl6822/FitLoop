package com.fitloop.user;

import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fitloop.security.JwtAuthenticationFilter;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(VerificationController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestPropertySource(properties = "fitloop.admin.key=test-admin-key")
class VerificationControllerTest {
    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private VerificationCodeService verificationCodes;

    @MockitoBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    @Test
    void sendReturnsDebugCodeWhenServiceProvidesOne() throws Exception {
        when(verificationCodes.sendCode(anyString(), anyString(), anyString(), anyString()))
                .thenReturn(new VerificationCodeSendResult("验证码已生成（调试模式）", "123456"));

        mockMvc.perform(post("/api/verification/send")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"channel":"email","target":"user@example.com","purpose":"login"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.message").value("验证码已生成（调试模式）"))
                .andExpect(jsonPath("$.data.debugCode").value("123456"));
    }

    @Test
    void sendReturnsEmailMessageWithoutDebugCode() throws Exception {
        when(verificationCodes.sendCode(anyString(), anyString(), anyString(), anyString()))
                .thenReturn(new VerificationCodeSendResult("验证码已发送到邮箱，请检查收件箱", null));

        mockMvc.perform(post("/api/verification/send")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"channel":"email","target":"user@example.com","purpose":"register"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.message").value("验证码已发送到邮箱，请检查收件箱"))
                .andExpect(jsonPath("$.data.debugCode").doesNotExist());
    }

    @Test
    void sendPhoneVerificationCodeInDebugMode() throws Exception {
        when(verificationCodes.sendCode(anyString(), anyString(), anyString(), anyString()))
                .thenReturn(new VerificationCodeSendResult("验证码已生成（内测模式）", "654321"));

        mockMvc.perform(post("/api/verification/send")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"channel":"phone","target":"13800000001","purpose":"register"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.message").value("验证码已生成（内测模式）"))
                .andExpect(jsonPath("$.data.debugCode").value("654321"));
    }
}
