package com.fitloop.sport;

import com.fitloop.common.DomainEventOutbox;
import com.fitloop.sport.SportDtos.FinishSessionRequest;
import com.fitloop.sport.SportDtos.SportCursorPage;
import com.fitloop.sport.SportDtos.SportRecordResponse;
import com.fitloop.sport.SportDtos.StartSessionRequest;
import com.fitloop.sport.SportDtos.StartSessionResponse;
import com.fitloop.sport.SportDtos.TrackBatchRequest;
import com.fitloop.sport.SportDtos.TrackBatchResponse;
import com.fitloop.sport.SportDtos.TrackPointInput;
import com.fitloop.sport.SportDtos.TrackPointRequest;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.ObjectMapper;

@Service
public class SportService {
    private static final double DEFAULT_WEIGHT_KG = 60.0;
    private static final int MAX_BATCH_SIZE = 500;
    private static final String FINISH_OPERATION = "SPORT_FINISH";

    private static final Map<String, Set<String>> SPORT_CHECKIN_MODES = Map.of(
            "running", Set.of("gps", "timer", "manual", "sensor"),
            "walking", Set.of("gps", "timer", "manual", "sensor"),
            "cycling", Set.of("gps", "timer", "manual", "sensor"),
            "rope_skipping", Set.of("timer", "sensor", "count", "manual", "calorie"),
            "custom", Set.of("timer", "sensor", "count", "manual", "calorie", "gps", "photo")
    );

    private final SportRecordRepository records;
    private final SportTrackPointRepository trackPoints;
    private final IdempotencyRecordRepository idempotencyRecords;
    private final CalorieCalculator calorieCalculator;
    private final ObjectMapper objectMapper;
    private final ApplicationEventPublisher eventPublisher;
    private final DomainEventOutbox outbox;
    private final Path photoDir;

    public SportService(SportRecordRepository records, SportTrackPointRepository trackPoints,
                        IdempotencyRecordRepository idempotencyRecords, CalorieCalculator calorieCalculator,
                        ObjectMapper objectMapper, ApplicationEventPublisher eventPublisher,
                        DomainEventOutbox outbox,
                        @Value("${fitloop.upload.photo-dir:uploads/photos}") String photoDir) {
        this.records = records;
        this.trackPoints = trackPoints;
        this.idempotencyRecords = idempotencyRecords;
        this.calorieCalculator = calorieCalculator;
        this.objectMapper = objectMapper;
        this.eventPublisher = eventPublisher;
        this.outbox = outbox;
        this.photoDir = Paths.get(photoDir).toAbsolutePath().normalize();
    }

    @Transactional
    public StartSessionResponse start(Long userId, StartSessionRequest request) {
        Set<String> allowedModes = SPORT_CHECKIN_MODES.getOrDefault(
                request.sportType(), Set.of("timer", "manual"));
        if (!allowedModes.contains(request.checkinMode())) {
            throw new IllegalArgumentException("运动类型不支持该打卡方式");
        }
        SportRecord record = new SportRecord();
        record.setUserId(userId);
        record.setSessionId(UUID.randomUUID().toString());
        record.setSportType(request.sportType());
        record.setCheckinMode(request.checkinMode());
        record.setStartedAt(Instant.now());
        records.save(record);
        return new StartSessionResponse(record.getSessionId(), record.getStartedAt());
    }

    @Transactional
    public void appendTrack(Long userId, TrackPointRequest request) {
        SportRecord record = lockDraft(userId, request.sessionId());
        int nextSequence = trackPoints.findTopByRecordIdOrderBySequenceNoDesc(record.getRecordId())
                .map(point -> point.getSequenceNo() + 1).orElse(0);
        appendPoints(record, List.of(new TrackPointInput(nextSequence, request.lat(), request.lng(),
                request.accuracy(), request.timestamp())));
    }

    @Transactional
    public TrackBatchResponse appendTrackBatch(Long userId, String sessionId, TrackBatchRequest request) {
        SportRecord record = lockDraft(userId, sessionId);
        return appendPoints(record, request.points());
    }

    @Transactional
    public SportRecordResponse finish(Long userId, FinishSessionRequest request) {
        return finish(userId, request, null);
    }

