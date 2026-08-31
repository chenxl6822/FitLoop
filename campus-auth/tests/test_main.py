import pytest
from httpx import ASGITransport, AsyncClient

from fitloop_campus.main import app, settings


@pytest.fixture(autouse=True)
def _service_key(monkeypatch):
    monkeypatch.setenv("CAMPUS_SERVICE_KEY", "x" * 32)
    settings.service_key = "x" * 32


@pytest.mark.asyncio
async def test_ready():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/ready")
    assert response.status_code == 200
    assert response.json()["status"] == "UP"


@pytest.mark.asyncio
async def test_verify_requires_service_key():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/internal/v1/verify",
            json={"userId": 1, "studentId": "20230001", "password": "secret"},
        )
    assert response.status_code == 401
