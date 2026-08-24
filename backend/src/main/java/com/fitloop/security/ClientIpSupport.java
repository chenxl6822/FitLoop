package com.fitloop.security;

import java.net.InetAddress;
import java.net.UnknownHostException;

/**
 * Resolves a rate-limit / audit client identity from the servlet remote address
 * and optional {@code X-Forwarded-For} chain.
 *
 * <p>Forwarded headers are trusted only when the immediate peer is a loopback or
 * private address (Compose Nginx → backend). The rightmost non-blank hop is used,
 * matching {@code $proxy_add_x_forwarded_for}. Direct peers must not select identity
 * from a client-supplied forwarded prefix.
 */
public final class ClientIpSupport {
    private ClientIpSupport() {
    }

    public static String resolve(String remoteAddr, String forwardedFor) {
        String remote = blankToNull(remoteAddr);
        if (remote == null) {
            return "unknown";
        }
        if (!isTrustedProxy(remote)) {
            return remote;
        }
        String hop = rightmostForwardedHop(forwardedFor);
        return hop != null ? hop : remote;
    }

    static boolean isTrustedProxy(String remoteAddr) {
        try {
            InetAddress address = InetAddress.getByName(remoteAddr.trim());
            return address.isLoopbackAddress()
                    || address.isLinkLocalAddress()
                    || address.isSiteLocalAddress();
        } catch (UnknownHostException ex) {
            return false;
        }
    }

    static String rightmostForwardedHop(String forwardedFor) {
        if (forwardedFor == null || forwardedFor.isBlank()) {
            return null;
        }
        String[] parts = forwardedFor.split(",");
        for (int i = parts.length - 1; i >= 0; i--) {
            String part = parts[i].trim();
            if (!part.isEmpty()) {
                return part;
            }
        }
        return null;
    }

    private static String blankToNull(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        return value.trim();
    }
}
