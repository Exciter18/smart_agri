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
- Dùng thông tin ruộng đã lưu trên điện thoại làm bối cảnh ban đầu; agent chỉ hỏi
  những dữ kiện cần thiết còn thiếu cho nhãn bệnh đó.
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
.\.venv\Scripts\python.exe -m uvicorn app.api.api_server:app --host 127.0.0.1 --port 8000
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
.\.venv\Scripts\python.exe -m uvicorn app.api.api_server:app --host 127.0.0.1 --port 8000
```

Mở `http://127.0.0.1:8000/api-docs` để thử API và
`http://127.0.0.1:8000/health` để xem trạng thái.
`http://127.0.0.1:8000/agent/model-info` cho biết model ngôn ngữ, nhà cung cấp
và agent đang dùng API ngoài hay Ollama local.

### Demo từ xa qua ngrok (dùng chung API nhận diện và Rice Care)

Nhận diện và Rice Care đang được phục vụ bởi **cùng một backend** ở cổng 8000:
app gửi ảnh tới `/predict`, rồi gửi hội thoại tới `/agent/chat` trên chính host
đó. Không cần khởi chạy riêng API agent hoặc mở tunnel thứ hai.

**Chuẩn bị một lần**

1. Cài ngrok, đăng nhập và cấu hình token trên PC:
   `ngrok config add-authtoken <token-của-bạn>`.
2. Tài khoản ngrok phải được cấp domain cố định
   `jamison-noncollusive-tomasa.ngrok-free.dev`. Launcher sẽ báo lỗi nếu domain
   không thuộc tài khoản đang đăng nhập.
3. Nếu chưa tạo môi trường Python cho dự án, mở PowerShell tại thư mục gốc repo
   và chạy:
   ```powershell
   python -m venv .venv
   .\.venv\Scripts\python.exe -m pip install -r requirements.txt
   ```
4. Nếu chưa có model, chạy `ollama pull qwen2.5:3b`.
5. Chạy `Build Smart Agri Demo APK.bat`. Chép
   `app\mobile\build\app\outputs\flutter-apk\app-arm64-v8a-debug.apk` sang điện
   thoại Android rồi cài. Đây là APK debug; Android có thể yêu cầu cho phép cài
   ứng dụng từ nguồn này.
6. Mở app > **Analysis server**. URL mặc định là
   `https://jamison-noncollusive-tomasa.ngrok-free.dev/predict`. Nếu app đã lưu
   một URL cũ, nhập URL này và lưu một lần.

**Mỗi lần demo**

1. Trên PC, mở `Start Smart Agri Remote.bat` và để cửa sổ chạy. Launcher kiểm
   tra Python `.venv`, Ollama/model, backend và tunnel ngrok.
2. Trên điện thoại (không cần cùng Wi-Fi hay cắm USB), mở
   `https://jamison-noncollusive-tomasa.ngrok-free.dev/health`. Chỉ tiếp tục
   khi thấy phản hồi từ API.
3. Mở app, điền hồ sơ ruộng nếu cần, chụp/chọn ảnh lúa để nhận diện, rồi tiếp
   tục hội thoại Rice Care. Nhận diện và chat dùng chung một backend.
4. Giữ PC, Ollama, backend và ngrok hoạt động suốt buổi demo. Khi xong, đóng
   cửa sổ ngrok và backend để dừng tunnel/API. Ollama có thể vẫn chạy nền; có
   thể để đó nếu sẽ tiếp tục demo hoặc thoát Ollama từ biểu tượng khay hệ thống.

Ngrok làm API có thể truy cập qua Internet. Đây là endpoint demo, không có lớp
đăng nhập đầy đủ; chỉ chia sẻ URL với người tham gia demo và không gửi dữ liệu
nhạy cảm. Chưa xác minh tunnel thật hoặc quyền domain của tài khoản hiện tại
cho đến khi launcher chạy thành công.

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

Gửi multipart với trường `file`. Ứng dụng có thể gửi thêm trường `farm_context`
dưới dạng chuỗi JSON; chỉ gửi các giá trị đã nhập và trường biết chắc:

```json
{
  "rice_variety": "IR64",
  "age_days": 35,
  "growth_stage": "tillering",
  "recent_weather": "rainy_humid",
  "water_condition": "adequate",
  "nitrogen_use": "balanced",
  "previous_action": "Applied fertilizer"
}
```

Các giá trị lựa chọn phải dùng mã chuẩn: giai đoạn `seedling`, `tillering`,
`panicle_initiation`, `heading`, `ripening`; thời tiết `rainy_humid`, `normal`,
`dry_hot`; nước `waterlogged`, `adequate`, `dry`; phân đạm `recent_heavy`,
`balanced`, `none_recent`. Backend kiểm tra whitelist và kiểu dữ liệu trước khi
đưa các giá trị vào context phiên agent. Tên ruộng và diện tích chỉ lưu trên
điện thoại; tuổi cây và điều kiện ngoài ruộng nên được cập nhật khi thay đổi.
Snapshot context đã gửi cũng được lưu cùng lịch sử chẩn đoán trên thiết bị.

Kết quả gồm `class_id`, tên tiếng Việt,
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
  "confidence_score": 0.78,
  "initial_context": {
    "age_days": 35,
    "growth_stage": "tillering"
  }
}
```

## Chạy Flutter

Android Emulator truy cập backend trên máy chủ qua `10.0.2.2`:

```powershell
cd app\mobile
flutter pub get
flutter run --dart-define=SMART_AGRI_API_URL=http://10.0.2.2:8000/predict
```

Để demo bằng Android từ xa, dùng các bước trong mục **Demo từ xa qua ngrok** ở
trên. Chỉ cần build và cài APK một lần; những lần demo sau chỉ mở
`Start Smart Agri Remote.bat` trên PC.

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
