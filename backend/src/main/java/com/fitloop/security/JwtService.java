package com.fitloop.security;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Base64;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class JwtService {
    private final String secret;
    private final long ttlSeconds;

    public JwtService(
            @Value("${fitloop.jwt.secret}") String secret,
            @Value("${fitloop.jwt.ttl-seconds}") long ttlSeconds
    ) {
        this.secret = secret;
        this.ttlSeconds = ttlSeconds;
    }

    public String issue(Long userId) {
        long expiresAt = Instant.now().plusSeconds(ttlSeconds).getEpochSecond();
        String payload = userId + "." + expiresAt;
        return payload + "." + sign(payload);
    }

    public Long verify(String token) {
        String[] parts = token.split("\\.");
        if (parts.length != 3) {
            throw new IllegalArgumentException("无效登录令牌");
        }
        String payload = parts[0] + "." + parts[1];
        if (!sign(payload).equals(parts[2])) {
            throw new IllegalArgumentException("无效登录令牌");
        }
        long expiresAt = Long.parseLong(parts[1]);
        if (Instant.now().getEpochSecond() > expiresAt) {
            throw new IllegalArgumentException("登录已过期");
        }
        return Long.valueOf(parts[0]);
    }

    private String sign(String value) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return Base64.getUrlEncoder().withoutPadding()
                    .encodeToString(mac.doFinal(value.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception ex) {
            throw new IllegalStateException("签发令牌失败", ex);
        }
    }
}
