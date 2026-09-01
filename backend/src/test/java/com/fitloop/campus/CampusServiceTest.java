package com.fitloop.campus;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

import com.fitloop.campus.CampusAuthClient.CampusVerifyResult;
import com.fitloop.campus.CampusDtos.CampusVerifyRequest;
import com.fitloop.user.UserInfo;
import com.fitloop.user.UserRepository;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.server.ResponseStatusException;

@ExtendWith(MockitoExtension.class)
class CampusServiceTest {
    @Mock
    private CampusVerificationRepository verifications;
    @Mock
    private UserRepository users;
    @Mock
    private CampusAuthClient campusAuthClient;
    @Mock
    private CampusScheduleService campusScheduleService;

    private CampusService service;

    @BeforeEach
    void setUp() {
        service = new CampusService(
                verifications,
                users,
                campusAuthClient,
                campusScheduleService,
                "campus-hash-secret-value-32bytes!!");
    }

    @Test
    void statusReturnsUnverifiedWhenMissing() {
        when(verifications.findByUserId(7L)).thenReturn(Optional.empty());
        var status = service.status(7L);
        assertThat(status.verified()).isFalse();
    }

    @Test
    void verifyLinksStudentIdentity() {
        when(verifications.findByUserId(7L)).thenReturn(Optional.empty());
        when(verifications.findByStudentIdHash(anyString())).thenReturn(Optional.empty());
        when(campusAuthClient.verify(7L, "20230001", "pw"))
                .thenReturn(new CampusVerifyResult("20230001", "数学与计算科学学院", "计科2班", "软件工程", "2023级"));
        var user = new UserInfo();
        user.setNickname("Tester");
        when(users.findById(7L)).thenReturn(Optional.of(user));
        when(verifications.save(org.mockito.ArgumentMatchers.any())).thenAnswer(invocation -> {
            CampusVerification saved = invocation.getArgument(0);
            return saved;
        });

        var status = service.verify(7L, new CampusVerifyRequest("20230001", "pw"));

        assertThat(status.verified()).isTrue();
        assertThat(status.college()).isEqualTo("数学与计算科学学院");
        assertThat(status.className()).isEqualTo("计科2班");
        assertThat(user.getCollege()).isEqualTo("数学与计算科学学院");
        assertThat(user.getGrade()).isEqualTo("2023级");
    }

    @Test
    void verifyRejectsDuplicateUserBinding() {
        when(verifications.findByUserId(7L)).thenReturn(Optional.of(new CampusVerification()));
        assertThatThrownBy(() -> service.verify(7L, new CampusVerifyRequest("20230001", "pw")))
                .isInstanceOf(ResponseStatusException.class);
    }
}
