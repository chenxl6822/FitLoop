package com.fitloop.security;

import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

public final class AuthSupport {
    private AuthSupport() {
    }

    public static Long currentUserId() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || authentication.getPrincipal() == null) {
            throw new IllegalArgumentException("未登录或登录已过期");
        }
        return Long.valueOf(authentication.getPrincipal().toString());
    }
}
