package com.fitloop.user;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

@Service
public class VerificationCodeService {
    public static final String CHANNEL_PHONE = "phone";
    public static final String CHANNEL_EMAIL = "email";
    public static final String PURPOSE_REGISTER = "register";
    public static final String PURPOSE_LOGIN = "login";
    public static final String PURPOSE_RESET_PASSWORD = "reset_password";

    private static final Set<String> CHANNELS = Set.of(CHANNEL_PHONE, CHANNEL_EMAIL);
    private static final Set<String> PURPOSES = Set.of(PURPOSE_REGISTER, PURPOSE_LOGIN, PURPOSE_RESET_PASSWORD);
    private static final int MAX_ATTEMPTS = 5;

    private final VerificationCodeRepository codes;
    private final Map<String, VerificationCodeSender> senders;
    private final Environment environment;
    private final SecureRandom random;
    private final Clock clock;
    private final String hashSecret;
    private final boolean debugReturnEnabled;

    @Autowired
    public VerificationCodeService(VerificationCodeRepository codes,
                                   List<VerificationCodeSender> senders,
                                   Environment environment,
                                   @Value("${fitloop.verification.hash-secret}") String hashSecret,
                                   @Value("${fitloop.verification.debug-return:false}") boolean debugReturnEnabled) {
        this(codes, senders, environment, new SecureRandom(), Clock.systemUTC(),
                hashSecret, debugReturnEnabled);
    }

    VerificationCodeService(VerificationCodeRepository codes,
                            List<VerificationCodeSender> senders,
                            Environment environment,
                            SecureRandom random,
                            Clock clock,
                            String hashSecret,
                            boolean debugReturnEnabled) {
        this.codes = codes;
        this.senders = senders.stream()
                .collect(Collectors.toMap(VerificationCodeSender::channel, Function.identity()));
        this.environment = environment;
        this.random = random;
        this.clock = clock;
        this.hashSecret = hashSecret;
        this.debugReturnEnabled = debugReturnEnabled;
    }

    @Transactional
    public VerificationCodeSendResult sendCode(String channel, String target, String purpose, String requestIp) {
        String normalizedChannel = normalizeChannel(channel);
        String normalizedPurpose = normalizePurpose(purpose);
        String normalizedTarget = normalizeTarget(normalizedChannel, target);
        String requestIpHash = StringUtils.hasText(requestIp) ? hashIp(requestIp) : null;
        enforceRateLimit(normalizedChannel, normalizedTarget, normalizedPurpose, requestIpHash);

        String code = String.format("%06d", random.nextInt(1_000_000));
        codes.findByTargetAndChannelAndPurposeAndUsedFalse(normalizedTarget, normalizedChannel, normalizedPurpose)
                .forEach(existing -> existing.setUsed(true));

        VerificationCode entity = new VerificationCode();
        entity.setTarget(normalizedTarget);
        entity.setChannel(normalizedChannel);
        entity.setPurpose(normalizedPurpose);
        entity.setCodeHash(hashCode(normalizedTarget, normalizedChannel, normalizedPurpose, code));
        entity.setExpiresAt(Instant.now(clock).plus(5, ChronoUnit.MINUTES));
        entity.setRequestIpHash(requestIpHash);
        codes.save(entity);

        senderFor(normalizedChannel).send(normalizedTarget, code, normalizedPurpose);

        String message;
        if (shouldReturnDebugCode()) {
            message = CHANNEL_PHONE.equals(normalizedChannel)
                    ? "验证码已生成（内测模式）"
                    : "验证码已生成（调试模式）";
        } else if (CHANNEL_PHONE.equals(normalizedChannel)) {
            throw new IllegalArgumentException("手机短信通道暂未开放，请使用邮箱验证码");
        } else {
            message = "验证码已发送到邮箱，请检查收件箱";
        }
        return new VerificationCodeSendResult(message, shouldReturnDebugCode() ? code : null);
    }

    @Transactional
    public boolean verifyCode(String channel, String target, String purpose, String code) {
        if (!StringUtils.hasText(code)) {
            return false;
        }
        String normalizedChannel = normalizeChannel(channel);
        String normalizedPurpose = normalizePurpose(purpose);
        String normalizedTarget = normalizeTarget(normalizedChannel, target);

        return codes.findTopByTargetAndChannelAndPurposeAndUsedFalseOrderByCreatedAtDesc(
                        normalizedTarget, normalizedChannel, normalizedPurpose)
                .map(entity -> verifyExisting(entity, normalizedTarget, normalizedChannel, normalizedPurpose, code))
                .orElse(false);
    }