    @Transactional
    public SportRecordResponse finish(Long userId, FinishSessionRequest request, String idempotencyKey) {
        validateIdempotencyKey(idempotencyKey);
        SportRecord record = records.findForUpdate(request.sessionId(), userId)
                .orElseThrow(() -> new IllegalArgumentException("打卡 session 不存在"));
        String requestHash = requestHash(request);
        if (idempotencyKey != null && !idempotencyKey.isBlank()) {
            var existing = idempotencyRecords.findByUserIdAndOperationAndIdempotencyKey(
                    userId, FINISH_OPERATION, idempotencyKey);
            if (existing.isPresent()) {
                if (!existing.get().getRequestHash().equals(requestHash)) {
                    throw new IllegalArgumentException("Idempotency-Key 已用于不同请求");
                }
                return SportRecordResponse.from(records.findById(existing.get().getResourceId())
                        .orElseThrow(() -> new IllegalStateException("Idempotent result is missing")));
            }
        }
        if (record.workoutStatus() != WorkoutStatus.DRAFT) {
            rememberIdempotency(userId, idempotencyKey, requestHash, record.getRecordId());
            return SportRecordResponse.from(record);
        }

        long duration = request.durationSeconds() != null
                ? request.durationSeconds()
                : Duration.between(record.getStartedAt(), Instant.now()).toSeconds();
        List<TrackPoint> points = loadTrack(record);
        TrackSummary summary = points.isEmpty() ? new TrackSummary(0.0, false, null) : summarize(points);
        double distance = request.distanceKm() != null ? request.distanceKm() : summary.distanceKm();
        double calorie = request.calorie() != null ? request.calorie()
                : calorieCalculator.estimate(record.getSportType(),
                request.weightKg() == null ? DEFAULT_WEIGHT_KG : request.weightKg(), duration);

        record.setDurationSeconds(Math.max(duration, 0));
        record.setDistanceKm(calorieCalculator.round(Math.max(distance, 0)));
        record.setCalorie(calorieCalculator.round(Math.max(calorie, 0)));
        record.setPhotoUrl(request.photoUrl());
        record.setNote(request.note());
        record.setEndedAt(Instant.now());
        record.finishAs(summary.abnormal() ? WorkoutStatus.ABNORMAL : WorkoutStatus.VALID);
        record.setAbnormalReason(summary.abnormalReason());

        if (record.workoutStatus() == WorkoutStatus.VALID) {
            WorkoutCompletedEvent event = new WorkoutCompletedEvent(record.getRecordId(), record.getUserId(),
                    record.getDurationSeconds(), record.getDistanceKm(), record.getCalorie(), Instant.now());
            eventPublisher.publishEvent(event);
            outbox.append("WORKOUT_COMPLETED", record.getRecordId().toString(), event);
        }
        rememberIdempotency(userId, idempotencyKey, requestHash, record.getRecordId());
        return SportRecordResponse.from(record);
    }

    public String savePhoto(Long userId, MultipartFile file) {
        if (file.isEmpty()) throw new IllegalArgumentException("文件不能为空");
        String contentType = file.getContentType();
        if (contentType == null || !contentType.startsWith("image/")) {
            throw new IllegalArgumentException("只能上传图片文件");
        }
        if (file.getSize() > 10 * 1024 * 1024) throw new IllegalArgumentException("文件不能超过 10MB");
        try {
            Files.createDirectories(photoDir);
            String extension = switch (contentType.toLowerCase(Locale.ROOT)) {
                case "image/jpeg", "image/jpg" -> ".jpg";
                case "image/png" -> ".png";
                case "image/gif" -> ".gif";
                case "image/webp" -> ".webp";
                default -> ".img";
            };
            String filename = "photo_" + userId + "_" + Instant.now().toEpochMilli() + extension;
            Files.copy(file.getInputStream(), photoDir.resolve(filename), StandardCopyOption.REPLACE_EXISTING);
            return "/uploads/photos/" + filename;
        } catch (IOException ex) {
            throw new IllegalArgumentException("照片上传失败: " + ex.getMessage());
        }
    }

    @Transactional(readOnly = true)
    public List<SportRecordResponse> list(Long userId) {
        return records.findTop50ByUserIdOrderByStartedAtDesc(userId).stream()
                .map(SportRecordResponse::from).toList();
    }

    @Transactional(readOnly = true)
    public SportCursorPage list(Long userId, Long cursor, int requestedSize) {
        int size = Math.max(1, Math.min(requestedSize, 100));
        List<SportRecord> page = records.findPageBefore(userId, cursor, PageRequest.of(0, size + 1));
        boolean hasMore = page.size() > size;
        List<SportRecord> visible = hasMore ? page.subList(0, size) : page;
        Long nextCursor = hasMore ? visible.getLast().getRecordId() : null;
        return new SportCursorPage(visible.stream().map(SportRecordResponse::from).toList(), nextCursor, hasMore);
    }

    private SportRecord lockDraft(Long userId, String sessionId) {
        SportRecord record = records.findForUpdate(sessionId, userId)
                .orElseThrow(() -> new IllegalArgumentException("打卡 session 不存在"));
        if (record.workoutStatus() != WorkoutStatus.DRAFT) {
            throw new IllegalArgumentException("打卡已结束，不能继续上传轨迹");
        }
        return record;
    }

