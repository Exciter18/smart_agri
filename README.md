# Smart Agriculture

Phân loại bệnh lúa bằng đặc trưng ResNet50 và SVM, kết hợp các thuật toán tối ưu chọn đặc trưng PSO, GA, GWO, WOA và SCA.

## Yêu cầu

- Python 3.10 trở lên
- Git
- Dataset được đặt trong `classification_dataset/train/` và `classification_dataset/val/`, theo cấu trúc `ImageFolder` (mỗi lớp một thư mục)

## Cài đặt

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
```

PyTorch có thể cần phiên bản phù hợp riêng cho CPU hoặc CUDA. Tham khảo hướng dẫn cài đặt chính thức của PyTorch nếu lệnh cài từ `requirements.txt` không phù hợp với máy.

## Chạy pipeline

1. Tạo feature cache từ dataset:

   ```powershell
   python extract_features.py
   ```

2. Chạy baseline và các thuật toán chọn đặc trưng, đánh giá và xuất artifacts mô hình:

   ```powershell
   python main_experiment.py
   ```

Artifacts mô hình và feature cache được tạo cục bộ, không được commit vào Git.

## API

`api_server.py` cung cấp endpoint `POST /predict`. Cần có các artifacts mô hình trong thư mục gốc trước khi khởi chạy:

```powershell
uvicorn api_server:app --reload
```

Mở `http://127.0.0.1:8000/docs` để xem tài liệu API.

## Kiểm thử

```powershell
python -m unittest discover -s tests -v
```

## Dataset và artifacts

Dataset, feature cache và các file mô hình như `.pkl`, `.npy`, `.pth` được bỏ qua bởi `.gitignore` để tránh đưa dữ liệu lớn hoặc artifacts cục bộ lên GitHub. Hãy tự tạo lại artifacts bằng pipeline hoặc phân phối riêng nếu người dùng được phép truy cập.
