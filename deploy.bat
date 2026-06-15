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

rem ── 시크릿 로드 ──
if not exist deploy_secrets.bat (
    echo [ERROR] deploy_secrets.bat 파일이 없습니다.
    echo         deploy_secrets.bat.example 을 복사한 뒤 실제 값을 입력하세요.
    pause
    exit /b 1
)
call deploy_secrets.bat

rem ── 필수 변수 확인 ──
if "%GOOGLE_CLIENT_ID%"=="" (
    echo [ERROR] GOOGLE_CLIENT_ID 가 설정되지 않았습니다. deploy_secrets.bat 을 확인하세요.
    pause & exit /b 1
)
if "%GOOGLE_CLIENT_SECRET%"=="" (
    echo [ERROR] GOOGLE_CLIENT_SECRET 이 설정되지 않았습니다.
    pause & exit /b 1
)
if "%SECRET_KEY%"=="" (
    echo [ERROR] SECRET_KEY 가 설정되지 않았습니다.
    pause & exit /b 1
)
if "%GOOGLE_REDIRECT_URI%"=="https://YOUR_CLOUD_RUN_URL/auth/callback" (
    echo [WARN] GOOGLE_REDIRECT_URI 가 아직 placeholder 입니다.
    echo        첫 배포 후 실제 URL 로 업데이트하세요.
)

echo [0/5] Setting GCloud project...
call gcloud config set project %PROJECT_ID%

echo.
echo [1/5] Creating GCS bucket...
call gsutil mb -p %PROJECT_ID% -l %REGION% gs://%BUCKET% 2>nul
if %errorlevel% neq 0 (
    echo   Bucket already exists. Skipping.
)

echo.
echo [2/5] Granting BigQuery roles to Cloud Run service account...
for /f "delims=" %%N in ('gcloud projects describe %PROJECT_ID% --format="value(projectNumber)"') do set PROJECT_NUMBER=%%N
set SA=%PROJECT_NUMBER%-compute@developer.gserviceaccount.com
echo   Service Account: %SA%
call gcloud projects add-iam-policy-binding %PROJECT_ID% --member="serviceAccount:%SA%" --role="roles/bigquery.dataEditor" --quiet
call gcloud projects add-iam-policy-binding %PROJECT_ID% --member="serviceAccount:%SA%" --role="roles/bigquery.jobUser" --quiet
call gcloud projects add-iam-policy-binding %PROJECT_ID% --member="serviceAccount:%SA%" --role="roles/storage.objectAdmin" --quiet

echo.
echo [3/5] Building and pushing Docker image...
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
echo [4/5] Deploying to Cloud Run...
call gcloud run deploy %SERVICE% ^
  --image %IMAGE% ^
  --platform managed ^
  --region %REGION% ^
  --allow-unauthenticated ^
  --set-env-vars "GCS_BUCKET_NAME=%BUCKET%,GCP_PROJECT_ID=%PROJECT_ID%,BQ_DATASET=ml_models,BQ_TABLE=model_registry,BQ_LOCATION=%REGION%,GOOGLE_CLIENT_ID=%GOOGLE_CLIENT_ID%,GOOGLE_CLIENT_SECRET=%GOOGLE_CLIENT_SECRET%,GOOGLE_REDIRECT_URI=%GOOGLE_REDIRECT_URI%,SECRET_KEY=%SECRET_KEY%" ^
  --project %PROJECT_ID%
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Cloud Run deployment failed.
    pause
    exit /b 1
)

echo.
echo [5/5] Fetching service URL...
for /f "delims=" %%u in ('gcloud run services describe %SERVICE% --region %REGION% --project %PROJECT_ID% --format "value(status.url)"') do set URL=%%u

echo.
echo ================================================
echo   Deploy successful!
echo   URL: %URL%
echo ================================================
echo.
echo [다음 단계]
echo   1. Google OAuth 콘솔에서 승인된 리디렉션 URI 를 추가하세요:
echo      %URL%/auth/callback
echo.
echo   2. deploy_secrets.bat 의 GOOGLE_REDIRECT_URI 를 아래로 업데이트하세요:
echo      %URL%/auth/callback
echo.
echo   3. GOOGLE_REDIRECT_URI 가 placeholder 였다면 이 스크립트를 다시 실행하세요.
echo.
pause
