package com.fitloop.security;

import static org.assertj.core.api.Assertions.assertThat;

import com.fitloop.user.UserRole;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("test")
class AdminRbacIntegrationTest {
    @LocalServerPort
    private int port;

    @Autowired
    private JwtService jwtService;

    @MockitoBean
    private StringRedisTemplate redis;

    @MockitoBean
    private JavaMailSender mailSender;

    @Test
    void adminEndpointsRequireAdminJwt() throws Exception {
        String userToken = jwtService.issue(1L, UserRole.USER);
        String adminToken = jwtService.issue(2L, UserRole.ADMIN);

        HttpResponse<String> anonymous = get(null);
        HttpResponse<String> user = get(userToken);
        HttpResponse<String> admin = get(adminToken);

        assertThat(anonymous.statusCode()).isEqualTo(403);
        assertThat(user.statusCode()).isEqualTo(403);
        assertThat(admin.statusCode()).isEqualTo(200);
        assertThat(admin.body()).contains("\"items\":[]");
    }

    private HttpResponse<String> get(String token) throws Exception {
        HttpRequest.Builder request = HttpRequest.newBuilder(
                URI.create("http://localhost:" + port + "/api/v1/admin/audit-logs")).GET();
        if (token != null) {
            request.header("Authorization", "Bearer " + token);
        }
        return HttpClient.newHttpClient().send(request.build(), HttpResponse.BodyHandlers.ofString());
    }
}
