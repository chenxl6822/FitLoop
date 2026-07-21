package com.fitloop.admin;

import com.fitloop.user.UserInfo;
import com.fitloop.user.UserRepository;
import com.fitloop.user.UserRole;
import java.util.Locale;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

@Component
public class AdminBootstrap implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(AdminBootstrap.class);

    private final UserRepository users;
    private final String bootstrapAccount;

    public AdminBootstrap(UserRepository users,
                          @Value("${fitloop.admin.bootstrap-account:}") String bootstrapAccount) {
        this.users = users;
        this.bootstrapAccount = bootstrapAccount;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        if (!StringUtils.hasText(bootstrapAccount)) {
            return;
        }
        if (users.existsByRole(UserRole.ADMIN)) {
            log.info("Admin bootstrap ignored because an administrator already exists");
            return;
        }

        String account = bootstrapAccount.trim();
        if (account.contains("@")) {
            account = account.toLowerCase(Locale.ROOT);
        }
        UserInfo user = users.findByPhoneOrEmail(account, account)
                .orElseThrow(() -> new IllegalStateException(
                        "FITLOOP_ADMIN_BOOTSTRAP_ACCOUNT must reference an existing user"));
        user.setRole(UserRole.ADMIN);
        log.warn("Initial administrator promoted: userId={}. Remove FITLOOP_ADMIN_BOOTSTRAP_ACCOUNT after startup.",
                user.getUserId());
    }
}
