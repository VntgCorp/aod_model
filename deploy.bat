@echo off
setlocal enabledelayedexpansion

set PROJECT_ID=oneteam-vpc-9
set REGION=asia-northeast3
set SERVICE=house-price-predictor
set BUCKET=oneteam-vpc-9-ml-models
set IMAGE=gcr.io/%PROJECT_ID%/%SERVICE%

echo.
echo ================================================
echo   House Price Predictor  ^|  Cloud Run Deploy
echo ================================================
echo.

echo [0/4] Setting GCloud project...
call gcloud config set project %PROJECT_ID%

echo.
echo [1/4] Creating GCS bucket...
call gsutil mb -p %PROJECT_ID% -l %REGION% gs://%BUCKET% 2>nul
if %errorlevel% neq 0 (
    echo   Bucket already exists. Skipping.
)

echo.
echo [2/4] Building and pushing Docker image...
call gcloud builds submit --tag %IMAGE% --project %PROJECT_ID% --async
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Failed to submit build.
    pause
    exit /b 1
)

echo   Build submitted. Waiting for image to be ready (max 6 min)...
set /a WAIT=0
:poll
set /a WAIT+=1
if %WAIT% gtr 24 (
    echo.
    echo [ERROR] Build timed out. Check Cloud Console for build status.
    pause
    exit /b 1
)
timeout /t 15 /nobreak >nul
call gcloud container images describe %IMAGE% --project %PROJECT_ID% >nul 2>nul
if %errorlevel% neq 0 (
    echo   Still building... [%WAIT%/24]
    goto poll
)
echo   Image ready.

echo.
echo [3/4] Deploying to Cloud Run...
call gcloud run deploy %SERVICE% ^
  --image %IMAGE% ^
  --platform managed ^
  --region %REGION% ^
  --allow-unauthenticated ^
  --set-env-vars GCS_BUCKET_NAME=%BUCKET%,GOOGLE_CLIENT_ID=%GOOGLE_CLIENT_ID%,GOOGLE_CLIENT_SECRET=%GOOGLE_CLIENT_SECRET%,GOOGLE_REDIRECT_URI=https://YOUR_CLOUD_RUN_URL/auth/callback,SECRET_KEY=%SECRET_KEY%,GCP_PROJECT_ID=%PROJECT_ID%,BQ_DATASET=ml_models,BQ_TABLE=model_registry,BQ_LOCATION=%REGION% ^
  --project %PROJECT_ID%
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Cloud Run deployment failed.
    pause
    exit /b 1
)

echo.
echo [4/4] Fetching service URL...
for /f "delims=" %%u in ('call gcloud run services describe %SERVICE% --region %REGION% --project %PROJECT_ID% --format "value(status.url)"') do set URL=%%u

echo.
echo ================================================
echo   Deploy successful!
echo   URL: %URL%
echo ================================================
echo.
pause