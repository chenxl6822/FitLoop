package com.fitloop.agent;

import com.fitloop.agent.AgentDtos.ToolContext;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.ObjectMapper;

@Service
public class AgentDelegationTokenService {
    private static final Base64.Encoder ENCODER = Base64.getUrlEncoder().withoutPadding();
    private static final Base64.Decoder DECODER = Base64.getUrlDecoder();
    private final byte[] secret;
    private final long ttlSeconds;
    private final ObjectMapper objectMapper;

    public AgentDelegationTokenService(
            @Value("${fitloop.agent.delegation-secret:${fitloop.jwt.secret}}") String secret,
            @Value("${fitloop.agent.delegation-ttl-seconds:300}") long ttlSeconds,
            ObjectMapper objectMapper) {
        if (secret == null || secret.getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new IllegalStateException("Agent delegation secret must contain at least 32 bytes");
        }
        this.secret = secret.getBytes(StandardCharsets.UTF_8);
        this.ttlSeconds = Math.min(Math.max(ttlSeconds, 30), 300);
        this.objectMapper = objectMapper;
    }

    public String issue(AgentRun run) {
        Instant now = Instant.now();
        Map<String, Object> claims = new LinkedHashMap<>();
        claims.put("iss", "fitloop-backend");
        claims.put("aud", "fitloop-agent-tools");
        claims.put("sub", "agent-service");
        claims.put("runId", run.getRunId());
        claims.put("subjectUserId", run.getSubjectUserId());
        claims.put("subjectResourceId", run.getSubjectResourceId());
        claims.put("type", run.getRunType().name());
        claims.put("scope", "agent.internal");
        claims.put("iat", now.getEpochSecond());
        claims.put("exp", now.plusSeconds(ttlSeconds).getEpochSecond());
        try {
            String unsigned = encode(objectMapper.writeValueAsBytes(Map.of("alg", "HS256", "typ", "JWT")))
                    + "." + encode(objectMapper.writeValueAsBytes(claims));
            return unsigned + "." + encode(sign(unsigned));
        } catch (Exception ex) {
            throw new IllegalStateException("Could not issue agent delegation token", ex);
        }
    }

    public ToolContext verify(String token) {
        try {
            String[] parts = token.split("\\.");
            if (parts.length != 3) throw invalid();
            String unsigned = parts[0] + "." + parts[1];
            if (!MessageDigest.isEqual(sign(unsigned), DECODER.decode(parts[2]))) throw invalid();
            Map<String, Object> claims = objectMapper.readValue(DECODER.decode(parts[1]), new TypeReference<>() { });
            if (!"fitloop-backend".equals(claims.get("iss"))
                    || !"fitloop-agent-tools".equals(claims.get("aud"))
                    || !"agent.internal".equals(claims.get("scope"))
                    || Instant.now().getEpochSecond() >= ((Number) claims.get("exp")).longValue()) {
                throw invalid();
            }
            Object resource = claims.get("subjectResourceId");
            return new ToolContext(claims.get("runId").toString(),
                    Long.valueOf(claims.get("subjectUserId").toString()),
                    resource == null ? null : Long.valueOf(resource.toString()),
                    AgentRunType.valueOf(claims.get("type").toString()));
        } catch (IllegalArgumentException ex) {
            throw ex;
        } catch (Exception ex) {
            throw invalid();
        }
    }

    public long ttlSeconds() { return ttlSeconds; }
    private String encode(byte[] value) { return ENCODER.encodeToString(value); }
    private byte[] sign(String value) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret, "HmacSHA256"));
            return mac.doFinal(value.getBytes(StandardCharsets.UTF_8));
        } catch (Exception ex) {
            throw new IllegalStateException("Could not sign agent token", ex);
        }
    }
    private IllegalArgumentException invalid() { return new IllegalArgumentException("Invalid agent delegation token"); }
}
