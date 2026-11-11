FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt requirements-production.txt ./
RUN pip install --no-cache-dir -r requirements-production.txt
COPY . .
RUN rm -f rosa.db && rm -rf .pytest_cache __pycache__ tests/__pycache__
EXPOSE 8080
CMD ["sh", "./start_production.sh"]
