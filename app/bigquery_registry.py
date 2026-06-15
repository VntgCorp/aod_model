import json
import os
import uuid
from datetime import datetime, timezone

from google.cloud import bigquery

PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "oneteam-vpc-9")
DATASET_ID = os.environ.get("BQ_DATASET", "ml_models")
TABLE_ID = os.environ.get("BQ_TABLE", "model_registry")
BQ_LOCATION = os.environ.get("BQ_LOCATION", "asia-northeast3")

_TABLE_REF = f"`{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}`"

_SCHEMA = [
    bigquery.SchemaField("model_id", "STRING", mode="REQUIRED"),
    bigquery.SchemaField("model_filename", "STRING", mode="REQUIRED"),
    bigquery.SchemaField("created_at", "TIMESTAMP", mode="REQUIRED"),
    bigquery.SchemaField("model_type", "STRING"),
    bigquery.SchemaField("mae", "FLOAT64"),
    bigquery.SchemaField("r2_score", "FLOAT64"),
    bigquery.SchemaField("coef", "STRING"),
    bigquery.SchemaField("intercept", "FLOAT64"),
    bigquery.SchemaField("x_features", "STRING"),
    bigquery.SchemaField("y_feature", "STRING"),
    bigquery.SchemaField("is_active", "BOOL"),
    bigquery.SchemaField("created_by", "STRING"),
]

_initialized = False


def _client() -> bigquery.Client:
    return bigquery.Client(project=PROJECT_ID)


def init_table() -> None:
    global _initialized
    if _initialized:
        return
    client = _client()
    ds_ref = bigquery.DatasetReference(PROJECT_ID, DATASET_ID)
    try:
        client.get_dataset(ds_ref)
    except Exception:
        ds = bigquery.Dataset(ds_ref)
        ds.location = BQ_LOCATION
        client.create_dataset(ds)
    tbl_ref = bigquery.TableReference(ds_ref, TABLE_ID)
    try:
        client.get_table(tbl_ref)
    except Exception:
        client.create_table(bigquery.Table(tbl_ref, schema=_SCHEMA))
    _initialized = True


def _row_to_dict(row) -> dict:
    return {
        "model_id": row["model_id"],
        "model_filename": row["model_filename"],
        "created_at": row["created_at"].isoformat() if row["created_at"] else None,
        "model_type": row["model_type"],
        "mae": row["mae"],
        "r2_score": row["r2_score"],
        "coef": json.loads(row["coef"]) if row["coef"] else [],
        "intercept": row["intercept"],
        "x_features": json.loads(row["x_features"]) if row["x_features"] else [],
        "y_feature": row["y_feature"],
        "is_active": row["is_active"],
        "created_by": row["created_by"],
    }


def register_model(
    model_filename: str,
    model_type: str,
    mae: float,
    r2_score: float,
    coef: list,
    intercept: float,
    x_features: list,
    y_feature: str,
    created_by: str = "system",
) -> str:
    init_table()
    client = _client()
    model_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc)

    # 기존 활성 모델 비활성화
    client.query(
        f"UPDATE {_TABLE_REF} SET is_active = FALSE WHERE is_active = TRUE"
    ).result()

    insert_sql = f"""
        INSERT INTO {_TABLE_REF} (
            model_id, model_filename, created_at, model_type,
            mae, r2_score, coef, intercept, x_features, y_feature, is_active, created_by
        ) VALUES (
            @model_id, @model_filename, @created_at, @model_type,
            @mae, @r2_score, @coef, @intercept, @x_features, @y_feature, TRUE, @created_by
        )
    """
    client.query(
        insert_sql,
        job_config=bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter("model_id", "STRING", model_id),
            bigquery.ScalarQueryParameter("model_filename", "STRING", model_filename),
            bigquery.ScalarQueryParameter("created_at", "TIMESTAMP", now),
            bigquery.ScalarQueryParameter("model_type", "STRING", model_type),
            bigquery.ScalarQueryParameter("mae", "FLOAT64", mae),
            bigquery.ScalarQueryParameter("r2_score", "FLOAT64", r2_score),
            bigquery.ScalarQueryParameter("coef", "STRING", json.dumps(coef)),
            bigquery.ScalarQueryParameter("intercept", "FLOAT64", intercept),
            bigquery.ScalarQueryParameter("x_features", "STRING", json.dumps(x_features)),
            bigquery.ScalarQueryParameter("y_feature", "STRING", y_feature),
            bigquery.ScalarQueryParameter("created_by", "STRING", created_by),
        ]),
    ).result()
    return model_id


def list_models() -> list:
    init_table()
    client = _client()
    query = f"""
        SELECT model_id, model_filename, created_at, model_type,
               mae, r2_score, coef, intercept, x_features, y_feature, is_active, created_by
        FROM {_TABLE_REF}
        ORDER BY created_at DESC
    """
    return [_row_to_dict(row) for row in client.query(query).result()]


def get_active_model() -> dict | None:
    init_table()
    client = _client()
    query = f"""
        SELECT model_id, model_filename, created_at, model_type,
               mae, r2_score, coef, intercept, x_features, y_feature, is_active, created_by
        FROM {_TABLE_REF}
        WHERE is_active = TRUE
        ORDER BY created_at DESC
        LIMIT 1
    """
    rows = list(client.query(query).result())
    return _row_to_dict(rows[0]) if rows else None


def set_active_model(model_id: str) -> bool:
    init_table()
    client = _client()
    job_config = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("model_id", "STRING", model_id)]
    )
    rows = list(
        client.query(
            f"SELECT model_id FROM {_TABLE_REF} WHERE model_id = @model_id LIMIT 1",
            job_config=job_config,
        ).result()
    )
    if not rows:
        return False
    client.query(
        f"UPDATE {_TABLE_REF} SET is_active = FALSE WHERE is_active = TRUE"
    ).result()
    client.query(
        f"UPDATE {_TABLE_REF} SET is_active = TRUE WHERE model_id = @model_id",
        job_config=job_config,
    ).result()
    return True
