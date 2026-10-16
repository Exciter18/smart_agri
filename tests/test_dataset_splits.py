import unittest

import numpy as np

from dataset_splits import grouped_split_indices, source_group
from prepare_data import parse_annotation


class GroupedSplitTests(unittest.TestCase):
    def test_source_group_merges_crops_and_augmented_copies(self):
        first = r"classification_dataset\train\Rice__LeafSmut\sample.rf.abc123_crop_0.jpg"
        second = r"classification_dataset\val\Rice__LeafSmut\sample.rf.def456_crop_2.jpg"

        self.assertEqual(source_group(first), source_group(second))

    def test_source_group_merges_prefixed_variants(self):
        train_copy = r"rice\images\train\r6k_train_Blast_1040_jpg.rf.abc123.jpg"
        test_copy = r"rice\images\val\r6k_test_Blast_1040_jpg.rf.def456.jpg"

        self.assertEqual(source_group(train_copy), source_group(test_copy))

    def test_polygon_annotation_is_converted_to_its_bounding_box(self):
        annotation = parse_annotation(
            "2 0.1 0.2 0.8 0.2 0.8 0.9 0.1 0.9",
            "label.txt",
            1,
            9,
        )

        self.assertEqual(annotation[0], 2)
        np.testing.assert_allclose(annotation[1:], (0.45, 0.55, 0.7, 0.7))

    def test_bounding_box_touching_image_edge_is_preserved(self):
        annotation = parse_annotation(
            "2 0.1 0.5 0.2 0.4",
            "label.txt",
            1,
            9,
        )

        self.assertEqual(annotation[0], 2)
        np.testing.assert_allclose(annotation[1:], (0.1, 0.5, 0.2, 0.4))

    def test_splits_keep_source_groups_disjoint_and_cover_rows(self):
        labels = np.repeat(np.arange(3), 40)
        groups = np.asarray(
            [f"class-{label}-image-{index // 2}" for index, label in enumerate(labels)]
        )

        train, validation, test = grouped_split_indices(labels, groups)

        train_groups = set(groups[train])
        validation_groups = set(groups[validation])
        test_groups = set(groups[test])
        self.assertFalse(train_groups & validation_groups)
        self.assertFalse(train_groups & test_groups)
        self.assertFalse(validation_groups & test_groups)
        self.assertEqual(len(train) + len(validation) + len(test), len(labels))


if __name__ == "__main__":
    unittest.main()
