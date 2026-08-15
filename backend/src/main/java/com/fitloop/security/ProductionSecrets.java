package com.fitloop.security;

import java.nio.charset.StandardCharsets;
import java.util.Locale;

/**
 * Shared fail-closed checks for authentication and agent credentials.
 * Known template placeholders must never be accepted as runtime secrets.
 */
public final class ProductionSecrets {
    private ProductionSecrets() {
    }

    public static byte[] requireSecret(String name, String value, int minBytes) {
        if (value == null || value.isBlank()) {
            throw new IllegalStateException(name + " must be configured");
        }
        String trimmed = value.trim();
        String lower = trimmed.toLowerCase(Locale.ROOT);
        if (lower.startsWith("change-me") || lower.startsWith("replace-with-")) {
            throw new IllegalStateException(name + " still uses a placeholder value");
        }
        byte[] bytes = trimmed.getBytes(StandardCharsets.UTF_8);
        if (bytes.length < minBytes) {
            throw new IllegalStateException(name + " must contain at least " + minBytes + " bytes");
        }
        return bytes;
    }
}
