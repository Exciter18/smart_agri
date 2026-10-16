import torch
import pandas as pd
import numpy as np
from pathlib import Path
from torchvision import models, transforms
from torch.utils.data import DataLoader
from torchvision.datasets import ImageFolder
import torch.nn as nn

PROJECT_ROOT = Path(__file__).resolve().parents[1]
TRAIN_DIR = PROJECT_ROOT / "classification_dataset" / "train"
VAL_DIR = PROJECT_ROOT / "classification_dataset" / "val"

def get_feature_extractor(
    num_classes, model_path=PROJECT_ROOT / "fine_tuned_resnet.pth", device="cpu"
):
    model = models.resnet50(weights=None)
    num_ftrs = model.fc.in_features
    model.fc = nn.Linear(num_ftrs, num_classes)
    
    model.load_state_dict(torch.load(model_path, map_location=device))
    
    model = torch.nn.Sequential(*(list(model.children())[:-1]))
    model.eval()
    
    return model

def extract_features(data_loader, model, device):
    features = []
    labels = []
    image_paths = [path for path, _ in data_loader.dataset.samples]
    class_names = data_loader.dataset.classes
    
    with torch.no_grad():
        for inputs, targets in data_loader:
            inputs = inputs.to(device)
            outputs = model(inputs)
            outputs = outputs.view(outputs.size(0), -1)
            
            features.extend(outputs.cpu().numpy())
            for t in targets:
                labels.append(class_names[t.item()])
                
    return np.array(features), np.array(labels), image_paths

def save_feature_data(split, features, labels, image_paths):
    feature_frame = pd.DataFrame(features)
    feature_frame['Target'] = labels
    feature_frame.to_csv(PROJECT_ROOT / f"{split}_features.csv", index=False)

    manifest = pd.DataFrame({
        'ImagePath': [Path(path).as_posix() for path in image_paths],
        'Target': labels,
    })
    manifest.to_csv(PROJECT_ROOT / f"{split}_manifest.csv", index=False)

def main():
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Su dung thiet bi: {device}")
    
    transform = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
    ])
    
    print("Dang chuan bi du lieu...")
    train_dataset = ImageFolder(TRAIN_DIR, transform=transform)
    val_dataset = ImageFolder(VAL_DIR, transform=transform)
    
    num_classes = len(train_dataset.classes)
    
    train_loader = DataLoader(train_dataset, batch_size=32, shuffle=False)
    val_loader = DataLoader(val_dataset, batch_size=32, shuffle=False)
    
    print("Nap mo hinh ResNet50 da Fine-tune...")
    model = get_feature_extractor(
        num_classes, PROJECT_ROOT / "fine_tuned_resnet.pth", device
    ).to(device)
    
    print("Dang trich xuat dac trung tap Train...")
    train_features, train_labels, train_paths = extract_features(
        train_loader, model, device
    )
    save_feature_data('train', train_features, train_labels, train_paths)
    
    print("Dang trich xuat dac trung tap Val...")
    val_features, val_labels, val_paths = extract_features(
        val_loader, model, device
    )
    save_feature_data('val', val_features, val_labels, val_paths)
    
    print("Hoan tat trich xuat.")

if __name__ == '__main__':
    main()