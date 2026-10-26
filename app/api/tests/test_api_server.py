import io
import unittest

from fastapi.testclient import TestClient
from PIL import Image

from app.api.api_server import (
    MAX_IMAGE_BYTES,
    PredictionResponse,
    create_app,
)


def image_bytes() -> bytes:
    output = io.BytesIO()
    Image.new("RGB", (8, 8), color="green").save(output, format="PNG")
    return output.getvalue()


class PredictionApiTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(
            create_app(
                predictor=lambda _: PredictionResponse(
                    disease="Leaf Blast",
                    confidence=99.5,
                )
            )
        )

    def test_success_returns_only_disease_and_confidence(self):
        response = self.client.post(
            "/predict",
            files={"file": ("leaf.png", image_bytes(), "image/png")},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json(),
            {"disease": "Leaf Blast", "confidence": 99.5},
        )
        self.assertNotIn("severity", response.json())

    def test_low_confidence_does_not_replace_the_predicted_disease(self):
        app = create_app(
            predictor=lambda _: PredictionResponse(
                disease="Leaf Blast",
                confidence=12.5,
            )
        )
        response = TestClient(app).post(
            "/predict",
            files={"file": ("leaf.png", image_bytes(), "image/png")},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["disease"], "Leaf Blast")
        self.assertEqual(response.json()["confidence"], 12.5)

    def test_empty_image_returns_a_client_error(self):
        response = self.client.post(
            "/predict",
            files={"file": ("empty.png", b"", "image/png")},
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"]["code"], "empty_image")

    def test_invalid_image_returns_a_client_error(self):
        response = self.client.post(
            "/predict",
            files={"file": ("invalid.png", b"not an image", "image/png")},
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"]["code"], "invalid_image")

    def test_oversized_image_is_rejected_before_prediction(self):
        def unexpected_prediction(_):
            self.fail("Oversized uploads must not reach the model.")

        client = TestClient(create_app(predictor=unexpected_prediction))
        response = client.post(
            "/predict",
            files={"file": ("large.png", b"x" * (MAX_IMAGE_BYTES + 1), "image/png")},
        )

        self.assertEqual(response.status_code, 413)
        self.assertEqual(response.json()["error"]["code"], "image_too_large")

    def test_image_with_unsupported_dimensions_is_rejected(self):
        output = io.BytesIO()
        Image.new("RGB", (5001, 5000), color="green").save(output, format="PNG")
        client = TestClient(
            create_app(
                predictor=lambda _: self.fail(
                    "Images with unsupported dimensions must not reach the model."
                )
            )
        )
        response = client.post(
            "/predict",
            files={"file": ("large-dimensions.png", output.getvalue(), "image/png")},
        )

        self.assertEqual(response.status_code, 413)
        self.assertEqual(
            response.json()["error"]["code"],
            "image_dimensions_too_large",
        )

    def test_prediction_failure_returns_a_generic_server_error(self):
        def fail_prediction(_):
            raise RuntimeError("private model details")

        client = TestClient(create_app(predictor=fail_prediction))
        with self.assertLogs("app.api.api_server", level="ERROR"):
            response = client.post(
                "/predict",
                files={"file": ("leaf.png", image_bytes(), "image/png")},
            )

        self.assertEqual(response.status_code, 500)
        self.assertEqual(response.json()["error"]["code"], "prediction_failed")
        self.assertNotIn("private model details", response.text)

    def test_invalid_model_confidence_is_reported_as_a_server_error(self):
        client = TestClient(
            create_app(
                predictor=lambda _: PredictionResponse(
                    disease="Leaf Blast",
                    confidence=120,
                )
            )
        )
        with self.assertLogs("app.api.api_server", level="ERROR"):
            response = client.post(
                "/predict",
                files={"file": ("leaf.png", image_bytes(), "image/png")},
            )

        self.assertEqual(response.status_code, 500)
        self.assertEqual(response.json()["error"]["code"], "prediction_failed")

    def test_missing_file_returns_a_validation_error(self):
        response = self.client.post("/predict")

        self.assertEqual(response.status_code, 422)

if __name__ == "__main__":
    unittest.main()
