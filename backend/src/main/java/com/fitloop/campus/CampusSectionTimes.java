package com.fitloop.campus;

import java.time.LocalTime;
import java.util.Map;

/**
 * XTU default section start times (Asia/Shanghai, approximate).
 */
final class CampusSectionTimes {
    private static final Map<Integer, LocalTime> STARTS = Map.ofEntries(
            Map.entry(1, LocalTime.of(8, 0)),
            Map.entry(2, LocalTime.of(8, 55)),
            Map.entry(3, LocalTime.of(10, 5)),
            Map.entry(4, LocalTime.of(11, 0)),
            Map.entry(5, LocalTime.of(14, 0)),
            Map.entry(6, LocalTime.of(14, 55)),
            Map.entry(7, LocalTime.of(16, 5)),
            Map.entry(8, LocalTime.of(17, 0)),
            Map.entry(9, LocalTime.of(19, 0)),
            Map.entry(10, LocalTime.of(19, 55)),
            Map.entry(11, LocalTime.of(21, 0)),
            Map.entry(12, LocalTime.of(21, 55));

    private CampusSectionTimes() {
    }

    static LocalTime sectionStart(int section) {
        return STARTS.getOrDefault(section, LocalTime.of(8, 0));
    }

    static LocalTime sectionEnd(int section) {
        return sectionStart(section).plusMinutes(45);
    }
}
