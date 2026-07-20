package com.fitloop.agent;

import com.fitloop.agent.AgentDtos.CompletionResponse;
import com.fitloop.agent.AgentDtos.ToolContext;
import com.fitloop.agent.AgentDtos.TrainingLoadResponse;
import com.fitloop.agent.AgentToolDtos.AppealEvidenceResponse;
import com.fitloop.agent.AgentToolDtos.GoalToolResponse;
import com.fitloop.agent.AgentToolDtos.HealthPoint;
import com.fitloop.agent.AgentToolDtos.HealthTrendResponse;
import com.fitloop.agent.AgentToolDtos.RuleEvidence;
import com.fitloop.agent.AgentToolDtos.RuleToolResponse;
import com.fitloop.agent.AgentToolDtos.WorkoutSummary;
import com.fitloop.agent.AgentToolDtos.WorkoutToolResponse;
import com.fitloop.appeal.Appeal;
import com.fitloop.appeal.AppealRepository;
import com.fitloop.sport.SportRecord;
import com.fitloop.sport.SportRecordRepository;
import com.fitloop.stats.HealthDataRepository;
import com.fitloop.target.TargetService;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/internal/v1/agent-tools")
public class AgentToolController {
    private static final ZoneId BUSINESS_ZONE = ZoneId.of("Asia/Shanghai");
    private final AgentGatewayService gateway;
    private final TargetService targets;
    private final SportRecordRepository workouts;
    private final HealthDataRepository health;
    private final AppealRepository appeals;

    public AgentToolController(AgentGatewayService gateway, TargetService targets,
                               SportRecordRepository workouts, HealthDataRepository health,
                               AppealRepository appeals) {
        this.gateway = gateway;
        this.targets = targets;
        this.workouts = workouts;
        this.health = health;
        this.appeals = appeals;
    }

    @GetMapping("/coach/goals")
    public GoalToolResponse goals(Authentication authentication) {
        ToolContext context = coachContext(authentication);
        return execute(context, "get_user_goals", Map.of(),
                () -> new GoalToolResponse(targets.current(context.subjectUserId())));
    }

    @GetMapping("/coach/workouts")
    public WorkoutToolResponse recentWorkouts(Authentication authentication) {
        ToolContext context = coachContext(authentication);
        return execute(context, "get_recent_workouts", Map.of("limit", 10), () -> {
            List<WorkoutSummary> result = workouts.findTop50ByUserIdOrderByStartedAtDesc(context.subjectUserId())
                    .stream().limit(10).map(this::summary).toList();
            return new WorkoutToolResponse(result);
        });
    }

    @GetMapping("/coach/health-trends")
    public HealthTrendResponse healthTrends(Authentication authentication) {
        ToolContext context = coachContext(authentication);
        return execute(context, "get_health_trends", Map.of("days", 30), () -> {
            LocalDate end = LocalDate.now(BUSINESS_ZONE);
            List<HealthPoint> points = health.findByUserIdAndDataDateBetweenOrderByDataDateAsc(
                            context.subjectUserId(), end.minusDays(29), end)
                    .stream().map(value -> new HealthPoint(value.getDataDate(), value.getWeightKg(), value.getSleepHours()))
                    .toList();
            return new HealthTrendResponse(points);
        });
    }

    @GetMapping("/coach/goal-completion")
    public List<CompletionResponse> goalCompletion(Authentication authentication) {
        ToolContext context = coachContext(authentication);
        return execute(context, "get_goal_completion", Map.of(),
                () -> targets.current(context.subjectUserId()).stream()
                        .map(target -> new CompletionResponse(target.metric(), target.targetValue(),
                                target.completedValue(), target.progress() / 100.0))
                        .toList());
    }

