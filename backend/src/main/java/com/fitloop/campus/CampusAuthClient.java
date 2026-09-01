package com.fitloop.campus;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpStatusCodeException;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;

@Component
public class CampusAuthClient {
    private final RestTemplate restTemplate;
    private final String baseUrl;
    private final String serviceKey;

    public CampusAuthClient(@Value("${fitloop.campus.auth-base-url:http://campus-auth:8091}") String baseUrl,
                            @Value("${fitloop.campus.service-key}") String serviceKey) {
        this.restTemplate = new RestTemplate();
        this.baseUrl = baseUrl.endsWith("/") ? baseUrl.substring(0, baseUrl.length() - 1) : baseUrl;
        com.fitloop.security.ProductionSecrets.requireSecret(
                "fitloop.campus.service-key", serviceKey, 32);
        this.serviceKey = serviceKey.trim();
    }

    public CampusVerifyResult verify(long userId, String studentId, String password) {
        var headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.set("X-Campus-Auth-Service-Key", serviceKey);
        var body = new VerifyPayload(userId, studentId, password);
        try {
            var response = restTemplate.postForEntity(
                    baseUrl + "/internal/v1/verify",
                    new HttpEntity<>(body, headers),
                    CampusVerifyResult.class);
            if (response.getBody() == null) {
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Campus auth returned empty body");
            }
            return response.getBody();
        } catch (HttpStatusCodeException ex) {
            throw mapError(ex);
        }
    }

    private ResponseStatusException mapError(HttpStatusCodeException ex) {
        var status = HttpStatus.resolve(ex.getStatusCode().value());
        var message = switch (status) {
            case UNAUTHORIZED -> "学号或密码不正确";
            case CONFLICT -> "该学号已绑定其他 FitLoop 账号";
            case LOCKED -> "教务账号已被禁用";
            case SERVICE_UNAVAILABLE -> "湘大教务系统暂时不可用，请稍后再试";
            default -> "校园认证失败，请稍后再试";
        };
        return new ResponseStatusException(status != null ? status : HttpStatus.BAD_GATEWAY, message);
    }

    record VerifyPayload(long userId, String studentId, String password) {
    }

    public record CampusVerifyResult(
            String studentId,
            String college,
            String className,
            String major,
            String grade
    ) {
    }

    public CampusScheduleSyncResult syncSchedule(long userId, String studentId, String password) {
        var headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.set("X-Campus-Auth-Service-Key", serviceKey);
        var body = new VerifyPayload(userId, studentId, password);
        try {
            var response = restTemplate.postForEntity(
                    baseUrl + "/internal/v1/sync-schedule",
                    new HttpEntity<>(body, headers),
                    CampusScheduleSyncResult.class);
            if (response.getBody() == null) {
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Campus auth returned empty body");
            }
            return response.getBody();
        } catch (HttpStatusCodeException ex) {
            throw mapError(ex);
        }
    }

    public record CampusScheduleSyncResult(
            String termYear,
            String termCode,
            List<SyncCourseRow> courses,
            List<SyncExamRow> exams
    ) {
    }

    public record SyncCourseRow(
            String name,
            String teacher,
            String classroom,
            int dayOfWeek,
            int startSection,
            int sectionCount,
            String weeks
    ) {
    }

    public record SyncExamRow(
            String name,
            String startTime,
            String endTime,
            String location,
            String examType
    ) {
    }
}
