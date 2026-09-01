from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict

logger = logging.getLogger("fitloop.campus")


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="CAMPUS_", extra="ignore")

    service_key: str = Field(min_length=32)
    host: str = "0.0.0.0"
    port: int = 8091


class VerifyRequest(BaseModel):
    userId: int
    studentId: str = Field(min_length=4, max_length=32)
    password: str = Field(min_length=1, max_length=128)


class VerifyResponse(BaseModel):
    studentId: str
    college: str
    className: str
    major: str | None = None
    grade: str | None = None


class ScheduleCoursePayload(BaseModel):
    name: str
    teacher: str = ""
    classroom: str = ""
    dayOfWeek: int
    startSection: int
    sectionCount: int
    weeks: str = ""


class ScheduleExamPayload(BaseModel):
    name: str
    startTime: str
    endTime: str | None = None
    location: str = ""
    examType: str = "考试"


class SyncScheduleResponse(BaseModel):
    termYear: str
    termCode: str
    courses: list[ScheduleCoursePayload]
    exams: list[ScheduleExamPayload]


settings = Settings()


@asynccontextmanager
async def lifespan(_: FastAPI):
    logging.basicConfig(level=logging.INFO)
    yield


app = FastAPI(title="FitLoop Campus Auth", docs_url=None, redoc_url=None, lifespan=lifespan)


def _require_service_key(supplied: str | None) -> None:
    if not supplied or supplied != settings.service_key:
        raise HTTPException(status_code=401, detail="Invalid campus auth service credential")


@app.get("/ready")
async def ready() -> dict[str, str]:
    return {"status": "UP"}


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "UP"}


@app.post("/internal/v1/verify", response_model=VerifyResponse)
async def verify(
    request: VerifyRequest,
    x_campus_auth_service_key: str | None = Header(default=None, alias="X-Campus-Auth-Service-Key"),
) -> VerifyResponse:
    _require_service_key(x_campus_auth_service_key)
    from .xtu_verify import verify_xtu_student

    try:
        profile = await verify_xtu_student(request.studentId.strip(), request.password)
    except ValueError as error:
        message = str(error)
        if message == "invalid_credentials":
            raise HTTPException(status_code=401, detail="invalid credentials") from error
        if message == "account_disabled":
            raise HTTPException(status_code=423, detail="account disabled") from error
        if message == "service_unavailable":
            raise HTTPException(status_code=503, detail="xtu ems unavailable") from error
        raise HTTPException(status_code=400, detail=message) from error

    logger.info("Verified XTU student for userId=%s college=%s", request.userId, profile.college)
    return VerifyResponse(
        studentId=profile.student_id,
        college=profile.college,
        className=profile.class_,
        major=profile.major,
        grade=profile.grade,
    )


@app.post("/internal/v1/sync-schedule", response_model=SyncScheduleResponse)
async def sync_schedule(
    request: VerifyRequest,
    x_campus_auth_service_key: str | None = Header(default=None, alias="X-Campus-Auth-Service-Key"),
) -> SyncScheduleResponse:
    _require_service_key(x_campus_auth_service_key)
    from .xtu_schedule import sync_xtu_schedule

    try:
        schedule = await sync_xtu_schedule(request.studentId.strip(), request.password)
    except ValueError as error:
        message = str(error)
        if message == "invalid_credentials":
            raise HTTPException(status_code=401, detail="invalid credentials") from error
        if message == "account_disabled":
            raise HTTPException(status_code=423, detail="account disabled") from error
        if message == "service_unavailable":
            raise HTTPException(status_code=503, detail="xtu ems unavailable") from error
        raise HTTPException(status_code=400, detail=message) from error

    logger.info(
        "Synced XTU schedule for userId=%s courses=%s exams=%s",
        request.userId,
        len(schedule.courses),
        len(schedule.exams),
    )
    return SyncScheduleResponse(
        termYear=schedule.term_year,
        termCode=schedule.term_code,
        courses=[
            ScheduleCoursePayload(
                name=course.name,
                teacher=course.teacher,
                classroom=course.classroom,
                dayOfWeek=course.day_of_week,
                startSection=course.start_section,
                sectionCount=course.section_count,
                weeks=course.weeks,
            )
            for course in schedule.courses
        ],
        exams=[
            ScheduleExamPayload(
                name=exam.name,
                startTime=exam.start_time,
                endTime=exam.end_time,
                location=exam.location,
                examType=exam.exam_type,
            )
            for exam in schedule.exams
        ],
    )