    public String inferChannel(String account) {
        if (!StringUtils.hasText(account)) {
            throw new IllegalArgumentException("账号不能为空");
        }
        return account.contains("@") ? CHANNEL_EMAIL : CHANNEL_PHONE;
    }

    private boolean verifyExisting(VerificationCode entity, String target, String channel, String purpose, String code) {
        Instant now = Instant.now(clock);
        if (now.isAfter(entity.getExpiresAt())) {
            entity.setUsed(true);
            return false;
        }
        if (entity.getAttemptCount() >= MAX_ATTEMPTS) {
            entity.setUsed(true);
            return false;
        }

        entity.setAttemptCount(entity.getAttemptCount() + 1);
        String expected = hashCode(target, channel, purpose, code);
        boolean matches = MessageDigest.isEqual(
                expected.getBytes(StandardCharsets.UTF_8),
                entity.getCodeHash().getBytes(StandardCharsets.UTF_8));
        if (matches) {
            entity.setUsed(true);
            return true;
        }
        if (entity.getAttemptCount() >= MAX_ATTEMPTS) {
            entity.setUsed(true);
        }
        return false;
    }

    private void enforceRateLimit(String channel, String target, String purpose, String requestIpHash) {
        Instant now = Instant.now(clock);
        codes.findTopByTargetAndChannelAndPurposeAndUsedFalseOrderByCreatedAtDesc(target, channel, purpose)
                .filter(existing -> existing.getCreatedAt() != null)
                .filter(existing -> existing.getCreatedAt().isAfter(now.minus(60, ChronoUnit.SECONDS)))
                .ifPresent(existing -> {
                    throw new IllegalArgumentException("验证码发送过于频繁，请稍后再试");
                });
        if (codes.countByTargetAndChannelAndPurposeAndCreatedAtAfter(
                target, channel, purpose, now.minus(1, ChronoUnit.HOURS)) >= 5) {
            throw new IllegalArgumentException("验证码发送次数过多，请稍后再试");
        }
        if (codes.countByTargetAndChannelAndPurposeAndCreatedAtAfter(
                target, channel, purpose, now.minus(1, ChronoUnit.DAYS)) >= 20) {
            throw new IllegalArgumentException("今日验证码发送次数已达上限");
        }
        if (StringUtils.hasText(requestIpHash)
                && codes.countByRequestIpHashAndCreatedAtAfter(requestIpHash, now.minus(1, ChronoUnit.HOURS)) >= 60) {
            throw new IllegalArgumentException("验证码请求次数过多，请稍后再试");
        }
    }

    private VerificationCodeSender senderFor(String channel) {
        VerificationCodeSender sender = senders.get(channel);
        if (sender == null) {
            throw new IllegalArgumentException("不支持的验证码渠道");
        }
        return sender;
    }

    private String normalizeChannel(String channel) {
        String value = normalizeToken(channel);
        if (!CHANNELS.contains(value)) {
            throw new IllegalArgumentException("验证码渠道不正确");
        }
        return value;
    }

    private String normalizePurpose(String purpose) {
        String value = normalizeToken(purpose);
        if (!PURPOSES.contains(value)) {
            throw new IllegalArgumentException("验证码用途不正确");
        }
        return value;
    }

    private String normalizeTarget(String channel, String target) {
        if (!StringUtils.hasText(target)) {
            throw new IllegalArgumentException("验证码接收账号不能为空");
        }
        String value = target.trim().toLowerCase(Locale.ROOT);
        if (CHANNEL_PHONE.equals(channel) && !value.matches("^1\\d{10}$")) {
            throw new IllegalArgumentException("手机号格式不正确");
        }
        if (CHANNEL_EMAIL.equals(channel) && !value.matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")) {
            throw new IllegalArgumentException("邮箱格式不正确");
        }
        return value;
    }

    private String normalizeToken(String value) {
        return StringUtils.hasText(value) ? value.trim().toLowerCase(Locale.ROOT) : "";
    }

    private boolean shouldReturnDebugCode() {
        if (!debugReturnEnabled) {
            return false;
        }
        for (String profile : environment.getActiveProfiles()) {
            if ("local".equals(profile) || "test".equals(profile) || "demo".equals(profile) || "staging".equals(profile)) {
                return true;
            }
        }
        return false;
    }

    private String hashCode(String target, String channel, String purpose, String code) {
        return hmac("%s:%s:%s:%s".formatted(channel, purpose, target, code));
    }

    private String hashIp(String requestIp) {
        return hmac("ip:%s".formatted(requestIp));
    }

    private String hmac(String value) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(hashSecret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return Base64.getUrlEncoder().withoutPadding()
                    .encodeToString(mac.doFinal(value.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception ex) {
            throw new IllegalStateException("验证码签名失败", ex);
        }
    }
}
