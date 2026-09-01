from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from xtu_ems.common.exception import (
    AccountDisabledException,
    InvalidUsernameOrPasswordException,
    ServiceUnavailableException,
    ZfAccountNotFoundException,
)
from xtu_ems.common.sess import HttpSessionHolder
from xtu_ems.common.term import get_term_id, get_term_year
from xtu_ems.zf_ems.courses import get_courses
from xtu_ems.zf_ems.exams import get_exams
from xtu_ems.zf_ems.login import sso_auth as zf_sso_auth
from xtu_ems.zf_sso.login import login as sso_login

_DAY_TO_NUMBER = {
    "Monday": 1,
    "Tuesday": 2,
    "Wednesday": 3,
    "Thursday": 4,
    "Friday": 5,
    "Saturday": 6,
    "Sunday": 7,
}


@dataclass(frozen=True)
class ScheduleCourse:
    name: str
    teacher: str
    classroom: str
    day_of_week: int
    start_section: int
    section_count: int
    weeks: str


@dataclass(frozen=True)
class ScheduleExam:
    name: str
    start_time: str
    end_time: str | None
    location: str
    exam_type: str


@dataclass(frozen=True)
class SyncedSchedule:
    term_year: str
    term_code: str
    courses: list[ScheduleCourse]
    exams: list[ScheduleExam]


def _iso(value: datetime | str) -> str:
    if isinstance(value, datetime):
        return value.isoformat(timespec="minutes")
    return str(value)


async def sync_xtu_schedule(student_id: str, password: str) -> SyncedSchedule:
    session_holder = HttpSessionHolder()
    try:
        session_holder = await sso_login(student_id, password)
        session_holder = await zf_sso_auth(session_holder)
        course_list = await get_courses(session_holder)
        exam_list = await get_exams(session_holder)
    except InvalidUsernameOrPasswordException as error:
        raise ValueError("invalid_credentials") from error
    except AccountDisabledException as error:
        raise ValueError("account_disabled") from error
    except (ServiceUnavailableException, ZfAccountNotFoundException) as error:
        raise ValueError("service_unavailable") from error

    today = datetime.now().date()
    term_year = str(get_term_year(today))
    term_code = str(get_term_id(today))

    courses = [
        ScheduleCourse(
            name=course.name,
            teacher=course.teacher,
            classroom=course.classroom,
            day_of_week=_DAY_TO_NUMBER.get(course.day, 1),
            start_section=course.start_time,
            section_count=course.duration,
            weeks=course.weeks,
        )
        for course in course_list.courses
    ]
    exams = [
        ScheduleExam(
            name=exam.name,
            start_time=_iso(exam.start_time),
            end_time=_iso(exam.end_time) if exam.end_time else None,
            location=exam.location,
            exam_type=exam.type,
        )
        for exam in exam_list.exams
    ]
    return SyncedSchedule(
        term_year=term_year,
        term_code=term_code,
        courses=courses,
        exams=exams,
    )
