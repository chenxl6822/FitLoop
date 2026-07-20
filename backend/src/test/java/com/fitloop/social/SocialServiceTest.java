package com.fitloop.social;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fitloop.social.SocialDtos.FriendRequest;
import com.fitloop.sport.CalorieCalculator;
import com.fitloop.sport.SportRecord;
import com.fitloop.sport.SportRecordRepository;
import com.fitloop.user.UserInfo;
import com.fitloop.user.UserRepository;
import java.time.Instant;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.context.annotation.Import;

@DataJpaTest
@Import({SocialService.class, LeaderboardService.class, CalorieCalculator.class})
class SocialServiceTest {

    @Autowired
    private SocialService socialService;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private UserFriendRepository friendRepository;

    @Autowired
    private SportRecordRepository sportRecordRepository;

    @MockitoBean
    private org.springframework.data.redis.core.StringRedisTemplate redis;

    @BeforeEach
    void setUp() {
        friendRepository.deleteAll();
        sportRecordRepository.deleteAll();
        userRepository.deleteAll();
    }

    private UserInfo createUser(String phone, String nickname) {
        UserInfo u = new UserInfo();
        u.setPhone(phone);
        u.setPasswordHash("hash");
        u.setNickname(nickname);
        return userRepository.save(u);
    }

    @Test
    void listFriendsReturnsEmptyForNewUser() {
        var result = socialService.listFriends(99L);
        assertThat(result.friends()).isEmpty();
    }

    @Test
    void listFriendsReturnsFriendDetails() {
        var u1 = createUser("13800000001", "Alice");
        var u2 = createUser("13800000002", "Bob");
        socialService.addFriend(u1.getUserId(), new FriendRequest(u2.getUserId()));

        var result = socialService.listFriends(u1.getUserId());
        assertThat(result.friends()).hasSize(1);
        assertThat(result.friends().get(0).nickname()).isEqualTo("Bob");
        assertThat(result.friends().get(0).status()).isEqualTo("active");
    }

    @Test
    void searchUsersReturnsMatchingResults() {
        createUser("13800000001", "Alice");
        createUser("13800000002", "Bob");
        var me = createUser("13800000003", "Charlie");

        var result = socialService.searchUsers(me.getUserId(), "Ali");
        assertThat(result.users()).hasSize(1);
        assertThat(result.users().get(0).nickname()).isEqualTo("Alice");
        assertThat(result.users().get(0).isFriend()).isFalse();
    }

    @Test
    void searchUsersMarksExistingFriends() {
        var u1 = createUser("13800000001", "Alice");
        var u2 = createUser("13800000002", "Bob");
        socialService.addFriend(u1.getUserId(), new FriendRequest(u2.getUserId()));

        var result = socialService.searchUsers(u1.getUserId(), "Bob");
        assertThat(result.users()).hasSize(1);
        assertThat(result.users().get(0).isFriend()).isTrue();
    }

    @Test
    void searchUsersExcludesSelf() {
        var me = createUser("13800000001", "Alice");

        var result = socialService.searchUsers(me.getUserId(), "Ali");
        assertThat(result.users()).isEmpty();
    }

    @Test
    void searchUsersEmptyQueryReturnsEmpty() {
        createUser("13800000001", "Alice");

        var result = socialService.searchUsers(1L, "");
        assertThat(result.users()).isEmpty();

        var result2 = socialService.searchUsers(1L, null);
        assertThat(result2.users()).isEmpty();
    }

    @Test
    void addFriendRejectsSelf() {
        var u = createUser("13800000001", "Alice");

        assertThatThrownBy(() -> socialService.addFriend(u.getUserId(),
                new FriendRequest(u.getUserId())))
                .hasMessageContaining("不合法");
    }

    @Test
    void searchUsersByPhoneAlsoWorks() {
        var david = createUser("13811112222", "David");
        var alice = createUser("13800000001", "Alice");

        // Search as Alice, looking for David by partial phone
        var result = socialService.searchUsers(alice.getUserId(), "1381111");
        assertThat(result.users()).hasSize(1);
        assertThat(result.users().get(0).nickname()).isEqualTo("David");
    }

    @Test
    void weeklyRankingFallsBackToMysqlWhenRedisIsDown() {
        var user = createUser("13800000009", "Runner");
        SportRecord record = new SportRecord();
        record.setUserId(user.getUserId());
        record.setSessionId("redis-fallback-session");
        record.setSportType("running");
        record.setCheckinMode("manual");
        record.setDistanceKm(5.2);
        record.setCalorie(310);
        record.setStatus(SportRecord.STATUS_VALID);
        record.setStartedAt(Instant.now());
        sportRecordRepository.saveAndFlush(record);
        org.mockito.Mockito.when(redis.opsForZSet())
                .thenThrow(new org.springframework.data.redis.RedisConnectionFailureException("redis down"));

        var result = socialService.ranking("personal", "week", 1, 20);

        assertThat(result.rankingList()).hasSize(1);
        assertThat(result.rankingList().getFirst().userId()).isEqualTo(user.getUserId());
        assertThat(result.rankingList().getFirst().distanceKm()).isEqualTo(5.2);
    }
}
