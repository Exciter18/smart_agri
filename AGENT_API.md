# Trợ lý bệnh lúa

Phiên bản này giữ model ảnh làm nhiệm vụ **phân loại 9 nhãn** và mặc định dùng
**OpenAI Responses API** làm model ngôn ngữ cho agent. Agent dùng RAG để đưa
đúng hồ sơ bệnh và nguồn chuyên môn vào prompt trước khi GPT tạo câu trả lời.
Khóa OpenAI chỉ nằm ở backend; ứng dụng Flutter không được nhận hoặc lưu khóa.

Có thể chuyển về Qwen2.5 chạy local bằng Ollama thông qua `LLM_PROVIDER=ollama`.

Agent có hai tầng kiến thức:

- JSON đã kiểm duyệt luôn có sẵn để hệ thống không bị ngừng khi database lỗi.
- PostgreSQL + pgvector lưu các đoạn tài liệu và embedding để tìm theo ý nghĩa
  câu hỏi. Nếu `DATABASE_URL` chưa được cấu hình, agent tự dùng tầng JSON.

## Phạm vi

- Nhận một ảnh chụp gần của lá, thân hoặc cổ bông lúa.
- Hỗ trợ các nhãn: bạc lá, đốm nâu, khỏe mạnh, bọ gai, đạo ôn lá,
  cháy lá, than lá, đốm nâu hẹp và đạo ôn cổ bông.
- Hỏi thêm tuổi/giai đoạn lúa, thời tiết gần đây, tình trạng nước, lịch bón đạm
  và biện pháp đã thử.
- Trả lời về nguyên nhân, dấu hiệu tham khảo, xử lý, nước, phân bón và phòng ngừa.
- Không ước lượng tỷ lệ nhiễm toàn ruộng, không dự đoán năng suất và không kê
  tên/liều thuốc chỉ từ một ảnh.

## Chuẩn bị backend với OpenAI API

Từ thư mục gốc dự án:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
$env:OPENAI_API_KEY='khóa-api-của-bạn'
$env:LLM_PROVIDER='openai'
$env:OPENAI_MODEL='gpt-6.1-sol'
.\.venv\Scripts\python.exe -m uvicorn app.api.api_server:app --host 0.0.0.0 --port 8000
```

Không commit `OPENAI_API_KEY`, không đặt khóa trong `main.dart` và không gửi
khóa xuống điện thoại. Sao chép `.env.example` để biết các biến cấu hình nhưng
phải tự đặt giá trị thật trong môi trường chạy backend.

## Bật PostgreSQL + pgvector

Repo đã có `docker-compose.yml` dùng image `pgvector/pgvector:pg17`, schema ở
`infra/postgres/schema.sql` và danh mục nguồn tại
`data/knowledge/sources.json`. Cài Docker Desktop trước, sau đó chạy:

```powershell
docker compose up -d postgres
$env:DATABASE_URL='postgresql://smart_agri:change-this-password@127.0.0.1:5432/smart_agri'
$env:OPENAI_API_KEY='khóa-api-của-bạn'
$env:OPENAI_EMBEDDING_MODEL='text-embedding-3-large'
$env:OPENAI_EMBEDDING_DIMENSIONS='1024'
python -m app.knowledge.ingest --initialize --include-remote
```

Lệnh nạp dữ liệu sẽ:

1. Chuyển 9 hồ sơ bệnh hiện có thành các đoạn nhỏ theo nguyên nhân, triệu chứng,
   nước, phân bón, xử lý và phòng ngừa.
2. Tải các nguồn cho phép từ IRRI, FAO, LSU AgCenter và cơ quan nông nghiệp.
3. Tạo embedding rồi lưu vector, nội dung, chủ đề, URL và checksum nguồn.
4. Khi hỏi, kết hợp độ gần vector 85% với tìm kiếm từ khóa 15%, đồng thời ưu
   tiên đúng nhãn bệnh do model ảnh trả về.

Muốn chỉ nạp JSON đã kiểm duyệt, bỏ `--include-remote`. Không đưa database hoặc
khóa API thẳng vào ứng dụng Flutter; Flutter chỉ gọi REST API của backend.

Sau khi nạp xong, khởi động lại Uvicorn và mở `/agent/model-info`. Các trường
`knowledge_backend`, `retrieval.database.embedded_chunks` và
`session_storage.backend` cho biết hệ thống đã dùng pgvector thật hay vẫn đang
chạy fallback.

### Chế độ Qwen local dự phòng

```powershell
ollama pull qwen2.5:3b
$env:LLM_PROVIDER='ollama'
$env:OLLAMA_MODEL='qwen2.5:3b'
.\.venv\Scripts\python.exe -m uvicorn app.api.api_server:app --host 0.0.0.0 --port 8000
```

Mở `http://127.0.0.1:8000/api-docs` để thử API và
`http://127.0.0.1:8000/health` để xem trạng thái.
`http://127.0.0.1:8000/agent/model-info` cho biết model ngôn ngữ, nhà cung cấp
và agent đang dùng API ngoài hay Ollama local.

