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

rem -- Load secrets --
if not exist deploy_secrets.bat (
    echo [ERROR] deploy_secrets.bat not found.
    echo         Copy deploy_secrets.bat.example and fill in the values.
    pause
    exit /b 1
)
call deploy_secrets.bat

rem -- Validate required variables --
if "%GOOGLE_CLIENT_ID%"=="" (
    echo [ERROR] GOOGLE_CLIENT_ID is not set. Check deploy_secrets.bat.
    pause ^& exit /b 1
)
if "%GOOGLE_CLIENT_SECRET%"=="" (
    echo [ERROR] GOOGLE_CLIENT_SECRET is not set.
    pause ^& exit /b 1
)
if "%SECRET_KEY%"=="" (
    echo [ERROR] SECRET_KEY is not set.
    pause ^& exit /b 1
)
if "%GOOGLE_REDIRECT_URI%"=="https://YOUR_CLOUD_RUN_URL/auth/callback" (
    echo [WARN] GOOGLE_REDIRECT_URI is still a placeholder. Update it after first deploy.
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
call gcloud projects add-iam-policy-binding %PROJECT_ID% --member="serviceAccount:%SA%" --role="roles/bigquery.dataEditor" --quiet 2>nul
if %errorlevel% neq 0 echo   [WARN] BigQuery Data Editor: permission denied. Ask admin to grant manually.
call gcloud projects add-iam-policy-binding %PROJECT_ID% --member="serviceAccount:%SA%" --role="roles/bigquery.jobUser" --quiet 2>nul
if %errorlevel% neq 0 echo   [WARN] BigQuery Job User: permission denied. Ask admin to grant manually.
call gcloud projects add-iam-policy-binding %PROJECT_ID% --member="serviceAccount:%SA%" --role="roles/storage.objectAdmin" --quiet 2>nul
if %errorlevel% neq 0 echo   [WARN] Storage Object Admin: permission denied. Ask admin to grant manually.

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
echo [Next steps]
echo   1. Add this redirect URI in Google OAuth Console:
echo      %URL%/auth/callback
echo.
echo   2. Update GOOGLE_REDIRECT_URI in deploy_secrets.bat:
echo      %URL%/auth/callback
echo.
echo   3. If GOOGLE_REDIRECT_URI was a placeholder, re-run this script.
echo.
echo   [BigQuery IAM - if WARN appeared above, ask admin to run:]
echo   gcloud projects add-iam-policy-binding %PROJECT_ID% --member=serviceAccount:%SA% --role=roles/bigquery.dataEditor
echo   gcloud projects add-iam-policy-binding %PROJECT_ID% --member=serviceAccount:%SA% --role=roles/bigquery.jobUser
echo.
pause
