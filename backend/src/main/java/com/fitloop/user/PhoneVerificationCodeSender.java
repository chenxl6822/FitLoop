package com.fitloop.user;

import org.springframework.stereotype.Component;

@Component
public class PhoneVerificationCodeSender implements VerificationCodeSender {
    @Override
    public String channel() {
        return VerificationCodeService.CHANNEL_PHONE;
    }

    @Override
    public void send(String target, String code, String purpose) {
        // 手机短信暂未接入真实服务商；验证码由调试响应在本地/测试环境展示。
    }
}
