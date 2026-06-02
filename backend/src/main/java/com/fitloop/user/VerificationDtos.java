package com.fitloop.user;

import jakarta.validation.constraints.NotBlank;

public final class VerificationDtos {
    private VerificationDtos() {
    }

    public record SendCodeRequest(@NotBlank String channel, @NotBlank String target, @NotBlank String purpose) {
    }

    public record SendCodeResponse(String message, String debugCode) {
    }
}
