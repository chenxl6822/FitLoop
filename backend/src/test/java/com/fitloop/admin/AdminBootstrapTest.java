package com.fitloop.admin;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fitloop.user.UserInfo;
import com.fitloop.user.UserRepository;
import com.fitloop.user.UserRole;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.boot.DefaultApplicationArguments;

@ExtendWith(MockitoExtension.class)
class AdminBootstrapTest {

    @Mock
    private UserRepository users;

    @Test
    void doesNothingWhenBootstrapAccountIsBlank() {
        new AdminBootstrap(users, " ").run(new DefaultApplicationArguments());

        verify(users, never()).existsByRole(UserRole.ADMIN);
    }

    @Test
    void doesNothingWhenAnAdministratorAlreadyExists() {
        when(users.existsByRole(UserRole.ADMIN)).thenReturn(true);

        new AdminBootstrap(users, "13800000000").run(new DefaultApplicationArguments());

        verify(users, never()).findByPhoneOrEmail(anyString(), anyString());
    }

    @Test
    void promotesAnExistingUserAndNormalizesEmail() {
        UserInfo user = new UserInfo();
        user.setRole(UserRole.USER);
        when(users.existsByRole(UserRole.ADMIN)).thenReturn(false);
        when(users.findByPhoneOrEmail("admin@example.com", "admin@example.com"))
                .thenReturn(Optional.of(user));

        new AdminBootstrap(users, " Admin@Example.com ").run(new DefaultApplicationArguments());

        assertThat(user.getRole()).isEqualTo(UserRole.ADMIN);
    }

    @Test
    void rejectsAnUnknownBootstrapAccount() {
        when(users.existsByRole(UserRole.ADMIN)).thenReturn(false);
        when(users.findByPhoneOrEmail("13800000000", "13800000000"))
                .thenReturn(Optional.empty());

        AdminBootstrap bootstrap = new AdminBootstrap(users, "13800000000");

        assertThatThrownBy(() -> bootstrap.run(new DefaultApplicationArguments()))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("existing user");
    }
}
