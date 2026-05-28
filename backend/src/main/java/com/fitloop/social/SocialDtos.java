package com.fitloop.social;

import java.util.List;

public final class SocialDtos {
    private SocialDtos() {
    }

    public record FriendRequest(Long friendUserId) {
    }

    public record FriendInfo(Long friendId, Long friendUserId, String nickname, int points, int level, String status) {
    }

    public record FriendListResponse(java.util.List<FriendInfo> friends) {
    }

    public record UserSearchItem(Long userId, String nickname, int points, int level, boolean isFriend) {
    }

    public record UserSearchResponse(java.util.List<UserSearchItem> users) {
    }

    public record FriendResponse(Long friendId, Long friendUserId, String status) {
        public static FriendResponse from(UserFriend friend) {
            return new FriendResponse(friend.getFriendId(), friend.getFriendUserId(), friend.getStatus());
        }
    }

    public record MedalResponse(int points, int level, List<String> medals) {
    }

    public record RankingRow(int rank, Long userId, String nickname, double distanceKm, double calorie) {
    }

    public record RankingResponse(String scope, String period, List<RankingRow> rankingList) {
    }
}
