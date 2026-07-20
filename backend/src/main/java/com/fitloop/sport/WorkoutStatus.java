package com.fitloop.sport;

import java.util.Arrays;

public enum WorkoutStatus {
    DRAFT(0),
    VALID(1),
    ABNORMAL(2),
    APPEALING(3);

    private final int code;

    WorkoutStatus(int code) {
        this.code = code;
    }

    public int code() {
        return code;
    }

    public static WorkoutStatus fromCode(int code) {
        return Arrays.stream(values()).filter(value -> value.code == code).findFirst()
                .orElseThrow(() -> new IllegalArgumentException("Unknown workout status: " + code));
    }
}
