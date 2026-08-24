package com.fitloop.user;

/**
 * Wrong or exhausted verification codes must not roll back the attempt counter
 * written in the same service transaction as login/register/reset.
 */
public class InvalidVerificationCodeException extends IllegalArgumentException {
    public InvalidVerificationCodeException(String message) {
        super(message);
    }
}
