import os
import math
from pathlib import Path

import cv2
import yaml


def parse_annotation(line, source, line_number, class_count):
    parts = line.split()
    if not parts:
        return None

    try:
        class_id = int(parts[0])
        coordinates = [float(value) for value in parts[1:]]
    except ValueError as exc:
        raise ValueError(f"Invalid annotation at {source}:{line_number}") from exc

    if class_id < 0 or class_id >= class_count:
        raise ValueError(f"Class ID out of range at {source}:{line_number}")
    if any(not math.isfinite(value) for value in coordinates):
        raise ValueError(f"Non-finite coordinate at {source}:{line_number}")

    if len(coordinates) == 4:
        x_center, y_center, width, height = coordinates
    elif len(coordinates) >= 6 and len(coordinates) % 2 == 0:
        x_values = coordinates[0::2]
        y_values = coordinates[1::2]
        if any(value < 0 or value > 1 for value in coordinates):
            raise ValueError(f"Polygon coordinate out of range at {source}:{line_number}")
        x_min, x_max = min(x_values), max(x_values)
        y_min, y_max = min(y_values), max(y_values)
        x_center = (x_min + x_max) / 2
        y_center = (y_min + y_max) / 2
        width = x_max - x_min
        height = y_max - y_min
    else:
        raise ValueError(f"Expected a box or polygon at {source}:{line_number}")

    if width <= 0 or height <= 0:
        raise ValueError(f"Degenerate bounding box at {source}:{line_number}")

    x_min = x_center - width / 2
    y_min = y_center - height / 2
    x_max = x_center + width / 2
    y_max = y_center + height / 2
    if x_min < -1e-6 or y_min < -1e-6 or x_max > 1 + 1e-6 or y_max > 1 + 1e-6:
        raise ValueError(f"Bounding box out of range at {source}:{line_number}")

    x_min = max(0.0, x_min)
    y_min = max(0.0, y_min)
    x_max = min(1.0, x_max)
    y_max = min(1.0, y_max)
    return (
        class_id,
        (x_min + x_max) / 2,
        (y_min + y_max) / 2,
        x_max - x_min,
        y_max - y_min,
    )


def process_yolo_to_classification(base_dir, output_dir, allow_existing=False):
    output_root = Path(output_dir)
    image_extensions = {".jpg", ".jpeg", ".png"}
    existing_images = (
        path
        for path in output_root.rglob("*")
        if path.is_file() and path.suffix.lower() in image_extensions
    )
    if output_root.exists() and next(existing_images, None) is not None and not allow_existing:
        raise FileExistsError(
            f"{output_root} already contains crops. Choose a new output directory "
            "or pass allow_existing=True to merge results."
        )
    
    yaml_path = os.path.join(base_dir, 'data.yaml')
    with open(yaml_path, 'r', encoding='utf-8') as f:
        data_config = yaml.safe_load(f)
    
    classes = data_config.get('names', [])
    if isinstance(classes, dict):
        classes = [classes[i] for i in range(len(classes))]
        
    print(f"Tim thay {len(classes)} classes: {classes}")

    for split in ['train', 'val']:
        for cls_name in classes:
            os.makedirs(os.path.join(output_dir, split, cls_name), exist_ok=True)

    for split in ['train', 'val']:
        img_dir = os.path.join(base_dir, 'images', split)
        lbl_dir = os.path.join(base_dir, 'labels', split)
        
        if not os.path.exists(img_dir):
            continue
            
        print(f"Dang xu ly tap {split}...")
        
        for img_name in sorted(os.listdir(img_dir)):
            if not img_name.lower().endswith(('.jpg', '.jpeg', '.png')):
                continue
                
            img_path = os.path.join(img_dir, img_name)
            lbl_path = os.path.join(lbl_dir, os.path.splitext(img_name)[0] + '.txt')
            
            if not os.path.exists(lbl_path):
                raise FileNotFoundError(f"Missing annotation file: {lbl_path}")
                
            img = cv2.imread(img_path)
            if img is None:
                raise OSError(f"Could not read image: {img_path}")
                
            h, w, _ = img.shape
            
            with open(lbl_path, 'r') as f:
                lines = f.readlines()
                
            for idx, line in enumerate(lines):
                annotation = parse_annotation(
                    line, lbl_path, idx + 1, len(classes)
                )
                if annotation is None:
                    continue

                class_id, x_center, y_center, box_w, box_h = annotation
                x1 = max(0, math.floor((x_center - box_w / 2) * w))
                y1 = max(0, math.floor((y_center - box_h / 2) * h))
                x2 = min(w, math.ceil((x_center + box_w / 2) * w))
                y2 = min(h, math.ceil((y_center + box_h / 2) * h))

                if x2 <= x1 or y2 <= y1:
                    continue

                crop_img = img[y1:y2, x1:x2]
                class_name = classes[class_id]
                save_name = f"{os.path.splitext(img_name)[0]}_crop_{idx}.jpg"
                save_path = os.path.join(output_dir, split, class_name, save_name)
                if not cv2.imwrite(save_path, crop_img):
                    raise OSError(f"Could not write crop: {save_path}")

if __name__ == '__main__':
    PROJECT_ROOT = Path(__file__).resolve().parents[1]
    BASE_DIR = PROJECT_ROOT / 'rice'
    OUTPUT_DIR = PROJECT_ROOT / 'classification_dataset'
    
    process_yolo_to_classification(BASE_DIR, OUTPUT_DIR)
    print("Da cat va phan loai anh xong!")