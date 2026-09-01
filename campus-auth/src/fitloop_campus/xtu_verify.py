from __future__ import annotations

from dataclasses import dataclass

from xtu_ems.common.exception import (
    AccountDisabledException,
    InvalidUsernameOrPasswordException,
    ServiceUnavailableException,
    ZfAccountNotFoundException,
)
from xtu_ems.common.sess import HttpSessionHolder
from xtu_ems.zf_ems.login import sso_auth as zf_sso_auth
from xtu_ems.zf_ems.personal_info import get_student_info
from xtu_ems.zf_sso.login import login as sso_login


@dataclass(frozen=True)
class VerifiedStudent:
    student_id: str
    college: str
    class_: str
    major: str | None
    grade: str | None


def _grade_from_entrance_day(entrance_day: str) -> str | None:
    digits = "".join(ch for ch in entrance_day if ch.isdigit())
    if len(digits) >= 4:
        return f"{digits[:4]}级"
    return None


async def verify_xtu_student(student_id: str, password: str) -> VerifiedStudent:
    session_holder = HttpSessionHolder()
    try:
        session_holder = await sso_login(student_id, password)
        session_holder = await zf_sso_auth(session_holder)
        info = await get_student_info(session_holder)
    except InvalidUsernameOrPasswordException as error:
        raise ValueError("invalid_credentials") from error
    except AccountDisabledException as error:
        raise ValueError("account_disabled") from error
    except (ServiceUnavailableException, ZfAccountNotFoundException) as error:
        raise ValueError("service_unavailable") from error

    return VerifiedStudent(
        student_id=info.student_id,
        college=info.college,
        class_=info.class_,
        major=info.major,
        grade=_grade_from_entrance_day(info.entrance_day),
    )
