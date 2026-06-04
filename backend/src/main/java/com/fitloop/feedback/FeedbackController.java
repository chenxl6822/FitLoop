package com.fitloop.feedback;

import com.fitloop.common.ApiResponse;
import com.fitloop.feedback.FeedbackDtos.CreateFeedbackRequest;
import com.fitloop.feedback.FeedbackDtos.FeedbackListResponse;
import com.fitloop.feedback.FeedbackDtos.FeedbackResponse;
import com.fitloop.feedback.FeedbackDtos.UpdateFeedbackRequest;
import com.fitloop.security.AuthSupport;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class FeedbackController {
    private final FeedbackService feedbacks;

    public FeedbackController(FeedbackService feedbacks) {
        this.feedbacks = feedbacks;
    }

    @PostMapping("/api/feedback")
    public ApiResponse<FeedbackResponse> create(@Valid @RequestBody CreateFeedbackRequest request) {
        return ApiResponse.ok(feedbacks.create(AuthSupport.currentUserId(), request));
    }

    @GetMapping("/api/feedback")
    public ApiResponse<FeedbackListResponse> listByUser() {
        return ApiResponse.ok(new FeedbackListResponse(
                feedbacks.listByUser(AuthSupport.currentUserId())));
    }

    @GetMapping("/api/admin/feedback")
    public ApiResponse<FeedbackListResponse> listAll() {
        return ApiResponse.ok(new FeedbackListResponse(feedbacks.listAll()));
    }

    @PutMapping("/api/admin/feedback/{feedbackId}")
    public ApiResponse<FeedbackResponse> updateStatus(@PathVariable Long feedbackId,
                                                      @Valid @RequestBody UpdateFeedbackRequest request) {
        return ApiResponse.ok(feedbacks.updateStatus(feedbackId, request));
    }
}
