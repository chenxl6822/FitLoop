package com.fitloop.common;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.ConstraintViolationException;
import java.net.URI;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(IllegalArgumentException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Object illegalArgument(IllegalArgumentException ex, HttpServletRequest request) {
        return error(request, HttpStatus.BAD_REQUEST, "Invalid request", ex.getMessage());
    }

    @ExceptionHandler({MethodArgumentNotValidException.class, ConstraintViolationException.class})
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Object validation(Exception ex, HttpServletRequest request) {
        return error(request, HttpStatus.BAD_REQUEST, "Validation failed", "请求参数不合法");
    }

    private Object error(HttpServletRequest request, HttpStatus status, String title, String detail) {
        if (!request.getRequestURI().startsWith("/api/v1/")) {
            return ApiResponse.fail(status.value() * 100, detail);
        }
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(status, detail);
        problem.setTitle(title);
        problem.setType(URI.create("https://fitloop.local/problems/" + status.value()));
        problem.setInstance(URI.create(request.getRequestURI()));
        problem.setProperty("requestId", request.getAttribute(RequestIdFilter.ATTRIBUTE));
        return ResponseEntity.status(status).body(problem);
    }
}