    @GetMapping("/coach/training-load")
    public TrainingLoadResponse trainingLoad(Authentication authentication) {
        ToolContext context = coachContext(authentication);
        return execute(context, "calculate_training_load", Map.of("days", 28), () -> {
            Instant end = Instant.now();
            Instant start = end.minusSeconds(28L * 24 * 60 * 60);
            List<SportRecord> records = workouts.findValidInRange(
                    context.subjectUserId(), SportRecord.STATUS_VALID, start, end);
            double distance = records.stream().mapToDouble(SportRecord::getDistanceKm).sum();
            long seconds = records.stream().mapToLong(SportRecord::getDurationSeconds).sum();
            double acuteLoad = records.stream().filter(record -> record.getStartedAt() != null
                            && record.getStartedAt().isAfter(end.minusSeconds(7L * 24 * 60 * 60)))
                    .mapToDouble(record -> record.getDurationSeconds() / 60.0).sum();
            String assessment = acuteLoad > 420 ? "HIGH" : acuteLoad > 180 ? "MODERATE" : "LOW";
            return new TrainingLoadResponse(records.size(), round(distance), round(seconds / 3600.0),
                    round(acuteLoad), assessment);
        });
    }

    @GetMapping("/appeals/{appealId}/evidence")
    public AppealEvidenceResponse appealEvidence(@PathVariable Long appealId, Authentication authentication) {
        ToolContext context = appealContext(authentication, appealId);
        return execute(context, "get_appeal_evidence", Map.of("appealId", appealId), () -> {
            Appeal appeal = appeals.findById(appealId)
                    .orElseThrow(() -> new IllegalArgumentException("Appeal does not exist"));
            SportRecord record = workouts.findById(appeal.getRecordId())
                    .orElseThrow(() -> new IllegalArgumentException("Workout does not exist"));
            List<WorkoutSummary> history = workouts.findTop50ByUserIdOrderByStartedAtDesc(appeal.getUserId())
                    .stream().filter(item -> !item.getRecordId().equals(record.getRecordId()))
                    .limit(10).map(this::summary).toList();
            double hours = record.getDurationSeconds() / 3600.0;
            return new AppealEvidenceResponse(appealId, appeal.getReason(), appeal.getEvidenceUrl(),
                    appeal.getStatus(), summary(record), hours <= 0 ? 0 : round(record.getDistanceKm() / hours), history);
        });
    }

    @GetMapping("/appeals/{appealId}/rules")
    public RuleToolResponse anomalyRules(@PathVariable Long appealId, Authentication authentication) {
        ToolContext context = appealContext(authentication, appealId);
        return execute(context, "get_anomaly_rules", Map.of("appealId", appealId), () ->
                new RuleToolResponse(List.of(
                        new RuleEvidence("SPEED_OUTLIER", "Average speed exceeds the sport safety threshold", "sport-specific"),
                        new RuleEvidence("DURATION_INVALID", "Duration is absent or outside a plausible range", "> 0 seconds"),
                        new RuleEvidence("DISTANCE_INVALID", "Distance is absent or negative", ">= 0 km"),
                        new RuleEvidence("DUPLICATE_SESSION", "The same client session was already settled", "unique sessionId"))));
    }

    private ToolContext coachContext(Authentication authentication) {
        ToolContext context = context(authentication);
        if (context.type() != AgentRunType.COACH) {
            throw new org.springframework.security.access.AccessDeniedException("Tool is restricted to coach runs");
        }
        return context;
    }

    private ToolContext appealContext(Authentication authentication, Long appealId) {
        ToolContext context = context(authentication);
        if (context.type() != AgentRunType.APPEAL_REVIEW || !appealId.equals(context.subjectResourceId())) {
            throw new org.springframework.security.access.AccessDeniedException("Tool is restricted to this appeal");
        }
        return context;
    }

    private ToolContext context(Authentication authentication) {
        if (authentication == null || !(authentication.getDetails() instanceof ToolContext context)) {
            throw new org.springframework.security.access.AccessDeniedException("Missing agent delegation context");
        }
        return context;
    }

    private WorkoutSummary summary(SportRecord record) {
        return new WorkoutSummary(record.getRecordId(), record.getSportType(), record.getDurationSeconds(),
                round(record.getDistanceKm()), round(record.getCalorie()), record.getStatus(),
                record.getAbnormalReason(), record.getStartedAt());
    }

    @SuppressWarnings("unchecked")
    private <T> T execute(ToolContext context, String toolName, Map<String, Object> arguments,
                          java.util.function.Supplier<T> invocation) {
        return (T) gateway.executeTool(context, toolName, arguments, invocation::get);
    }

    private double round(double value) { return Math.round(value * 100.0) / 100.0; }
}
