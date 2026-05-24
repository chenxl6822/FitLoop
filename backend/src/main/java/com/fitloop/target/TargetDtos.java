package com.fitloop.target;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;
import java.time.LocalDate;
import java.util.List;

public final class TargetDtos {
    private TargetDtos() {
    }

    public record CreateTargetRequest(@NotBlank String periodType, @NotBlank String metric,
                                      @Positive double targetValue) {
    }

    public record TargetResponse(Long targetId, String periodType, String metric, double targetValue,
                                 double completedValue, double progress, LocalDate startDate,
                                 LocalDate endDate, String status) {
        public static TargetResponse from(SportTarget target) {
            double progress = target.getTargetValue() <= 0 ? 0
                    : Math.min(100.0, target.getCompletedValue() / target.getTargetValue() * 100.0);
            return new TargetResponse(target.getTargetId(), target.getPeriodType(), target.getMetric(),
                    target.getTargetValue(), target.getCompletedValue(), Math.round(progress * 10.0) / 10.0,
                    target.getStartDate(), target.getEndDate(), target.getStatus());
        }
    }

    public record TargetListResponse(List<TargetResponse> targets) {
    }
}
