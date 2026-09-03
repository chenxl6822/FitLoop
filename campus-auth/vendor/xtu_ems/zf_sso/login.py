import logging

from aiohttp import ClientSession

from xtu_ems.common.encrypt import rsa_encrypt
from xtu_ems.common.exception import *
from xtu_ems.common.sess import HttpSessionHolder as SessionHolder
from xtu_ems.common.urls import normalize_campus_url, url_matches_prefix
from xtu_ems.zf_sso.config import key_url, login_url, login_success_url_prefix, modify_password_url_prefix

logger = logging.getLogger(__name__)


async def login(username: str, password: str) -> SessionHolder:
    """
    登录并返回用户凭证

    一共有四次请求：

    获取RSA公钥 --> 获取execution值 --> 提交登录表单，获取ticket_url --> 访问ticket_url

    :param username: 用户名
    :param password: 密码
    :return: 包含登录后cookies的CookieJar对象

    :raises ServiceUnavailableException: 当服务不可用时抛出, 如无法获取RSA公钥或登录页面
    :raises InvalidUsernameOrPasswordException: 当用户名或密码无效时抛出
    :raises AccountDisabledException: 当账号被禁用时抛出

    """
    async with ClientSession() as session:
        async with session.get(key_url) as response:
            if response.status != 200:
                raise ServiceUnavailableException("CAS Key Service")
            key_pair = await response.json()
            key_pair = {
                "modulus": int(key_pair["modulus"], 16),
                "public_exponent": int(key_pair["exponent"], 16),
            }
        async with session.get(login_url) as response:
            if response.status != 200:
                raise ServiceUnavailableException(
                    "CAS Login Page", "Cannot access login page"
                )
            # 从html中提取execution值，一个input标签，name="execution"，value="xxxx"
            html = await response.text()
            start_index = html.index('name="execution" value="') + len(
                'name="execution" value="'
            )
            end_index = html.index('"', start_index)
            if not (0 < start_index < end_index):
                raise ServiceUnavailableException(
                    "CAS Login Page", "Cannot find execution value in login page"
                )
            execution = html[start_index:end_index]
        encrypted_password = rsa_encrypt(
            key_pair["public_exponent"], key_pair["modulus"], password
        )
        payload = {
            "username": username,
            "password": encrypted_password,
            "execution": execution,
            "_eventId": "submit",
            "authcode": "",
            "mobileCode": "",
        }
        # 执行登录请求
        async with session.post(
            login_url,
            data=payload,
            allow_redirects=False,
        ) as response:
            if response.status == 302 and "Location" in response.headers:
                raw_redirect = response.headers["Location"] or ""
                # CAS may return relative paths or absolute URLs with :443.
                redirect_url = normalize_campus_url(raw_redirect, base=login_url)
                logger.debug(
                    "Redirect Location raw=%s normalized=%s", raw_redirect, redirect_url
                )
            elif response.status == 200:
                raise InvalidUsernameOrPasswordException(username)
            elif response.status == 403:
                logger.error(
                    f"Login failed: status code {response.status}, headers {response.headers}"
                )
                raise AccountDisabledException(username)
            else:
                logger.error(
                    f"Login failed: status code {response.status}, headers {response.headers}"
                )
                raise ServiceUnavailableException("login failed")
        # 判断重定向URL（容忍 :443 / 相对路径等跳转地址变化）
        if url_matches_prefix(redirect_url, modify_password_url_prefix, base=login_url):
            raise UninitializedAccountException(username, "Please change password first.")
        elif not url_matches_prefix(redirect_url, login_success_url_prefix, base=login_url):
            logger.error("Unexpected CAS ticket redirect: %s", redirect_url)
            raise ServiceUnavailableException("ticket URL not found")
        # 访问ticket_url，完成登录
        async with session.get(
            redirect_url,
        ) as response:
            if response.status == 200:
                logger.info("Login successful.")
                return SessionHolder.from_aiohttp_session(session)
            else:
                logger.error("Failed to access ticket URL.")
                raise ServiceUnavailableException("login failed")
