package com.fitloop.user;

import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fitloop.security.JwtAuthenticationFilter;
import com.fitloop.user.UserDtos.UserProfile;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;

@WebMvcTest(UserController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestPropertySource(properties = "fitloop.admin.key=test-admin-key")
class UserControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private UserService userService;

    @MockBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    @BeforeEach
    void setUp() {
        SecurityContextHolder.getContext()
                .setAuthentication(new UsernamePasswordAuthenticationToken(1L, null, List.of()));
    }

    @Test
    void getProfileReturnsUserProfile() throws Exception {
        var profile = new UserProfile(1L, "138****1234", null, "小明",
                "/uploads/avatars/test.jpg", "男", "2023级", "计算机学院", 100, 3);
        when(userService.getProfile(anyLong())).thenReturn(profile);

        mockMvc.perform(get("/api/user/profile"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data.userId").value(1))
                .andExpect(jsonPath("$.data.nickname").value("小明"))
                .andExpect(jsonPath("$.data.avatarUrl").value("/uploads/avatars/test.jpg"))
                .andExpect(jsonPath("$.data.gender").value("男"))
                .andExpect(jsonPath("$.data.grade").value("2023级"))
                .andExpect(jsonPath("$.data.college").value("计算机学院"))
                .andExpect(jsonPath("$.data.points").value(100))
                .andExpect(jsonPath("$.data.level").value(3));
    }

    @Test
    void getProfileThrowsWhenUserNotFound() throws Exception {
        when(userService.getProfile(anyLong()))
                .thenThrow(new IllegalArgumentException("用户不存在"));

        mockMvc.perform(get("/api/user/profile"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void resetPasswordReturnsOk() throws Exception {
        doNothing().when(userService).resetPassword(any(UserDtos.PasswordResetRequest.class));

        mockMvc.perform(post("/api/auth/password/reset")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"account":"13800000001","code":"123456","newPassword":"newpass"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0));
    }
}
