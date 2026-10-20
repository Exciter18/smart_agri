import io
import re
from pathlib import Path

import torch
import torch.nn as nn
import joblib
import numpy as np
from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware 
from fastapi.responses import JSONResponse
from torchvision import models, transforms
from PIL import Image

app = FastAPI(title="Smart Agriculture Vision API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], 
    allow_credentials=True,
    allow_methods=["*"], 
    allow_headers=["*"], 
)

PROJECT_ROOT = Path(__file__).resolve().parents[2]
scaler = joblib.load(PROJECT_ROOT / 'scaler.pkl')
classes = joblib.load(PROJECT_ROOT / 'classes.pkl')
best_features = np.load(PROJECT_ROOT / 'best_features.npy')
svm_model = joblib.load(PROJECT_ROOT / 'svm_model.pkl')

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

num_classes = len(classes)
backbone = models.resnet50(weights=None)
num_ftrs = backbone.fc.in_features
backbone.fc = nn.Linear(num_ftrs, num_classes)

backbone.load_state_dict(
    torch.load(PROJECT_ROOT / 'fine_tuned_resnet.pth', map_location=device)
)

backbone = torch.nn.Sequential(*(list(backbone.children())[:-1]))
backbone.eval().to(device)

transform = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
])

def square_padding(image): 
    width, height = image.size
    max_dim = max(width, height)
    
    new_img = Image.new("RGB", (max_dim, max_dim), (0, 0, 0))
    
    left = (max_dim - width) // 2
    top = (max_dim - height) // 2
    
    new_img.paste(image, (left, top))
    return new_img

@app.post("/predict")
async def predict_disease(file: UploadFile = File(...)):
    try:
        image_data = await file.read()
        image = Image.open(io.BytesIO(image_data)).convert("RGB")
        
        padded_img = square_padding(image)
        img_tensor = transform(padded_img).unsqueeze(0).to(device)
        
        with torch.no_grad():
            features = backbone(img_tensor).view(1, -1).cpu().numpy()
            
        features_scaled = scaler.transform(features)
        features_optimized = features_scaled[:, best_features]
        
        pred_idx = svm_model.predict(features_optimized)[0]
        disease_name = classes[pred_idx]
        
        probabilities = svm_model.predict_proba(features_optimized)[0]
        confidence = float(np.max(probabilities) * 100)
        
        clean_name = disease_name.replace("Rice__", "").replace("_", " ")
        display_name = re.sub(r"([a-z])([A-Z])", r"\g<1> \g<2>", clean_name)
        
        if confidence < 50:
            display_name = "Unrecognized"
            severity = "Please retake image"
        else:
            severity = "Severe" if confidence > 80 else "Early stage"
        
        return JSONResponse(content={
            "disease": display_name,
            "confidence": round(confidence, 2),
            "severity": severity
        })
        
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)