package com.fitloop.sport;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fitloop.sport.SportDtos.FinishSessionRequest;
import com.fitloop.sport.SportDtos.SportRecordResponse;
import com.fitloop.sport.SportDtos.StartSessionRequest;
import com.fitloop.sport.SportDtos.StartSessionResponse;
import com.fitloop.sport.SportDtos.TrackPointRequest;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class SportService {
    private static final double DEFAULT_WEIGHT_KG = 60.0;

    private final SportRecordRepository records;
    private final CalorieCalculator calorieCalculator;
    private final ObjectMapper objectMapper;

    public SportService(SportRecordRepository records, CalorieCalculator calorieCalculator, ObjectMapper objectMapper) {
        this.records = records;
        this.calorieCalculator = calorieCalculator;
        this.objectMapper = objectMapper;
    }

    @Transactional
    public StartSessionResponse start(Long userId, StartSessionRequest request) {
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
        SportRecord record = records.findBySessionIdAndUserId(request.sessionId(), userId)
                .orElseThrow(() -> new IllegalArgumentException("打卡 session 不存在"));
        if (record.getStatus() != SportRecord.STATUS_DRAFT) {
            throw new IllegalArgumentException("打卡已结束，不能继续上传轨迹");
        }
        List<Map<String, Object>> points = readTrack(record);
        points.add(Map.of(
                "lat", request.lat(),
                "lng", request.lng(),
                "accuracy", request.accuracy() == null ? 0 : request.accuracy(),
                "timestamp", request.timestamp().toString()
        ));
        writeTrack(record, points);
    }

    @Transactional
    public SportRecordResponse finish(Long userId, FinishSessionRequest request) {
        SportRecord record = records.findBySessionIdAndUserId(request.sessionId(), userId)
                .orElseThrow(() -> new IllegalArgumentException("打卡 session 不存在"));
        if (record.getStatus() != SportRecord.STATUS_DRAFT) {
            return SportRecordResponse.from(record);
        }
        long duration = request.durationSeconds() != null
                ? request.durationSeconds()
                : Duration.between(record.getStartedAt(), Instant.now()).toSeconds();
        TrackSummary summary = summarize(readTrack(record));
        double distance = request.distanceKm() != null ? request.distanceKm() : summary.distanceKm();
        double calorie = request.calorie() != null
                ? request.calorie()
                : calorieCalculator.estimate(record.getSportType(),
                request.weightKg() == null ? DEFAULT_WEIGHT_KG : request.weightKg(), duration);

        record.setDurationSeconds(Math.max(duration, 0));
        record.setDistanceKm(calorieCalculator.round(Math.max(distance, 0)));
        record.setCalorie(calorieCalculator.round(Math.max(calorie, 0)));
        record.setPhotoUrl(request.photoUrl());
        record.setEndedAt(Instant.now());
        record.setStatus(summary.abnormal() ? SportRecord.STATUS_ABNORMAL : SportRecord.STATUS_VALID);
        record.setAbnormalReason(summary.abnormalReason());
        return SportRecordResponse.from(record);
    }

    @Transactional(readOnly = true)
    public List<SportRecordResponse> list(Long userId) {
        return records.findTop50ByUserIdOrderByStartedAtDesc(userId)
                .stream()
                .map(SportRecordResponse::from)
                .toList();
    }

    private List<Map<String, Object>> readTrack(SportRecord record) {
        try {
            if (record.getTrackJson() == null || record.getTrackJson().isBlank()) {
                return new ArrayList<>();
            }
            return objectMapper.readValue(record.getTrackJson(), new TypeReference<>() {
            });
        } catch (Exception ex) {
            throw new IllegalArgumentException("轨迹数据格式异常");
        }
    }

    private void writeTrack(SportRecord record, List<Map<String, Object>> points) {
        try {
            record.setTrackJson(objectMapper.writeValueAsString(points));
        } catch (Exception ex) {
            throw new IllegalArgumentException("轨迹数据保存失败");
        }
    }

    private TrackSummary summarize(List<Map<String, Object>> points) {
        List<TrackPoint> validPoints = points.stream()
                .map(this::toPoint)
                .filter(point -> point.accuracy() <= 100.0)
                .sorted(Comparator.comparing(TrackPoint::timestamp))
                .toList();
        double meters = 0;
        boolean abnormal = false;
        for (int i = 1; i < validPoints.size(); i++) {
            TrackPoint previous = validPoints.get(i - 1);
            TrackPoint current = validPoints.get(i);
            double segmentMeters = haversineMeters(previous.lat(), previous.lng(), current.lat(), current.lng());
            long seconds = Math.max(Duration.between(previous.timestamp(), current.timestamp()).toSeconds(), 1);
            double speed = segmentMeters / seconds;
            if (speed > 8.0) {
                abnormal = true;
            }
            meters += segmentMeters;
        }
        return new TrackSummary(meters / 1000.0, abnormal, abnormal ? "速度异常或轨迹跳变过大" : null);
    }

    private TrackPoint toPoint(Map<String, Object> raw) {
        return new TrackPoint(
                Double.parseDouble(raw.get("lat").toString()),
                Double.parseDouble(raw.get("lng").toString()),
                Double.parseDouble(raw.get("accuracy").toString()),
                Instant.parse(raw.get("timestamp").toString())
        );
    }

    private double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
        double radius = 6371000;
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        return radius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    private record TrackPoint(double lat, double lng, double accuracy, Instant timestamp) {
    }

    private record TrackSummary(double distanceKm, boolean abnormal, String abnormalReason) {
    }
}
