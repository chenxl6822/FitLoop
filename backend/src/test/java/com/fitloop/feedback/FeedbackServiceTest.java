package com.fitloop.feedback;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fitloop.feedback.FeedbackDtos.CreateFeedbackRequest;
import com.fitloop.feedback.FeedbackDtos.FeedbackResponse;
import com.fitloop.feedback.FeedbackDtos.UpdateFeedbackRequest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;

@DataJpaTest
@Import(FeedbackService.class)
class FeedbackServiceTest {
    @Autowired
    private FeedbackService feedbackService;

    @Autowired
    private FeedbackRepository feedbacks;

    @Test
    void createsFeedback() {
        var response = feedbackService.create(1L,
                new CreateFeedbackRequest("bug", "测试反馈内容", "test@example.com"));
        assertThat(response.feedbackId()).isNotNull();
        assertThat(response.type()).isEqualTo("bug");
        assertThat(response.content()).isEqualTo("测试反馈内容");
        assertThat(response.status()).isEqualTo("pending");
    }

    @Test
    void listsUserFeedback() {
        feedbackService.create(1L,
                new CreateFeedbackRequest("feature", "功能建议1", null));
        feedbackService.create(2L,
                new CreateFeedbackRequest("bug", "其他用户反馈", null));
        feedbackService.create(1L,
                new CreateFeedbackRequest("other", "功能建议2", null));

        var list = feedbackService.listByUser(1L);
        assertThat(list).hasSize(2);
    }

    @Test
    void listsAllFeedback() {
        feedbackService.create(1L,
                new CreateFeedbackRequest("bug", "用户1反馈", null));
        feedbackService.create(2L,
                new CreateFeedbackRequest("feature", "用户2反馈", null));

        var list = feedbackService.listAll();
        assertThat(list).hasSize(2);
    }

    @Test
    void updatesFeedbackStatus() {
        var created = feedbackService.create(1L,
                new CreateFeedbackRequest("bug", "待处理反馈", null));

        var updated = feedbackService.updateStatus(created.feedbackId(),
                new UpdateFeedbackRequest("reviewed", "已记录，下个版本修复"));
        assertThat(updated.status()).isEqualTo("reviewed");
        assertThat(updated.adminNote()).isEqualTo("已记录，下个版本修复");
    }

    @Test
    void updateNonExistentThrows() {
        assertThatThrownBy(() -> feedbackService.updateStatus(9999L,
                new UpdateFeedbackRequest("reviewed", null)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("反馈不存在");
    }
}
