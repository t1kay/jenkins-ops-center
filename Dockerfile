FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /srv

COPY app/requirements.txt app/requirements.txt
RUN pip install -r app/requirements.txt \
    && useradd --create-home --uid 1000 appuser

COPY app/ app/

# Tag của image, Jenkins truyền vào lúc build để /health trả về đúng version
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

USER appuser
EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/', timeout=2)" || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--access-logfile", "-", "app.main:app"]
