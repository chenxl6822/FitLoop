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
