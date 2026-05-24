package com.fitloop.social;

import com.fitloop.sport.CalorieCalculator;
import com.fitloop.sport.SportRecord;
import com.fitloop.sport.SportRecordRepository;
import com.fitloop.user.UserInfo;
import com.fitloop.user.UserRepository;
import com.fitloop.social.SocialDtos.FriendRequest;
import com.fitloop.social.SocialDtos.FriendResponse;
import com.fitloop.social.SocialDtos.MedalResponse;
import com.fitloop.social.SocialDtos.RankingResponse;
import com.fitloop.social.SocialDtos.RankingRow;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class SocialService {
    private final UserRepository users;
    private final UserFriendRepository friends;
    private final SportRecordRepository sportRecords;
    private final CalorieCalculator calculator;
    private final StringRedisTemplate redis;

    public SocialService(UserRepository users, UserFriendRepository friends, SportRecordRepository sportRecords,
                         CalorieCalculator calculator, StringRedisTemplate redis) {
        this.users = users;
        this.friends = friends;
        this.sportRecords = sportRecords;
        this.calculator = calculator;
        this.redis = redis;
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
        Map<Long, double[]> totals = new HashMap<>();
        sportRecords.findByStatus(SportRecord.STATUS_VALID).forEach(record -> {
            double[] total = totals.computeIfAbsent(record.getUserId(), ignored -> new double[2]);
            total[0] += record.getDistanceKm();
            total[1] += record.getCalorie();
        });
        List<RankingRow> rows = totals.entrySet().stream()
                .sorted(Map.Entry.<Long, double[]>comparingByValue(Comparator.comparingDouble((double[] v) -> -v[0])))
                .skip((long) Math.max(page - 1, 0) * size)
                .limit(size)
                .map(entry -> toRankingRow(entry, totals))
                .toList();
        return new RankingResponse(scope, period, rows);
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
