package com.fitloop.social;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserFriendRepository extends JpaRepository<UserFriend, Long> {
    List<UserFriend> findByUserId(Long userId);
}
