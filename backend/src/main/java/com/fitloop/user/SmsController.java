package com.fitloop.user;

import com.fitloop.common.ApiResponse;
import java.util.Map;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/sms")
public class SmsController {
    private final VerificationCodeService verificationCodes;

    public SmsController(VerificationCodeService verificationCodes) {
        this.verificationCodes = verificationCodes;
    }

    @PostMapping("/send")
    public ApiResponse<Map<String, String>> send(@RequestBody Map<String, String> body) {
        String phone = body.get("phone");
        if (phone == null || phone.isBlank()) {
            throw new IllegalArgumentException("手机号不能为空");
        }
        String purpose = body.getOrDefault("purpose", VerificationCodeService.PURPOSE_REGISTER);
        VerificationCodeSendResult result = verificationCodes.sendCode(
                VerificationCodeService.CHANNEL_PHONE, phone, purpose, null);
        if (result.debugCode() == null) {
            return ApiResponse.ok(Map.of("message", result.message()));
        }
        return ApiResponse.ok(Map.of("message", result.message(), "debugCode", result.debugCode()));
    }
}
