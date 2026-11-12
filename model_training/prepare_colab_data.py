"""Package the Smart Agri image data and current ResNet-SVM artifacts for Colab."""

from __future__ import annotations

import argparse
import json
import zipfile
from pathlib import Path

from torchvision.datasets import ImageFolder


PROJECT_ROOT = Path(__file__).resolve().parents[1]
EXPECTED_CLASSES = {
    "Rice__BacterialLeafBlight",
    "Rice__BrownSpot",
    "Rice__Healthy",
    "Rice__Hispa",
    "Rice__LeafBlast",
    "Rice__LeafScald",
    "Rice__LeafSmut",
    "Rice__NarrowBrownLeafSpot",
    "Rice__NeckBlast",
}
BASELINE_ARTIFACTS = (
    "fine_tuned_resnet.pth",
    "svm_model.pkl",
    "scaler.pkl",
    "classes.pkl",
    "best_features.npy",
)


def build_colab_archive(output: Path) -> None:
    dataset_root = PROJECT_ROOT / "classification_dataset"
    split_folders = {}
    for split in ("train", "val"):
        folder = ImageFolder(dataset_root / split)
        if set(folder.classes) != EXPECTED_CLASSES:
            raise ValueError(
                f"{split} must contain exactly the expected nine classes; "
                f"found {folder.classes}"
            )
        split_folders[split] = folder

    missing_artifacts = [
        filename
        for filename in BASELINE_ARTIFACTS
        if not (PROJECT_ROOT / filename).is_file()
    ]
    if missing_artifacts:
        raise FileNotFoundError(
            "Current ResNet-SVM artifacts are missing: "
            + ", ".join(missing_artifacts)
        )

    class_counts = {
        split: {
            class_name: sum(target == index for _, target in folder.samples)
            for index, class_name in enumerate(folder.classes)
        }
        for split, folder in split_folders.items()
    }
    files = [
        path
        for path in dataset_root.rglob("*")
        if path.is_file()
    ] + [PROJECT_ROOT / filename for filename in BASELINE_ARTIFACTS]
    archive_root = PROJECT_ROOT
    output = output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    manifest = {
        "dataset": "Smart Agri rice disease image classification",
        "splits": ["train", "val"],
        "classes": sorted(EXPECTED_CLASSES),
        "class_counts": class_counts,
        "baseline_artifacts": list(BASELINE_ARTIFACTS),
        "image_count": sum(len(folder.samples) for folder in split_folders.values()),
    }

    with zipfile.ZipFile(
        output, mode="w", compression=zipfile.ZIP_DEFLATED, compresslevel=1
    ) as archive:
        for file_path in files:
            archive.write(file_path, file_path.relative_to(archive_root).as_posix())
        archive.writestr(
            "colab_bundle_manifest.json",
            json.dumps(manifest, indent=2, ensure_ascii=False),
        )

    print(f"Created: {output}")
    print(f"Images: {manifest['image_count']:,}")
    print(f"Archive size: {output.stat().st_size / (1024 ** 3):.2f} GiB")
    print("Includes train/val images and the five current ResNet-SVM artifacts.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path.home() / "Downloads" / "smart_agri_colab_data.zip",
        help="Output zip path (default: Downloads/smart_agri_colab_data.zip)",
    )
    args = parser.parse_args()
    build_colab_archive(args.output)


if __name__ == "__main__":
    main()
