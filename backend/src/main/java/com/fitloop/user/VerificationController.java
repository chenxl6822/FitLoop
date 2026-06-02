package com.fitloop.user;

import com.fitloop.common.ApiResponse;
import com.fitloop.user.VerificationDtos.SendCodeRequest;
import com.fitloop.user.VerificationDtos.SendCodeResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/verification")
public class VerificationController {
    private final VerificationCodeService verificationCodes;

    public VerificationController(VerificationCodeService verificationCodes) {
        this.verificationCodes = verificationCodes;
    }

    @PostMapping("/send")
    public ApiResponse<SendCodeResponse> send(@Valid @RequestBody SendCodeRequest request,
                                              HttpServletRequest servletRequest) {
        VerificationCodeSendResult result = verificationCodes.sendCode(
                request.channel(), request.target(), request.purpose(), clientIp(servletRequest));
        return ApiResponse.ok(new SendCodeResponse(result.message(), result.debugCode()));
    }

    private String clientIp(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) {
            return forwarded.split(",")[0].trim();
        }
        return request.getRemoteAddr();
    }
}
