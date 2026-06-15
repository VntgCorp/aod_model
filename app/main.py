import os

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from fastapi_sso.sso.google import GoogleSSO
from pydantic import BaseModel
from starlette.middleware.sessions import SessionMiddleware

from app.bigquery_registry import list_models, set_active_model
from app.model import predict_new, test_model, train_and_save

app = FastAPI(title="House Price Predictor")
app.add_middleware(
    SessionMiddleware,
    secret_key=os.environ.get("SECRET_KEY", "local-dev-secret-change-in-prod"),
)

templates = Jinja2Templates(directory="app/templates")

google_sso = GoogleSSO(
    client_id=os.environ.get("GOOGLE_CLIENT_ID", ""),
    client_secret=os.environ.get("GOOGLE_CLIENT_SECRET", ""),
    redirect_uri=os.environ.get("GOOGLE_REDIRECT_URI", "http://localhost:8080/auth/callback"),
    allow_insecure_http=True,
)


def require_user(request: Request) -> dict:
    user = request.session.get("user")
    if not user:
        raise HTTPException(status_code=401, detail="로그인이 필요합니다.")
    return user


# ── Auth routes ──

@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    if request.session.get("user"):
        return RedirectResponse("/")
    return templates.TemplateResponse(request=request, name="login.html")


@app.get("/auth/google")
async def auth_google():
    async with google_sso:
        return await google_sso.get_login_redirect()


@app.get("/auth/callback")
async def auth_callback(request: Request):
    async with google_sso:
        user = await google_sso.verify_and_process(request)
    request.session["user"] = {
        "name": user.display_name,
        "email": user.email,
        "picture": user.picture,
    }
    return RedirectResponse("/")


@app.get("/logout")
async def logout(request: Request):
    request.session.clear()
    return RedirectResponse("/login")


# ── App routes ──

@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    user = request.session.get("user")
    if not user:
        return RedirectResponse("/login")
    return templates.TemplateResponse(request=request, name="index.html", context={"user": user})


# ── API routes (로그인 필요) ──

class PredictRequest(BaseModel):
    rooms: float


@app.post("/api/train")
async def api_train(user: dict = Depends(require_user)):
    try:
        return train_and_save(created_by=user.get("email", "unknown"))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/test")
async def api_test(user: dict = Depends(require_user)):
    try:
        return test_model()
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/predict")
async def api_predict(req: PredictRequest, user: dict = Depends(require_user)):
    try:
        return predict_new(req.rooms)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/models")
async def api_list_models(user: dict = Depends(require_user)):
    try:
        return list_models()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/models/{model_id}/activate")
async def api_activate_model(model_id: str, user: dict = Depends(require_user)):
    try:
        if not set_active_model(model_id):
            raise HTTPException(status_code=404, detail="해당 모델을 찾을 수 없습니다.")
        return {"success": True, "model_id": model_id}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
