import pytest
from pydantic import ValidationError

from fitloop_agent.schemas import AppealDecision, TrainingDay, TrainingPlanProposal


@pytest.mark.parametrize("duration_minutes", [5, 180])
def test_training_duration_accepts_inclusive_boundaries(duration_minutes: int) -> None:
    day = TrainingDay(
        day=1,
        session_type="synthetic easy run",
        duration_minutes=duration_minutes,
        intensity="LOW",
    )

    assert day.duration_minutes == duration_minutes


@pytest.mark.parametrize("duration_minutes", [4, 181])
def test_training_duration_rejects_values_outside_boundaries(
    duration_minutes: int,
) -> None:
    with pytest.raises(ValidationError):
        TrainingDay(
            day=1,
            session_type="synthetic easy run",
            duration_minutes=duration_minutes,
            intensity="LOW",
        )


@pytest.mark.parametrize("day_count", [1, 28])
def test_training_plan_accepts_inclusive_day_count_boundaries(day_count: int) -> None:
    proposal = TrainingPlanProposal(
        title="Synthetic boundary plan",
        goal="Validate the schema without real health data",
        days=[
            TrainingDay(
                day=index + 1,
                session_type="synthetic session",
                duration_minutes=30,
                intensity="MODERATE",
            )
            for index in range(day_count)
        ],
    )

    assert len(proposal.days) == day_count


@pytest.mark.parametrize("day_count", [0, 29])
def test_training_plan_rejects_day_counts_outside_boundaries(day_count: int) -> None:
    days = [
        TrainingDay(
            day=(index % 28) + 1,
            session_type="synthetic session",
            duration_minutes=30,
            intensity="MODERATE",
        )
        for index in range(day_count)
    ]

    with pytest.raises(ValidationError):
        TrainingPlanProposal(
            title="Synthetic invalid plan",
            goal="Validate the schema without real health data",
            days=days,
        )


def test_training_day_notes_can_include_weekday_and_time_window() -> None:
    day = TrainingDay(
        day=1,
        session_type="周三轻松慢跑",
        duration_minutes=30,
        intensity="LOW",
        notes="周三 19:30–21:00",
    )

    assert "周三" in day.session_type
    assert "19:30" in day.notes


@pytest.mark.parametrize("confidence", [0.0, 1.0])
def test_appeal_confidence_accepts_inclusive_boundaries(confidence: float) -> None:
    decision = AppealDecision(
        decision="NEED_MORE_INFO",
        confidence=confidence,
        evidence=["Synthetic evidence is intentionally incomplete."],
        reason="Request deterministic synthetic evidence.",
    )

    assert decision.confidence == confidence


@pytest.mark.parametrize("confidence", [-0.01, 1.01])
def test_appeal_confidence_rejects_values_outside_boundaries(confidence: float) -> None:
    with pytest.raises(ValidationError):
        AppealDecision(
            decision="NEED_MORE_INFO",
            confidence=confidence,
            evidence=["Synthetic evidence is intentionally incomplete."],
            reason="Request deterministic synthetic evidence.",
        )
