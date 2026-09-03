"""URL helpers for brittle campus CAS / JW redirect matching."""
from __future__ import annotations

from urllib.parse import urljoin, urlsplit, urlunsplit


def normalize_campus_url(url: str, base: str | None = None) -> str:
    """Resolve relative redirects and strip default HTTP(S) ports.

    School CAS occasionally returns absolute Locations that include ``:443``,
    or relative paths such as ``/application-center?ticket=...``. Strict
    ``startswith`` checks against configured prefixes then fail even though
    the jump target is still valid.
    """
    raw = (url or "").strip()
    if not raw:
        return ""
    if base:
        raw = urljoin(base, raw)
    parts = urlsplit(raw)
    hostname = (parts.hostname or "").lower()
    scheme = (parts.scheme or "https").lower()
    port = parts.port
    # Drop default ports that some gateways inject into Location headers.
    if (scheme == "https" and port == 443) or (scheme == "http" and port == 80):
        netloc = hostname
    elif port is not None:
        netloc = f"{hostname}:{port}"
    else:
        netloc = parts.netloc
    if parts.username or parts.password:
        # Preserve uncommon userinfo if present.
        auth = parts.username or ""
        if parts.password:
            auth = f"{auth}:{parts.password}"
        netloc = f"{auth}@{netloc}" if hostname else parts.netloc
    return urlunsplit((scheme, netloc, parts.path or "", parts.query, parts.fragment))


def url_matches_prefix(url: str, prefix: str, *, base: str | None = None) -> bool:
    """Return True when *url* matches *prefix* after campus URL normalization."""
    normalized = normalize_campus_url(url, base=base)
    expected = normalize_campus_url(prefix)
    if not normalized or not expected:
        return False
    return normalized.startswith(expected)
