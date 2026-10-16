import unittest

import numpy as np

from export_model import SVM_MAX_ITER, fit_linear_svc, build_calibrated_model


class CalibratedModelTests(unittest.TestCase):
    def test_linear_svc_converges_with_selected_tolerance(self):
        rng = np.random.default_rng(21)
        labels = np.repeat(np.arange(3), 30)
        features = rng.normal(size=(len(labels), 8)).astype(np.float32)
        features[:, 0] += labels * 2.0

        model = fit_linear_svc(features, labels)

        self.assertLess(int(np.max(np.asarray(model.n_iter_))), SVM_MAX_ITER)

    def test_model_returns_normalized_probabilities(self):
        rng = np.random.default_rng(42)
        labels = np.repeat(np.arange(3), 30)
        groups = np.asarray(
            [f"class-{label}-image-{index // 2}" for index, label in enumerate(labels)]
        )
        features = rng.normal(size=(len(labels), 6)).astype(np.float32)
        features[:, 0] += labels * 1.5

        model = build_calibrated_model(
            features, labels, groups, np.arange(features.shape[1])
        )
        probabilities = model.predict_proba(features[:6])

        self.assertEqual(probabilities.shape, (6, 3))
        np.testing.assert_allclose(probabilities.sum(axis=1), 1.0, atol=1e-6)


if __name__ == "__main__":
    unittest.main()
