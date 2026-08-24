package com.fitloop.security;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class ClientIpSupportTest {

    @Test
    void trustedLoopbackUsesRightmostForwardedHop() {
        assertThat(ClientIpSupport.resolve("127.0.0.1", "198.51.100.77, 203.0.113.10"))
                .isEqualTo("203.0.113.10");
    }

    @Test
    void untrustedPeerIgnoresForwardedHeader() {
        assertThat(ClientIpSupport.resolve("198.51.100.50", "203.0.113.9, 198.51.100.77"))
                .isEqualTo("198.51.100.50");
    }

    @Test
    void trustedPeerWithoutForwardedUsesRemote() {
        assertThat(ClientIpSupport.resolve("172.18.0.5", null)).isEqualTo("172.18.0.5");
        assertThat(ClientIpSupport.resolve("172.18.0.5", "  ")).isEqualTo("172.18.0.5");
    }
}
