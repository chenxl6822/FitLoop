package com.fitloop.admin;

import static org.assertj.core.api.Assertions.assertThat;

import com.fitloop.feedback.FeedbackRepository;
import com.fitloop.user.UserInfo;
import com.fitloop.user.UserRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.context.annotation.Import;

@DataJpaTest
@Import(AdminService.class)
class AdminServiceTest {
    @Autowired
    private AdminService adminService;

    @Autowired
    private UserRepository users;

    @Test
    void returnsSystemStats() {
        var stats = adminService.getStats();
        assertThat(stats.totalUsers()).isEqualTo(0);
        assertThat(stats.todayNewUsers()).isEqualTo(0);
    }

    @Test
    void listsUsers() {
        UserInfo u = new UserInfo();
        u.setNickname("测试用户");
        u.setEmail("test@admin.com");
        u.setPasswordHash("hash");
        users.save(u);

        var list = adminService.listUsers(0, 20);
        assertThat(list.users()).hasSize(1);
        assertThat(list.users().get(0).nickname()).isEqualTo("测试用户");
    }

    @Test
    void getsUserDetail() {
        UserInfo u = new UserInfo();
        u.setNickname("详情用户");
        u.setEmail("detail@admin.com");
        u.setPasswordHash("hash");
        var saved = users.save(u);

        var detail = adminService.getUserDetail(saved.getUserId());
        assertThat(detail.nickname()).isEqualTo("详情用户");
        assertThat(detail.email()).isEqualTo("detail@admin.com");
    }
}
