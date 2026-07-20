package com.fitloop.social;

import com.fitloop.sport.CalorieCalculator;
import com.fitloop.sport.SportRecord;
import com.fitloop.sport.SportRecordRepository;
import com.fitloop.sport.WorkoutCompletedEvent;
import com.fitloop.user.UserInfo;
import com.fitloop.user.UserRepository;
import com.fitloop.social.SocialDtos.FriendInfo;
import com.fitloop.social.SocialDtos.FriendListResponse;
import com.fitloop.social.SocialDtos.FriendRequest;
import com.fitloop.social.SocialDtos.FriendResponse;
import com.fitloop.social.SocialDtos.MedalResponse;
import com.fitloop.social.SocialDtos.RankingResponse;
import com.fitloop.social.SocialDtos.RankingRow;
import com.fitloop.social.SocialDtos.UserSearchItem;
import com.fitloop.social.SocialDtos.UserSearchResponse;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

@Service
public class SocialService {
    private final UserRepository users;
    private final UserFriendRepository friends;
    private final SportRecordRepository sportRecords;
    private final CalorieCalculator calculator;
    private final StringRedisTemplate redis;
    private final LeaderboardService leaderboard;

    public SocialService(UserRepository users, UserFriendRepository friends, SportRecordRepository sportRecords,
                         CalorieCalculator calculator, StringRedisTemplate redis, LeaderboardService leaderboard) {
        this.users = users;
        this.friends = friends;
        this.sportRecords = sportRecords;
        this.calculator = calculator;
        this.redis = redis;
        this.leaderboard = leaderboard;
    }

    @TransactionalEventListener(phase = TransactionPhase.BEFORE_COMMIT)
    public void onWorkoutCompleted(WorkoutCompletedEvent event) {
        SportRecord record = new SportRecord();
        record.setUserId(event.userId());
        record.setCalorie(event.calorie());
        record.setStatus(SportRecord.STATUS_VALID);
        reward(record);
    }

    @Transactional
    public void reward(SportRecord record) {
        if (record.getStatus() != SportRecord.STATUS_VALID) {
            return;
        }
        UserInfo user = users.findById(record.getUserId())
                .orElseThrow(() -> new IllegalArgumentException("用户不存在"));
        int earned = Math.max(1, (int) Math.round(record.getCalorie() / 10.0));
        user.setPoints(user.getPoints() + earned);
        user.setLevel(user.getPoints() / 100 + 1);
        try {
            redis.delete("ranking:personal:week");
        } catch (RuntimeException ignored) {
            // Ranking cache invalidation must not make a completed check-in fail.
        }
    }

    @Transactional(readOnly = true)
    public MedalResponse medal(Long userId) {
        UserInfo user = users.findById(userId).orElseThrow(() -> new IllegalArgumentException("用户不存在"));
        List<String> medals = new ArrayList<>();
        if (user.getPoints() >= 10) medals.add("初次启程");
        if (user.getPoints() >= 100) medals.add("校园活力达人");
        return new MedalResponse(user.getPoints(), user.getLevel(), medals);
    }

    @Transactional(readOnly = true)
    public RankingResponse ranking(String scope, String period, int page, int size) {
        return leaderboard.ranking(scope, period, page, size);
    }

    @Transactional
    public FriendResponse addFriend(Long userId, FriendRequest request) {
        if (request.friendUserId() == null || request.friendUserId().equals(userId)) {
            throw new IllegalArgumentException("好友用户不合法");
        }
        UserFriend friend = new UserFriend();
        friend.setUserId(userId);
        friend.setFriendUserId(request.friendUserId());
        return FriendResponse.from(friends.save(friend));
    }

    @Transactional(readOnly = true)
    public FriendListResponse listFriends(Long userId) {
        List<UserFriend> relations = friends.findByUserId(userId);
        List<FriendInfo> list = relations.stream().map(f -> {
            UserInfo friendUser = users.findById(f.getFriendUserId()).orElse(null);
            return new FriendInfo(f.getFriendId(), f.getFriendUserId(),
                    friendUser != null ? friendUser.getNickname() : "未知用户",
                    friendUser != null ? friendUser.getPoints() : 0,
                    friendUser != null ? friendUser.getLevel() : 0,
                    f.getStatus());
        }).toList();
        return new FriendListResponse(list);
    }

    @Transactional(readOnly = true)
    public UserSearchResponse searchUsers(Long userId, String query) {
        if (query == null || query.trim().isEmpty()) {
            return new UserSearchResponse(List.of());
        }
        String q = query.trim();
        List<UserInfo> matches = users.findByNicknameContainingOrPhoneContaining(q, q);
        Set<Long> friendIds = friends.findByUserId(userId).stream()
                .map(UserFriend::getFriendUserId)
                .collect(Collectors.toSet());
        List<UserSearchItem> items = matches.stream()
                .filter(u -> !u.getUserId().equals(userId))
                .map(u -> new UserSearchItem(u.getUserId(), u.getNickname(), u.getPoints(), u.getLevel(),
                        friendIds.contains(u.getUserId())))
                .toList();
        return new UserSearchResponse(items);
    }

    private RankingRow toRankingRow(Map.Entry<Long, double[]> entry, Map<Long, double[]> totals) {
        List<Long> ordered = totals.entrySet().stream()
                .sorted(Map.Entry.<Long, double[]>comparingByValue(Comparator.comparingDouble((double[] v) -> -v[0])))
                .map(Map.Entry::getKey)
                .toList();
        UserInfo user = users.findById(entry.getKey()).orElse(null);
        return new RankingRow(ordered.indexOf(entry.getKey()) + 1, entry.getKey(),
                user == null ? "FitLoop 用户" : user.getNickname(),
                calculator.round(entry.getValue()[0]), calculator.round(entry.getValue()[1]));
    }
}
