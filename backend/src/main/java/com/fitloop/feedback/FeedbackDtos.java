package com.fitloop.feedback;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;

public final class FeedbackDtos {
    private FeedbackDtos() {}

    public record CreateFeedbackRequest(
            @NotBlank String type,
            @NotBlank String content,
            String contact) {}

    public record FeedbackResponse(
            Long feedbackId,
            String type,
            String content,
            String contact,
            String status,
            String adminNote,
            Instant createdAt) {
        public static FeedbackResponse from(Feedback f) {
            return new FeedbackResponse(
                    f.getFeedbackId(), f.getType(), f.getContent(),
                    f.getContact(), f.getStatus(), f.getAdminNote(),
                    f.getCreatedAt());
        }
    }

    public record FeedbackListResponse(List<FeedbackResponse> feedbacks) {}

    public record UpdateFeedbackRequest(@Size(max = 20) String status,
                                        @Size(max = 1000) String adminNote) {}
}
