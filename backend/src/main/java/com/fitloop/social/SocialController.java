package com.fitloop.social;

import com.fitloop.common.ApiResponse;
import com.fitloop.security.AuthSupport;
import com.fitloop.social.SocialDtos.FriendListResponse;
import com.fitloop.social.SocialDtos.FriendRequest;
import com.fitloop.social.SocialDtos.FriendResponse;
import com.fitloop.social.SocialDtos.MedalResponse;
import com.fitloop.social.SocialDtos.RankingResponse;
import com.fitloop.social.SocialDtos.UserSearchResponse;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class SocialController {
    private final SocialService social;

    public SocialController(SocialService social) {
        this.social = social;
    }

    @GetMapping("/api/social/medal")
    public ApiResponse<MedalResponse> medal() {
        return ApiResponse.ok(social.medal(AuthSupport.currentUserId()));
    }

    @GetMapping("/api/social/ranking")
    public ApiResponse<RankingResponse> ranking(@RequestParam(defaultValue = "personal") String scope,
                                                @RequestParam(defaultValue = "week") String period,
                                                @RequestParam(defaultValue = "1") int page,
                                                @RequestParam(defaultValue = "20") int size) {
        return ApiResponse.ok(social.ranking(scope, period, page, size));
    }

    @PostMapping("/api/social/friend")
    public ApiResponse<FriendResponse> friend(@RequestBody FriendRequest request) {
        return ApiResponse.ok(social.addFriend(AuthSupport.currentUserId(), request));
    }

    @GetMapping("/api/social/friends")
    public ApiResponse<FriendListResponse> friends() {
        return ApiResponse.ok(social.listFriends(AuthSupport.currentUserId()));
    }

    @GetMapping("/api/social/friends/search")
    public ApiResponse<UserSearchResponse> searchUsers(@RequestParam("q") String query) {
        return ApiResponse.ok(social.searchUsers(AuthSupport.currentUserId(), query));
    }
}
