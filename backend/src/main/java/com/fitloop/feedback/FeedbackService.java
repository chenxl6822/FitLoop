package com.fitloop.feedback;

import com.fitloop.audit.AdminAuditService;
import com.fitloop.feedback.FeedbackDtos.CreateFeedbackRequest;
import com.fitloop.feedback.FeedbackDtos.FeedbackResponse;
import com.fitloop.feedback.FeedbackDtos.UpdateFeedbackRequest;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class FeedbackService {
    private final FeedbackRepository feedbacks;
    private final AdminAuditService audits;

    public FeedbackService(FeedbackRepository feedbacks, AdminAuditService audits) {
        this.feedbacks = feedbacks;
        this.audits = audits;
    }

    @Transactional
    public FeedbackResponse create(Long userId, CreateFeedbackRequest request) {
        Feedback f = new Feedback();
        f.setUserId(userId);
        f.setType(request.type());
        f.setContent(request.content());
        f.setContact(request.contact());
        f.setStatus("pending");
        return FeedbackResponse.from(feedbacks.save(f));
    }

    @Transactional(readOnly = true)
    public List<FeedbackResponse> listByUser(Long userId) {
        return feedbacks.findByUserIdOrderByCreatedAtDesc(userId).stream()
                .map(FeedbackResponse::from)
                .toList();
    }

    @Transactional(readOnly = true)
    public List<FeedbackResponse> listAll() {
        return feedbacks.findAllByOrderByCreatedAtDesc().stream()
                .map(FeedbackResponse::from)
                .toList();
    }

    @Transactional
    public FeedbackResponse updateStatus(Long feedbackId, UpdateFeedbackRequest request) {
        return updateStatus(feedbackId, request, null);
    }

    @Transactional
    public FeedbackResponse updateStatus(Long feedbackId, UpdateFeedbackRequest request, Long actorUserId) {
        Feedback f = feedbacks.findById(feedbackId)
                .orElseThrow(() -> new IllegalArgumentException("反馈不存在"));
        if (request.status() != null && !request.status().isBlank()) {
            f.setStatus(request.status());
        }
        if (request.adminNote() != null) {
            f.setAdminNote(request.adminNote());
        }
        if (actorUserId != null) {
            audits.record(actorUserId, "FEEDBACK_UPDATED", "FEEDBACK", feedbackId,
                    "{\"status\":\"" + f.getStatus() + "\"}");
        }
        return FeedbackResponse.from(feedbacks.save(f));
    }
}