    private TrackBatchResponse appendPoints(SportRecord record, List<TrackPointInput> inputs) {
        if (inputs == null || inputs.isEmpty()) return new TrackBatchResponse(0, 0, -1);
        if (inputs.size() > MAX_BATCH_SIZE) throw new IllegalArgumentException("单批轨迹点不能超过 500 个");
        Map<Integer, TrackPointInput> unique = new LinkedHashMap<>();
        for (TrackPointInput input : inputs) {
            validatePoint(input);
            unique.putIfAbsent(input.sequenceNo(), input);
        }
        Set<Integer> existing = new HashSet<>(trackPoints.findExistingSequences(
                record.getRecordId(), unique.keySet()));
        List<SportTrackPoint> accepted = unique.values().stream()
                .filter(input -> !existing.contains(input.sequenceNo()))
                .map(input -> toEntity(record.getRecordId(), input)).toList();
        trackPoints.saveAll(accepted);
        int lastSequence = unique.keySet().stream().mapToInt(Integer::intValue).max().orElse(-1);
        return new TrackBatchResponse(accepted.size(), inputs.size() - accepted.size(), lastSequence);
    }

    private void validatePoint(TrackPointInput point) {
        if (point.sequenceNo() < 0) throw new IllegalArgumentException("sequenceNo 不能小于 0");
        if (point.lat() < -90 || point.lat() > 90 || point.lng() < -180 || point.lng() > 180) {
            throw new IllegalArgumentException("轨迹坐标不合法");
        }
    }

    private SportTrackPoint toEntity(Long recordId, TrackPointInput input) {
        SportTrackPoint point = new SportTrackPoint();
        point.setRecordId(recordId);
        point.setSequenceNo(input.sequenceNo());
        point.setLatitude(input.lat());
        point.setLongitude(input.lng());
        point.setAccuracy(input.accuracy() == null ? 0 : input.accuracy());
        point.setRecordedAt(input.timestamp());
        return point;
    }

    private List<TrackPoint> loadTrack(SportRecord record) {
        List<SportTrackPoint> stored = trackPoints.findByRecordIdOrderBySequenceNoAsc(record.getRecordId());
        if (!stored.isEmpty()) {
            return stored.stream().map(point -> new TrackPoint(point.getLatitude(), point.getLongitude(),
                    point.getAccuracy(), point.getRecordedAt())).toList();
        }
        return readLegacyTrack(record);
    }

    private List<TrackPoint> readLegacyTrack(SportRecord record) {
        try {
            if (record.getTrackJson() == null || record.getTrackJson().isBlank()) return new ArrayList<>();
            List<Map<String, Object>> raw = objectMapper.readValue(record.getTrackJson(), new TypeReference<>() { });
            return raw.stream().map(this::toPoint).toList();
        } catch (Exception ex) {
            throw new IllegalArgumentException("轨迹数据格式异常");
        }
    }

    private TrackSummary summarize(List<TrackPoint> points) {
        List<TrackPoint> valid = points.stream().filter(point -> point.accuracy() <= 100.0)
                .sorted(Comparator.comparing(TrackPoint::timestamp)).toList();
        double meters = 0;
        boolean abnormal = false;
        for (int i = 1; i < valid.size(); i++) {
            TrackPoint previous = valid.get(i - 1);
            TrackPoint current = valid.get(i);
            double segment = haversineMeters(previous.lat(), previous.lng(), current.lat(), current.lng());
            long seconds = Math.max(Duration.between(previous.timestamp(), current.timestamp()).toSeconds(), 1);
            if (segment / seconds > 8.0) abnormal = true;
            meters += segment;
        }
        return new TrackSummary(meters / 1000.0, abnormal, abnormal ? "速度异常或轨迹跳变过大" : null);
    }

    private TrackPoint toPoint(Map<String, Object> raw) {
        return new TrackPoint(Double.parseDouble(raw.get("lat").toString()),
                Double.parseDouble(raw.get("lng").toString()),
                Double.parseDouble(raw.get("accuracy").toString()), Instant.parse(raw.get("timestamp").toString()));
    }

    private double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
        double radius = 6_371_000;
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        return radius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    private void validateIdempotencyKey(String key) {
        if (key != null && !key.isBlank() && (key.length() < 8 || key.length() > 128)) {
            throw new IllegalArgumentException("Idempotency-Key 长度必须为 8 到 128 个字符");
        }
    }

    private void rememberIdempotency(Long userId, String key, String requestHash, Long recordId) {
        if (key == null || key.isBlank()) return;
        IdempotencyRecord value = new IdempotencyRecord();
        value.setUserId(userId);
        value.setOperation(FINISH_OPERATION);
        value.setIdempotencyKey(key);
        value.setRequestHash(requestHash);
        value.setResourceId(recordId);
        idempotencyRecords.save(value);
    }

    private String requestHash(FinishSessionRequest request) {
        try {
            byte[] json = objectMapper.writeValueAsBytes(request);
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(json));
        } catch (Exception ex) {
            throw new IllegalStateException("Failed to hash finish request", ex);
        }
    }

    private record TrackPoint(double lat, double lng, double accuracy, Instant timestamp) { }
    private record TrackSummary(double distanceKm, boolean abnormal, String abnormalReason) { }
}
