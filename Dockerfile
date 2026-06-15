FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV GCS_BUCKET_NAME=oneteam-vpc-9-ml-models
ENV GCP_PROJECT_ID=oneteam-vpc-9
ENV BQ_DATASET=ml_models
ENV BQ_TABLE=model_registry
ENV BQ_LOCATION=asia-northeast3
# 아래 값들은 Cloud Run 배포 시 --set-env-vars 로 주입하세요
ENV GOOGLE_CLIENT_ID=""
ENV GOOGLE_CLIENT_SECRET=""
ENV GOOGLE_REDIRECT_URI=""
ENV SECRET_KEY=""

EXPOSE 8080

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}"]
