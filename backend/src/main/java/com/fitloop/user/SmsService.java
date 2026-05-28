package com.fitloop.user;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.concurrent.ThreadLocalRandom;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class SmsService {
    private final SmsCodeRepository smsCodes;

    public SmsService(SmsCodeRepository smsCodes) {
        this.smsCodes = smsCodes;
    }

    @Transactional
    public String sendCode(String phone) {
        if (!phone.matches("^1\\d{10}$")) {
            throw new IllegalArgumentException("手机号格式不正确");
        }
        String code = String.format("%06d", ThreadLocalRandom.current().nextInt(0, 1000000));
        SmsCode entity = new SmsCode();
        entity.setPhone(phone);
        entity.setCode(code);
        entity.setExpiresAt(Instant.now().plus(5, ChronoUnit.MINUTES));
        entity.setUsed(false);
        smsCodes.save(entity);
        return code;
    }

    public boolean verifyCode(String phone, String code) {
        return smsCodes.findTopByPhoneAndCodeAndUsedFalseOrderByCreatedAtDesc(phone, code)
                .filter(entity -> !Instant.now().isAfter(entity.getExpiresAt()))
                .map(entity -> {
                    entity.setUsed(true);
                    smsCodes.save(entity);
                    return true;
                })
                .orElse(false);
    }
}