Model ảnh dùng năm file sau nằm ở thư mục gốc dự án (branch `main` hiện đã
đóng gói đủ các file này):

- `fine_tuned_resnet.pth`
- `svm_model.pkl`
- `scaler.pkl`
- `classes.pkl`
- `best_features.npy`

Nếu một file bị thiếu, server vẫn chạy và các API agent vẫn hoạt động;
`/predict` trả mã 503 cùng danh sách file thiếu.

## API chính

### `POST /predict`

Gửi multipart với trường `file`. Kết quả gồm `class_id`, tên tiếng Việt,
`confidence_score`, ba dự đoán cao nhất, đánh giá chất lượng ảnh và trường
`agent`. Lưu `agent.session_id` để tiếp tục trò chuyện.
Trong `agent.generation` có tên model, chế độ `openai_api` hoặc `local_llm`, độ trễ, số token và
tốc độ sinh để phục vụ đánh giá thực nghiệm trong báo cáo.

### `POST /agent/chat`

```json
{
  "session_id": "id nhận từ /predict",
  "message": "Lúa gieo được 35 ngày, đang đẻ nhánh và gần đây mưa nhiều"
}
```

### `POST /agent/start`

Dùng để kiểm thử agent khi chưa có file model:

```json
{
  "class_id": "Rice__LeafBlast",
  "confidence_score": 0.78
}
```

## Chạy Flutter

Android Emulator truy cập backend trên máy chủ qua `10.0.2.2`:

```powershell
cd app\mobile
flutter pub get
flutter run --dart-define=SMART_AGRI_API_URL=http://10.0.2.2:8000/predict
```

### Demo trên điện thoại Android qua USB

Giữ Ollama và backend đang chạy trên máy tính. Bật USB debugging, cắm điện
thoại, rồi từ thư mục gốc repo chạy:

```powershell
adb reverse tcp:8000 tcp:8000
cd app\mobile
flutter run -d <device-id> --dart-define=SMART_AGRI_API_URL=http://127.0.0.1:8000/predict
```

Lấy `<device-id>` từ `flutter devices`. Cấu hình cho phép HTTP chỉ nằm trong
Android debug manifest; bản release không bật cleartext traffic. Giữ cáp USB
và cửa sổ backend trong suốt buổi demo. Không cần PostgreSQL cho luồng demo cơ
bản: agent dùng kiến thức JSON và SQLite cục bộ.

Điện thoại thật phải dùng IP LAN của máy chạy backend (điện thoại và máy tính
cùng mạng Wi-Fi):

```powershell
flutter run --dart-define=SMART_AGRI_API_URL=http://192.168.1.10:8000/predict
```

Thay `192.168.1.10` bằng IPv4 thật của máy tính. Không dùng `127.0.0.1` trên
điện thoại vì địa chỉ đó trỏ về chính điện thoại.

Nếu dùng ngrok, truyền URL HTTPS theo cách tương tự:

```powershell
flutter run --dart-define=SMART_AGRI_API_URL=https://ten-mien-ngrok-cua-ban.ngrok-free.app/predict
```

## Kiểm thử

```powershell
python -m unittest discover -s tests -v
cd app\mobile
flutter analyze
flutter test
```

Nguồn chuyên môn của từng nhãn nằm trong
`app/agent/data/rice_knowledge.json`; danh mục mở rộng có 16 tài liệu chính
thống trong `data/knowledge/sources.json`. URL nguồn được giữ trong từng chunk
để agent có thể nêu xuất xứ thay vì trả lời như một hộp đen.
