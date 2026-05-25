package com.fitloop.appeal;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.time.Instant;
import java.util.List;

public final class AppealDtos {
    private AppealDtos() {
    }

    public record CreateAppealRequest(@NotNull Long recordId, @NotBlank String reason, String evidenceUrl) {
    }

    public record AppealResponse(Long appealId, Long recordId, String reason, String evidenceUrl,
                                 String status, String reviewNote, Instant createdAt, Instant updatedAt) {
        public static AppealResponse from(Appeal appeal) {
            return new AppealResponse(appeal.getAppealId(), appeal.getRecordId(), appeal.getReason(),
                    appeal.getEvidenceUrl(), appeal.getStatus(), appeal.getReviewNote(),
                    appeal.getCreatedAt(), appeal.getUpdatedAt());
        }
    }

    public record AppealListResponse(List<AppealResponse> appeals) {
    }
}
