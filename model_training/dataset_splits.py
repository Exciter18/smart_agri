from pathlib import Path
import re

import numpy as np
import pandas as pd
from sklearn.model_selection import StratifiedGroupKFold
from torchvision.datasets import ImageFolder


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATASET_ROOT = PROJECT_ROOT / "classification_dataset"


def source_group(image_path):
    stem = Path(image_path).stem
    stem = re.sub(r"_crop_\d+$", "", stem)
    stem = re.sub(r"\.rf\.[0-9a-fA-F]+$", "", stem)
    stem = re.sub(r"^r6k_(?:train|test)_", "", stem, flags=re.IGNORECASE)
    return stem


def load_grouped_feature_rows():
    feature_frames = []
    labels = []
    groups = []

    for split in ("train", "val"):
        image_folder = ImageFolder(str(DATASET_ROOT / split))
        manifest_path = PROJECT_ROOT / f"{split}_manifest.csv"
        if not manifest_path.is_file():
            raise FileNotFoundError(
                f"{manifest_path} is missing. Run extract_features.py to rebuild "
                "the feature cache with its image manifest."
            )
        feature_frame = pd.read_csv(PROJECT_ROOT / f"{split}_features.csv")
        manifest = pd.read_csv(manifest_path)

        if "Target" not in feature_frame:
            raise ValueError(f"{split}_features.csv must include a Target column")
        if not {"ImagePath", "Target"}.issubset(manifest.columns):
            raise ValueError(f"{manifest_path} must include ImagePath and Target columns")
        if len(feature_frame) != len(manifest) or len(manifest) != len(image_folder.samples):
            raise ValueError(
                f"{split} feature rows ({len(feature_frame)}), manifest rows "
                f"({len(manifest)}), and current image count "
                f"({len(image_folder.samples)}) do not match. Run extract_features.py."
            )

        expected_paths = [Path(path).as_posix() for path, _ in image_folder.samples]
        expected_labels = np.asarray(
            [image_folder.classes[target] for _, target in image_folder.samples]
        )
        cached_labels = feature_frame["Target"].astype(str).to_numpy()
        manifest_labels = manifest["Target"].astype(str).to_numpy()
        if (
            manifest["ImagePath"].astype(str).tolist() != expected_paths
            or not np.array_equal(cached_labels, manifest_labels)
            or not np.array_equal(manifest_labels, expected_labels)
        ):
            raise ValueError(
                f"{split} feature manifest no longer matches the image files or "
                "feature rows. Run extract_features.py."
            )

        feature_frames.append(feature_frame.drop(columns="Target"))
        labels.extend(expected_labels)
        groups.extend(source_group(path) for path, _ in image_folder.samples)

    if list(feature_frames[0].columns) != list(feature_frames[1].columns):
        raise ValueError("Train and validation feature columns do not match")

    features = pd.concat(feature_frames, ignore_index=True).to_numpy(dtype=np.float32)
    return features, np.asarray(labels), np.asarray(groups)


def grouped_split_indices(labels, groups, random_state=42):
    labels = np.asarray(labels)
    groups = np.asarray(groups)
    dummy_features = np.zeros((len(labels), 1), dtype=np.uint8)

    outer_splitter = StratifiedGroupKFold(
        n_splits=5, shuffle=True, random_state=random_state
    )
    train_validation_indices, test_indices = next(
        outer_splitter.split(dummy_features, labels, groups)
    )

    inner_splitter = StratifiedGroupKFold(
        n_splits=5, shuffle=True, random_state=random_state + 1
    )
    train_relative_indices, validation_relative_indices = next(
        inner_splitter.split(
            dummy_features[train_validation_indices],
            labels[train_validation_indices],
            groups[train_validation_indices],
        )
    )

    train_indices = train_validation_indices[train_relative_indices]
    validation_indices = train_validation_indices[validation_relative_indices]

    train_groups = set(groups[train_indices])
    validation_groups = set(groups[validation_indices])
    test_groups = set(groups[test_indices])
    if (
        train_groups & validation_groups
        or train_groups & test_groups
        or validation_groups & test_groups
    ):
        raise RuntimeError("Source image groups overlap between dataset splits")

    return train_indices, validation_indices, test_indices
