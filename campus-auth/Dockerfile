FROM python:3.11-slim

WORKDIR /app

COPY campus-auth/pyproject.toml /app/pyproject.toml
COPY campus-auth/src /app/src
COPY campus-auth/vendor/xtu_ems /app/src/xtu_ems

RUN pip install --no-cache-dir .

ENV PYTHONPATH=/app/src
EXPOSE 8091

CMD ["uvicorn", "fitloop_campus.main:app", "--host", "0.0.0.0", "--port", "8091"]
