from datetime import datetime, timezone

import pandas as pd
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import train_test_split

from app.bigquery_registry import get_active_model, register_model
from app.gcs import BUCKET_NAME, download_model, upload_model

_DATA = {
    "rooms": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    "price": [1.5, 2.3, 3.1, 4.0, 4.8, 5.6, 6.5, 7.3, 8.2, 9.0],
}


def _split():
    df = pd.DataFrame(_DATA)
    return train_test_split(df[["rooms"]], df["price"], test_size=0.2, random_state=42)


def _versioned_blob() -> str:
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    return f"models/house_price_model_{ts}.pkl"


def train_and_save(created_by: str = "system") -> dict:
    X_train, X_test, y_train, y_test = _split()

    model = LinearRegression()
    model.fit(X_train, y_train)

    preds = model.predict(X_test)
    mae = round(float(mean_absolute_error(y_test, preds)), 4)
    r2 = round(float(r2_score(y_test, preds)), 4)
    coef = [round(float(c), 4) for c in model.coef_]
    intercept = round(float(model.intercept_), 4)

    blob_path = _versioned_blob()
    upload_model(model, blob_path)

    model_id = register_model(
        model_filename=blob_path,
        model_type="LinearRegression",
        mae=mae,
        r2_score=r2,
        coef=coef,
        intercept=intercept,
        x_features=["rooms"],
        y_feature="price",
        created_by=created_by,
    )

    return {
        "model_id": model_id,
        "gcs_path": f"gs://{BUCKET_NAME}/{blob_path}",
        "model_filename": blob_path,
        "coefficient": coef[0],
        "intercept": intercept,
        "mae": mae,
        "r2_score": r2,
        "train_samples": len(X_train),
        "test_samples": len(X_test),
    }


def test_model() -> dict:
    active = get_active_model()
    if not active:
        raise ValueError("활성화된 모델이 없습니다. Step 1에서 먼저 모델을 생성해주세요.")
    model = download_model(active["model_filename"])
    X_train, X_test, y_train, y_test = _split()
    preds = model.predict(X_test)
    results = [
        {
            "rooms": int(r),
            "actual": round(float(a), 2),
            "predicted": round(float(p), 2),
        }
        for r, a, p in zip(X_test["rooms"].values, y_test.values, preds)
    ]
    return {
        "results": results,
        "mse": round(float(mean_squared_error(y_test, preds)), 6),
        "r2_score": round(float(r2_score(y_test, preds)), 4),
        "active_model_id": active["model_id"],
    }


def predict_new(rooms: float) -> dict:
    active = get_active_model()
    if not active:
        raise ValueError("활성화된 모델이 없습니다. Step 1에서 먼저 모델을 생성해주세요.")
    model = download_model(active["model_filename"])
    pred = model.predict(pd.DataFrame({"rooms": [rooms]}))
    return {
        "rooms": rooms,
        "predicted_price": round(float(pred[0]), 2),
        "active_model_id": active["model_id"],
    }
