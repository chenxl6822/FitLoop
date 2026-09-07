package com.fitloop.common;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.web.MockHttpServletRequest;

class GlobalExceptionHandlerTest {
    @Test
    void dataIntegrityFailureReturnsServerErrorWithoutDatabaseDetails() {
        var request = new MockHttpServletRequest();
        request.setRequestURI("/api/v1/agent/actions/12/confirm");
        request.setAttribute(RequestIdFilter.ATTRIBUTE, "request-123");
        var exception = new DataIntegrityViolationException(
                "Data too long for column 'review_note'");

        Object result = new GlobalExceptionHandler().dataIntegrity(exception, request);

        assertThat(result).isInstanceOf(ResponseEntity.class);
        ResponseEntity<?> response = (ResponseEntity<?>) result;
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
        assertThat(response.getBody()).isInstanceOf(ProblemDetail.class);
        ProblemDetail problem = (ProblemDetail) response.getBody();
        assertThat(problem.getDetail()).isEqualTo("数据保存失败，请稍后重试");
        assertThat(problem.getProperties()).containsEntry("requestId", "request-123");
        assertThat(problem.toString()).doesNotContain("review_note");
    }
}
