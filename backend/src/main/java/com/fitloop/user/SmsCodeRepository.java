package com.fitloop.user;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface SmsCodeRepository extends JpaRepository<SmsCode, Long> {
    Optional<SmsCode> findTopByPhoneAndCodeAndUsedFalseOrderByCreatedAtDesc(String phone, String code);
}
