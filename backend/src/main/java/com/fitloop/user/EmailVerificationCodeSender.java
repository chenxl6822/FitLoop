package com.fitloop.user;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

@Component
public class EmailVerificationCodeSender implements VerificationCodeSender {
    private final JavaMailSender mailSender;
    private final String username;
    private final String from;

    public EmailVerificationCodeSender(JavaMailSender mailSender,
                                       @Value("${spring.mail.username:}") String username,
                                       @Value("${fitloop.mail.from:}") String from) {
        this.mailSender = mailSender;
        this.username = username;
        this.from = StringUtils.hasText(from) ? from : username;
    }

    @Override
    public String channel() {
        return VerificationCodeService.CHANNEL_EMAIL;
    }

    @Override
    public void send(String target, String code, String purpose) {
        if (!StringUtils.hasText(username) || !StringUtils.hasText(from)) {
            throw new IllegalStateException("邮箱服务未配置");
        }
        SimpleMailMessage message = new SimpleMailMessage();
        message.setFrom(from);
        message.setTo(target);
        message.setSubject(subjectFor(purpose));
        message.setText("""
                您的 FitLoop 验证码是：%s

                验证码 5 分钟内有效，请勿转发给他人。
                如果不是您本人操作，请忽略这封邮件。
                """.formatted(code));
        mailSender.send(message);
    }

    private String subjectFor(String purpose) {
        return switch (purpose) {
            case VerificationCodeService.PURPOSE_LOGIN -> "FitLoop 登录验证码";
            case VerificationCodeService.PURPOSE_RESET_PASSWORD -> "FitLoop 重置密码验证码";
            default -> "FitLoop 注册验证码";
        };
    }
}
