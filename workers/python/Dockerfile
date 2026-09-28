# syntax=docker/dockerfile:1
# BraiSEO background worker — deployed to Fly.io (see fly.toml).
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app
RUN useradd --create-home --uid 10001 worker

# Dependencies first for layer caching, then the package itself.
COPY pyproject.toml ./
RUN python - <<'PY'
import subprocess, sys, tomllib
deps = tomllib.load(open("pyproject.toml", "rb"))["project"]["dependencies"]
subprocess.check_call([sys.executable, "-m", "pip", "install", *deps])
PY
COPY openseo_workers ./openseo_workers
RUN pip install --no-deps .

USER worker
# Process groups in fly.toml override this with --queues.
CMD ["python", "-m", "openseo_workers"]
