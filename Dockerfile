FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 ROSA_DATA_DIR=/var/lib/delvane
WORKDIR /app
COPY requirements.txt requirements-production.txt ./
RUN pip install --no-cache-dir -r requirements-production.txt

# .dockerignore is a positive allowlist for the inputs below.
COPY *.py start_production.sh ./
COPY static/ static/
COPY docs/ntak/v9/ docs/ntak/v9/
COPY docs/viza/ docs/viza/

RUN find /app -type d -exec chmod 0755 {} + \
    && find /app -type f -exec chmod 0644 {} + \
    && python -c "from ntak_contracts import contracts; import viza_api; contracts()" \
    && mkdir -p /var/lib/delvane \
    && chown 10001:10001 /var/lib/delvane
USER 10001:10001
EXPOSE 8080
CMD ["sh", "./start_production.sh"]
