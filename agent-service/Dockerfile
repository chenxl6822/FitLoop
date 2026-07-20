ARG PYTHON_IMAGE=python:3.12-slim
FROM ${PYTHON_IMAGE}

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app
COPY pyproject.toml ./
COPY src ./src
RUN pip install .

USER 65532:65532
EXPOSE 8090
CMD ["uvicorn", "fitloop_agent.main:app", "--host", "0.0.0.0", "--port", "8090"]
