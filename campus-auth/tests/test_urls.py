from xtu_ems.common.urls import normalize_campus_url, url_matches_prefix


def test_normalize_strips_https_default_port():
    assert (
        normalize_campus_url(
            "https://portal2020.xtu.edu.cn:443/application-center?ticket=ST-1"
        )
        == "https://portal2020.xtu.edu.cn/application-center?ticket=ST-1"
    )


def test_normalize_resolves_relative_location():
    assert (
        normalize_campus_url(
            "/application-center?ticket=ST-1",
            base="https://portal2020.xtu.edu.cn/cas/login?service=x",
        )
        == "https://portal2020.xtu.edu.cn/application-center?ticket=ST-1"
    )


def test_url_matches_prefix_with_port443():
    assert url_matches_prefix(
        "https://portal2020.xtu.edu.cn:443/application-center?ticket=ST-1",
        "https://portal2020.xtu.edu.cn/application-center",
    )


def test_url_matches_prefix_relative():
    assert url_matches_prefix(
        "/application-center?ticket=ST-1",
        "https://portal2020.xtu.edu.cn/application-center",
        base="https://portal2020.xtu.edu.cn/cas/login",
    )


def test_url_matches_rejects_unrelated_host():
    assert not url_matches_prefix(
        "https://evil.example/application-center",
        "https://portal2020.xtu.edu.cn/application-center",
    )
