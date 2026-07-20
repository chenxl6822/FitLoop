from dataclasses import dataclass
from typing import Any, Literal

from pydantic import BaseModel, Field


class TrainingDay(BaseModel):
    day: int = Field(ge=1, le=28)
    session_type: str = Field(min_length=1, max_length=80)
    duration_minutes: int = Field(ge=5, le=180)
    intensity: Literal["LOW", "MODERATE", "HIGH"]
    notes: str = Field(default="", max_length=300)


class TrainingPlanProposal(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    goal: str = Field(min_length=1, max_length=300)
    days: list[TrainingDay] = Field(min_length=1, max_length=28)


class CoachOutput(BaseModel):
    answer: str = Field(min_length=1, max_length=3000)
    rationale: list[str] = Field(default_factory=list, max_length=8)
    safety_notices: list[str] = Field(default_factory=list, max_length=5)
    proposal: TrainingPlanProposal | None = None


class AppealDecision(BaseModel):
    decision: Literal["APPROVE", "REJECT", "NEED_MORE_INFO"]
    confidence: float = Field(ge=0, le=1)
    evidence: list[str] = Field(min_length=1, max_length=12)
    risk_flags: list[str] = Field(default_factory=list, max_length=12)
    reason: str = Field(min_length=1, max_length=3000)


class ClaimResponse(BaseModel):
    runId: str
    type: Literal["COACH", "APPEAL_REVIEW"]
    inputJson: str
    subjectUserId: int
    subjectResourceId: int | None
    traceId: str


@dataclass(slots=True)
class AgentContext:
    run_id: str
    subject_user_id: int
    subject_resource_id: int | None
    run_type: str
    trace_id: str
    token: str
    backend: Any


@dataclass(slots=True)
class UsageSummary:
    input_tokens: int = 0
    output_tokens: int = 0
    cost_micros: int = 0
