package com.fitloop.appeal;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;

public final class AppealDtos {
    private AppealDtos() {
    }

    public record CreateAppealRequest(@NotNull Long recordId, @NotBlank String reason, String evidenceUrl) {
    }

    public record ReviewAppealRequest(@NotBlank String status, @Size(max = 255) String reviewNote) {
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

    public record AdminAppealResponse(Long appealId, Long userId, Long recordId, String reason,
                                      String evidenceUrl, String status, String reviewNote,
                                      Instant createdAt, Instant updatedAt) {
        public static AdminAppealResponse from(Appeal appeal) {
            return new AdminAppealResponse(appeal.getAppealId(), appeal.getUserId(), appeal.getRecordId(),
                    appeal.getReason(), appeal.getEvidenceUrl(), appeal.getStatus(), appeal.getReviewNote(),
                    appeal.getCreatedAt(), appeal.getUpdatedAt());
        }
    }

    public record AdminAppealPageResponse(List<AdminAppealResponse> items, int page, int size,
                                          long totalElements, int totalPages) { }
}
