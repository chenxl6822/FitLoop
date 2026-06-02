package com.fitloop.user;

public interface VerificationCodeSender {
    String channel();

    void send(String target, String code, String purpose);
}
