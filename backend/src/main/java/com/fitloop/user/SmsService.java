package com.fitloop.user;

import org.springframework.stereotype.Service;

@Service
public class SmsService {
    private final VerificationCodeService verificationCodes;

    public SmsService(VerificationCodeService verificationCodes) {
        this.verificationCodes = verificationCodes;
    }

    public String sendCode(String phone) {
        return verificationCodes
                .sendCode(VerificationCodeService.CHANNEL_PHONE, phone,
                        VerificationCodeService.PURPOSE_REGISTER, null)
                .debugCode();
    }

    public boolean verifyCode(String phone, String code) {
        return verificationCodes.verifyCode(VerificationCodeService.CHANNEL_PHONE, phone,
                VerificationCodeService.PURPOSE_REGISTER, code);
    }
}
