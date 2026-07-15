FROM python:3.12-slim

WORKDIR /app

COPY pyproject.toml .
COPY leaderboard_api ./leaderboard_api
RUN pip install --no-cache-dir .

EXPOSE 8080

CMD ["uvicorn", "leaderboard_api.main:app", "--host", "0.0.0.0", "--port", "8080"]
