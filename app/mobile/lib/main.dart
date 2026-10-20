import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;

void main() {
  runApp(const SmartAgriApp());
}

class SmartAgriApp extends StatelessWidget {
  const SmartAgriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Nông Nghiệp',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const VisionScreen(),
    );
  }
}

class VisionScreen extends StatefulWidget {
  const VisionScreen({super.key});

  @override
  State<VisionScreen> createState() => _VisionScreenState();
}

class _VisionScreenState extends State<VisionScreen> {
  File? _image;
  Uint8List? _imageBytes;
  bool _isLoading = false;
  String? _predictionResult;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      var bytes = await pickedFile.readAsBytes();
      setState(() {
        _image = File(pickedFile.path);
        _imageBytes = bytes;
        _predictionResult = null; // Xóa kết quả cũ khi chọn ảnh mới
      });
    }
  }

  Future<void> _analyzeImage() async {
    if (_imageBytes == null && _image == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      var uri = Uri.parse(
        "https://jamison-noncollusive-tomasa.ngrok-free.dev/predict",
      );
      var request = http.MultipartRequest('POST', uri);
      request.headers['ngrok-skip-browser-warning'] = 'true';

      if (kIsWeb) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            _imageBytes!,
            filename: 'upload.jpg',
          ),
        );
      } else {
        request.files.add(
          await http.MultipartFile.fromPath('file', _image!.path),
        );
      }

      var response = await request.send();
      if (response.statusCode == 200) {
        var responseData = await response.stream.bytesToString();
        var result = json.decode(responseData);

        setState(() {
          _predictionResult = _predictionResult =
              "Disease: ${result['disease']}\nConfidence: ${result['confidence']}%\nSeverity: ${result['severity']}";
        });
      } else {
        setState(() {
          _predictionResult = "Lỗi Server: Mã ${response.statusCode}";
        });
      }
    } catch (e) {
      setState(() {
        _predictionResult =
            "Không thể kết nối tới Server.\nVui lòng kiểm tra lại link Ngrok.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Chẩn đoán Bệnh Lúa',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                height: 300,
                width: 300,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _imageBytes == null
                    ? const Center(child: Text('Chưa có ảnh nào được chọn.'))
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: kIsWeb
                            ? Image.memory(_imageBytes!, fit: BoxFit.cover)
                            : Image.file(_image!, fit: BoxFit.cover),
                      ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Chụp ảnh'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Thư viện'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Nút Gửi API
              ElevatedButton(
                onPressed: (_imageBytes == null || _isLoading)
                    ? null
                    : _analyzeImage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 15,
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        '🔍 TIẾN HÀNH PHÂN TÍCH',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),

              const SizedBox(height: 30),

              // Khung hiển thị kết quả JSON
              if (_predictionResult != null)
                Container(
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Text(
                    _predictionResult!,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
