package com.fitloop.sport;

import java.util.Locale;
import org.springframework.stereotype.Component;

@Component
public class CalorieCalculator {
    public double estimate(String sportType, double weightKg, long durationSeconds) {
        double met = switch (sportType.toLowerCase(Locale.ROOT)) {
            case "running", "跑步" -> 8.0;
            case "cycling", "骑行" -> 6.8;
            case "walking", "健走" -> 3.8;
            case "rope_skipping", "跳绳" -> 11.0;
            default -> 4.5;
        };
        return round(met * weightKg * durationSeconds / 3600.0);
    }

    public double round(double value) {
        return Math.round(value * 10.0) / 10.0;
    }
}
