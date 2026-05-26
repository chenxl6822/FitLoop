package com.fitloop.user;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserRepository extends JpaRepository<UserInfo, Long> {
    Optional<UserInfo> findByPhoneOrEmail(String phone, String email);

    boolean existsByPhone(String phone);

    boolean existsByEmail(String email);

    List<UserInfo> findByNicknameContainingOrPhoneContaining(String nickname, String phone);
}
