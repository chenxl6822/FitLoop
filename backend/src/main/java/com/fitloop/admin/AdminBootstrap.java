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
    private final String bootstrapNickname;

    public AdminBootstrap(UserRepository users,
                          @Value("${fitloop.admin.bootstrap-account:}") String bootstrapAccount,
                          @Value("${fitloop.admin.bootstrap-nickname:}") String bootstrapNickname) {
        this.users = users;
        this.bootstrapAccount = bootstrapAccount;
        this.bootstrapNickname = bootstrapNickname;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        boolean hasAccount = StringUtils.hasText(bootstrapAccount);
        boolean hasNickname = StringUtils.hasText(bootstrapNickname);
        if (!hasAccount && !hasNickname) {
            return;
        }
        if (users.existsByRole(UserRole.ADMIN)) {
            log.info("Admin bootstrap ignored because an administrator already exists");
            return;
        }
        if (!hasAccount || !hasNickname) {
            throw new IllegalStateException(
                    "FITLOOP_ADMIN_BOOTSTRAP_ACCOUNT and FITLOOP_ADMIN_BOOTSTRAP_NICKNAME must be set together");
        }

        String account = bootstrapAccount.trim();
        if (account.contains("@")) {
            account = account.toLowerCase(Locale.ROOT);
        }
        UserInfo user = users.findByPhoneOrEmail(account, account)
                .orElseThrow(() -> new IllegalStateException(
                        "FITLOOP_ADMIN_BOOTSTRAP_ACCOUNT must reference an existing user"));
        if (!bootstrapNickname.trim().equals(user.getNickname())) {
            throw new IllegalStateException(
                    "FITLOOP_ADMIN_BOOTSTRAP_NICKNAME does not match the existing user");
        }
        user.setRole(UserRole.ADMIN);
        log.warn("Initial administrator promoted: userId={}. Remove both admin bootstrap variables after startup.",
                user.getUserId());
    }
}
