# smart_agri

```text
smart_agri/
├── app/
│   ├── api/             # FastAPI
│   └── mobile/          # Ứng dụng mobile
└── model_training/      # Huấn luyện, tối ưu, kiểm thử và báo cáo
```

## Model

Cài dependencies ở thư mục gốc:

```powershell
pip install -r requirements.txt
```

Đặt dữ liệu ở `classification_dataset/train/` và `classification_dataset/val/`, sau đó chạy từ thư mục gốc:

```powershell
python -m model_training.extract_features
python -m model_training.main_experiment
```

Kiểm thử:

```powershell
python -m unittest discover -s model_training/tests -v
```

## API

Cần có các model artifacts trong thư mục gốc, sau đó chạy:

```powershell
uvicorn app.api.api_server:app --reload
```
