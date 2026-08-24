package com.fitloop.user;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fitloop.security.JwtAuthenticationFilter;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(VerificationController.class)
@AutoConfigureMockMvc(addFilters = false)
class VerificationClientIpSecurityTest {

    @Autowired
    MockMvc mockMvc;

    @MockitoBean
    VerificationCodeService verificationCodes;

    @MockitoBean
    JwtAuthenticationFilter jwtAuthenticationFilter;

    @Test
    void attackerSuppliedForwardedPrefixMustNotChooseTheRateLimitIdentity() throws Exception {
        when(verificationCodes.sendCode(
                eq("email"), eq("synthetic@example.invalid"), eq("login"), anyString()))
                .thenReturn(new VerificationCodeSendResult("synthetic", null));

        mockMvc.perform(post("/api/verification/send")
                        .with(request -> {
                            request.setRemoteAddr("127.0.0.1");
                            return request;
                        })
                        .header("X-Forwarded-For", "198.51.100.77, 203.0.113.10")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"channel":"email","target":"synthetic@example.invalid","purpose":"login"}
                                """))
                .andExpect(status().isOk());

        verify(verificationCodes).sendCode(
                "email", "synthetic@example.invalid", "login", "203.0.113.10");
    }

    @Test
    void directPeerMustIgnoreForgedForwardedHeader() throws Exception {
        when(verificationCodes.sendCode(
                eq("email"), eq("synthetic@example.invalid"), eq("login"), anyString()))
                .thenReturn(new VerificationCodeSendResult("synthetic", null));

        mockMvc.perform(post("/api/verification/send")
                        .with(request -> {
                            request.setRemoteAddr("198.51.100.50");
                            return request;
                        })
                        .header("X-Forwarded-For", "203.0.113.9, 198.51.100.77")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"channel":"email","target":"synthetic@example.invalid","purpose":"login"}
                                """))
                .andExpect(status().isOk());

        verify(verificationCodes).sendCode(
                "email", "synthetic@example.invalid", "login", "198.51.100.50");
    }

    @Test
    void privateProxyPeerUsesRightmostForwardedHop() throws Exception {
        when(verificationCodes.sendCode(
                eq("email"), eq("synthetic@example.invalid"), eq("login"), anyString()))
                .thenReturn(new VerificationCodeSendResult("synthetic", null));

        mockMvc.perform(post("/api/verification/send")
                        .with(request -> {
                            request.setRemoteAddr("172.18.0.5");
                            return request;
                        })
                        .header("X-Forwarded-For", "198.51.100.77, 203.0.113.20")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"channel":"email","target":"synthetic@example.invalid","purpose":"login"}
                                """))
                .andExpect(status().isOk());

        verify(verificationCodes).sendCode(
                "email", "synthetic@example.invalid", "login", "203.0.113.20");
    }
}
