package com.fitloop.security;

import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.ObjectMapper;
import com.fitloop.user.UserRole;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class JwtService {
    private static final Base64.Encoder ENCODER = Base64.getUrlEncoder().withoutPadding();
    private static final Base64.Decoder DECODER = Base64.getUrlDecoder();
    private final byte[] secret;
    private final long ttlSeconds;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public JwtService(@Value("${fitloop.jwt.secret}") String secret,
                      @Value("${fitloop.jwt.ttl-seconds}") long ttlSeconds) {
        if (secret == null || secret.getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new IllegalStateException("fitloop.jwt.secret must contain at least 32 bytes");
        }
        this.secret = secret.getBytes(StandardCharsets.UTF_8);
        this.ttlSeconds = ttlSeconds;
    }

    public String issue(Long userId) {
        return issue(userId, UserRole.USER);
    }

    public String issue(Long userId, UserRole role) {
        Instant now = Instant.now();
        Map<String, Object> header = Map.of("alg", "HS256", "typ", "JWT");
        Map<String, Object> claims = new LinkedHashMap<>();
        claims.put("iss", "fitloop-backend");
        claims.put("sub", userId.toString());
        claims.put("role", role.name());
        claims.put("iat", now.getEpochSecond());
        claims.put("exp", now.plusSeconds(ttlSeconds).getEpochSecond());
        claims.put("jti", UUID.randomUUID().toString());
        try {
            String unsigned = encode(objectMapper.writeValueAsBytes(header)) + "."
                    + encode(objectMapper.writeValueAsBytes(claims));
            return unsigned + "." + encode(sign(unsigned));
        } catch (Exception ex) {
            throw new IllegalStateException("Failed to issue access token", ex);
        }
    }

    public Long verify(String token) {
        return verifyClaims(token).userId();
    }

    public VerifiedToken verifyClaims(String token) {
        try {
            String[] parts = token.split("\\.");
            if (parts.length != 3) {
                throw invalidToken();
            }
            String unsigned = parts[0] + "." + parts[1];
            if (!MessageDigest.isEqual(sign(unsigned), DECODER.decode(parts[2]))) {
                throw invalidToken();
            }
            Map<String, Object> header = read(parts[0]);
            Map<String, Object> claims = read(parts[1]);
            if (!"HS256".equals(header.get("alg")) || !"fitloop-backend".equals(claims.get("iss"))) {
                throw invalidToken();
            }
            long expiresAt = ((Number) claims.get("exp")).longValue();
            if (Instant.now().getEpochSecond() >= expiresAt) {
                throw new IllegalArgumentException("登录已过期");
            }
            return new VerifiedToken(Long.valueOf(claims.get("sub").toString()),
                    UserRole.valueOf(claims.get("role").toString()), claims.get("jti").toString(),
                    Instant.ofEpochSecond(expiresAt));
        } catch (IllegalArgumentException ex) {
            throw ex;
        } catch (Exception ex) {
            throw invalidToken();
        }
    }

    public long ttlSeconds() {
        return ttlSeconds;
    }

    private Map<String, Object> read(String value) throws Exception {
        return objectMapper.readValue(DECODER.decode(value), new TypeReference<>() { });
    }

    private String encode(byte[] value) {
        return ENCODER.encodeToString(value);
    }

    private byte[] sign(String value) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret, "HmacSHA256"));
            return mac.doFinal(value.getBytes(StandardCharsets.UTF_8));
        } catch (Exception ex) {
            throw new IllegalStateException("Failed to sign access token", ex);
        }
    }

    private IllegalArgumentException invalidToken() {
        return new IllegalArgumentException("无效登录令牌");
    }

    public record VerifiedToken(Long userId, UserRole role, String jti, Instant expiresAt) { }
}
