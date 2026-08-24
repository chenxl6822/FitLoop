package com.fitloop.user;

import static org.assertj.core.api.Assertions.assertThat;

import com.fitloop.user.UserDtos.PasswordResetRequest;
import com.fitloop.user.UserDtos.RegisterRequest;
import jakarta.validation.Validation;
import org.junit.jupiter.api.Test;

class PasswordPolicySecurityTest {

    @Test
    void registrationAndResetRejectTriviallyShortPasswords() {
        try (var factory = Validation.buildDefaultValidatorFactory()) {
            var validator = factory.getValidator();

            assertThat(validator.validate(
                    new RegisterRequest(null, "synthetic@example.invalid", "x", "123456", "Synthetic")))
                    .as("registration must enforce a non-trivial password length")
                    .isNotEmpty();
            assertThat(validator.validate(
                    new PasswordResetRequest("synthetic@example.invalid", "123456", "x")))
                    .as("password reset must enforce the same password policy")
                    .isNotEmpty();
        }
    }

    @Test
    void registrationAndResetAcceptPasswordsMeetingMinimumLength() {
        try (var factory = Validation.buildDefaultValidatorFactory()) {
            var validator = factory.getValidator();

            assertThat(validator.validate(
                    new RegisterRequest(null, "synthetic@example.invalid", "pass1234", "123456", "Synthetic")))
                    .as("an eight-character password must satisfy the shared policy")
                    .isEmpty();
            assertThat(validator.validate(
                    new PasswordResetRequest("synthetic@example.invalid", "123456", "pass1234")))
                    .as("password reset must accept the same minimum length")
                    .isEmpty();
        }
    }
}
