# ==========================================
# FASTAPI MODEL DEPLOYMENT
# ==========================================

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import pandas as pd
import numpy as np
import joblib
from pathlib import Path
from typing import Dict, Any


# ==========================================
# LOAD MODEL AND THRESHOLD
# ==========================================

BASE_DIR = Path(__file__).resolve().parent.parent
MODEL_DIR = BASE_DIR / "models"

MODEL_PATH = MODEL_DIR / "churn_prediction_model.pkl"
THRESHOLD_PATH = MODEL_DIR / "churn_prediction_threshold.pkl"

try:
    model = joblib.load(MODEL_PATH)
    threshold = joblib.load(THRESHOLD_PATH)
    threshold = round(float(threshold), 2)
except Exception as e:
    raise RuntimeError(f"Error loading model or threshold: {e}")


# ==========================================
# CREATE FASTAPI APP
# ==========================================

app = FastAPI(
    title="RideWise Churn Prediction API",
    description="API for predicting customer churn using the final trained machine learning model.",
    version="1.0.0"
)


# ==========================================
# REQUEST SCHEMA
# ==========================================

class PredictionInput(BaseModel):
    features: Dict[str, Any]


# ==========================================
# HELPER: GET PIPELINE COLUMNS
# ==========================================

def get_pipeline_columns():
    """
    Extract numeric and categorical columns from a sklearn pipeline
    that contains a ColumnTransformer.
    """

    numeric_cols = []
    categorical_cols = []

    if hasattr(model, "named_steps"):
        for step_name, step in model.named_steps.items():
            if hasattr(step, "transformers_"):
                for transformer_name, transformer, columns in step.transformers_:
                    if transformer_name in ["remainder"]:
                        continue

                    if isinstance(columns, slice):
                        continue

                    columns = list(columns)

                    if "num" in transformer_name.lower():
                        numeric_cols.extend(columns)

                    elif "cat" in transformer_name.lower():
                        categorical_cols.extend(columns)

    return numeric_cols, categorical_cols


NUMERIC_COLS, CATEGORICAL_COLS = get_pipeline_columns()


# ==========================================
# HOME ROUTE
# ==========================================

@app.get("/")
def home():
    return {
        "message": "RideWise Churn Prediction API is running.",
        "threshold": threshold
    }


# ==========================================
# HEALTH CHECK ROUTE
# ==========================================

@app.get("/health")
def health_check():
    return {
        "status": "healthy",
        "model_loaded": model is not None,
        "threshold": threshold
    }


# ==========================================
# FEATURE NAMES ROUTE
# ==========================================

@app.get("/features")
def get_features():
    info = {
        "model_type": str(type(model)),
        "threshold": threshold,
        "numeric_columns_found": NUMERIC_COLS,
        "categorical_columns_found": CATEGORICAL_COLS
    }

    if hasattr(model, "feature_names_in_"):
        info["number_of_features"] = len(model.feature_names_in_)
        info["features"] = list(model.feature_names_in_)

    if hasattr(model, "named_steps"):
        info["pipeline_steps"] = list(model.named_steps.keys())

    return info


# ==========================================
# DEBUG MODEL ROUTE
# ==========================================

@app.get("/debug-model")
def debug_model():
    debug_info = {
        "model_type": str(type(model)),
        "threshold": threshold,
        "has_feature_names_in": hasattr(model, "feature_names_in_"),
        "has_named_steps": hasattr(model, "named_steps"),
        "numeric_columns_found": NUMERIC_COLS,
        "categorical_columns_found": CATEGORICAL_COLS
    }

    if hasattr(model, "feature_names_in_"):
        debug_info["feature_names_in"] = list(model.feature_names_in_)

    if hasattr(model, "named_steps"):
        debug_info["pipeline_steps"] = list(model.named_steps.keys())

        for step_name, step in model.named_steps.items():
            debug_info[f"{step_name}_type"] = str(type(step))

            if hasattr(step, "transformers_"):
                debug_info[f"{step_name}_transformers"] = [
                    str(transformer) for transformer in step.transformers_
                ]

    return debug_info


# ==========================================
# SAMPLE JSON ROUTE FOR TESTING
# ==========================================

@app.get("/sample-json")
def get_sample_json():
    sample_features = {}

    if hasattr(model, "feature_names_in_"):
        expected_columns = list(model.feature_names_in_)
    else:
        expected_columns = NUMERIC_COLS + CATEGORICAL_COLS

    for col in expected_columns:
        if col in CATEGORICAL_COLS:
            if col == "age_group":
                sample_features[col] = "26-35"
            elif col == "loyalty_status":
                sample_features[col] = "Silver"
            elif col == "favourite_vehicle_type":
                sample_features[col] = "Car"
            else:
                sample_features[col] = "Unknown"
        else:
            sample_features[col] = 1.0

    # Better realistic values for important numeric features
    sample_features.update({
        "total_trips": 20,
        "trips_per_active_day": 2.5,
        "avg_tip_percentage": 12.0,
        "total_fare": 370.0,
        "avg_surge": 1.2,
        "avg_time_on_app": 8.5
    })

    return {
        "message": "Copy sample_request_body and paste it into POST /predict.",
        "sample_request_body": {
            "features": sample_features
        }
    }


# ==========================================
# HELPER: PREPARE INPUT DATA
# ==========================================

def prepare_input_dataframe(raw_features: Dict[str, Any]) -> pd.DataFrame:
    """
    Prepare incoming JSON features for the sklearn pipeline.
    Numeric columns stay numeric.
    Categorical columns stay as strings.
    """

    # Expected raw input columns
    if hasattr(model, "feature_names_in_"):
        expected_columns = list(model.feature_names_in_)
    else:
        expected_columns = NUMERIC_COLS + CATEGORICAL_COLS

    cleaned_features = {}

    for col in expected_columns:
        value = raw_features.get(col, None)

        # Remove Swagger placeholder objects/lists
        if isinstance(value, (dict, list)):
            value = None

        if col in CATEGORICAL_COLS:
            if value is None or value == "":
                cleaned_features[col] = "Unknown"
            else:
                cleaned_features[col] = str(value)

        else:
            value = pd.to_numeric(value, errors="coerce")
            if pd.isna(value) or value in [np.inf, -np.inf]:
                value = 0.0
            cleaned_features[col] = float(value)

    input_df = pd.DataFrame([cleaned_features])

    # Ensure correct order
    input_df = input_df[expected_columns]

    return input_df


# ==========================================
# PREDICTION ROUTE
# ==========================================

@app.post("/predict")
def predict_churn(input_data: PredictionInput):
    try:
        input_df = prepare_input_dataframe(input_data.features)

        churn_probability = model.predict_proba(input_df)[:, 1][0]

        prediction = int(churn_probability >= threshold)

        prediction_label = "Churn" if prediction == 1 else "Not Churn"

        return {
            "prediction": prediction,
            "prediction_label": prediction_label,
            "churn_probability": round(float(churn_probability), 4),
            "threshold": threshold
        }

    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail={
                "error": str(e),
                "hint": "Open /features and /debug-model. Use /sample-json for the safest test body."
            }
        )