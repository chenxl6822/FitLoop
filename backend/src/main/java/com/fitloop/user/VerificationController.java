package com.fitloop.user;

import com.fitloop.common.ApiResponse;
import com.fitloop.user.VerificationDtos.SendCodeRequest;
import com.fitloop.user.VerificationDtos.SendCodeResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api")
public class VerificationController {
    private final VerificationCodeService verificationCodes;
    private final boolean smsEnabled;

    public VerificationController(VerificationCodeService verificationCodes,
                                  @Value("${fitloop.sms.enabled:false}") boolean smsEnabled) {
        this.verificationCodes = verificationCodes;
        this.smsEnabled = smsEnabled;
    }

    @PostMapping("/verification/send")
    public ApiResponse<SendCodeResponse> send(@Valid @RequestBody SendCodeRequest request,
                                              HttpServletRequest servletRequest) {
        VerificationCodeSendResult result = verificationCodes.sendCode(
                request.channel(), request.target(), request.purpose(), clientIp(servletRequest));
        return ApiResponse.ok(new SendCodeResponse(result.message(), result.debugCode()));
    }

    @GetMapping("/config/features")
    public ApiResponse<Map<String, Boolean>> features() {
        return ApiResponse.ok(Map.of("smsEnabled", smsEnabled));
    }

    private String clientIp(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) {
            return forwarded.split(",")[0].trim();
        }
        return request.getRemoteAddr();
    }
}
