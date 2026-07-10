# ridewise-customer-analytics
Customer Analytics and Churn Prediction Platform using Python, Machine Learning, FastAPI and Streamlit.



ridewise-customer-analytics/
│
├── data/
│   ├── raw/
│   │   ├── riders.csv
│   │   ├── trips.csv
│   │   ├── sessions.csv
│   │   ├── drivers.csv
│   │   └── promotions.csv
│   │
│   └── processed/
│
├── notebooks/
│   ├── 01_data_profiling.ipynb
│   ├── 02_data_cleaning.ipynb
│   ├── 03_eda.ipynb
│   ├── 04_feature_engineering.ipynb
│   ├── 05_customer_segmentation.ipynb
│   ├── 06_churn_prediction.ipynb
│   ├── 07_model_evaluation.ipynb
│   └── 08_model_interpretation.ipynb
│
├── models/
│
├── api/
│   └── main.py
│
├── dashboard/
│   └── app.py
│
├── reports/
│   └── figures/
│
├── tests/
│
├── README.md
├── requirements.txt
├── .gitignore
├── LICENSE
└── Dockerfile





At the default threshold of 0.5, Logistic Regression achieved the strongest overall performance with the highest F1 score of 0.3488, recall of 0.5995 and ROC-AUC of 0.6200. Although Random Forest produced the highest accuracy, its lower recall showed that it missed more positive cases. Since this is an imbalanced classification problem where identifying positive cases is important, F1 score and recall were considered more reliable than accuracy alone. Therefore, Logistic Regression was selected as the best baseline model at the default threshold.




Three models (Logistic Regression, Random Forest, and XGBoost) were evaluated using 5-fold cross-validation and threshold tuning. XGBoost achieved the highest F1 score (0.3612) at an optimized classification threshold of 0.45 and was selected as the final model for deployment.

One concern

Even though XGBoost is the best of the three, the overall performance is still modest:

F1 ≈ 0.36
ROC-AUC ≈ 0.61

That suggests the main limitation is not the algorithm but the features.






The trained churn prediction model was successfully deployed using FastAPI. The `/predict` endpoint accepts customer activity features as JSON input and returns the predicted churn class, churn probability and classification threshold. A test request returned a successful `200` response, confirming that the API is working correctly and the model is able to generate real-time predictions.



The final churn prediction model was deployed as a FastAPI application and successfully containerised using Docker. The Docker image was built and run locally, exposing the API through port 8001. The `/predict` endpoint was tested successfully and returned churn prediction results including the predicted class, churn probability and classification threshold.




## Model Evaluation Summary

The final churn prediction model was evaluated using the same rider-level dataset, target column, feature selection and train-test split approach used during model training. The target variable was `is_churned`, and non-modelling columns such as `user_id`, `signup_date` and `referred_by` were removed before evaluation.

The saved best model and classification threshold were loaded from the models directory. Predictions were generated using predicted churn probabilities, and the saved threshold was applied to classify customers as churn or not churn.

The model was evaluated using accuracy, precision, recall, F1 score, ROC-AUC, average precision, confusion matrix, ROC curve and precision-recall curve. Since churn prediction is an imbalanced classification problem, F1 score, recall and precision were considered more informative than accuracy alone.




python -m uvicorn api.main:app --reload (t start the fastAPI)


docker build -t ridewise-churn-api .


docker build -t ridewise-churn-api .

docker run -p 8001:8000 ridewise-churn-api

http://127.0.0.1:8001/docs