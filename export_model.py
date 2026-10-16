import warnings
import joblib
import numpy as np
from sklearn.calibration import CalibratedClassifierCV
from sklearn.exceptions import ConvergenceWarning
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.preprocessing import StandardScaler
from sklearn.svm import LinearSVC

from dataset_splits import grouped_split_indices, load_grouped_feature_rows


SVM_MAX_ITER = 20000
SVM_TOL = 1e-3


def fit_linear_svc(X_train, y_train):
    model = LinearSVC(
        C=1.0,
        dual=False,
        max_iter=SVM_MAX_ITER,
        tol=SVM_TOL,
        class_weight="balanced",
        random_state=42,
    )
    with warnings.catch_warnings(record=True) as caught_warnings:
        warnings.simplefilter("always", ConvergenceWarning)
        model.fit(X_train, y_train)

    convergence_warnings = [
        warning
        for warning in caught_warnings
        if issubclass(warning.category, ConvergenceWarning)
    ]
    if convergence_warnings:
        raise RuntimeError(
            "LinearSVC did not converge after "
            f"{SVM_MAX_ITER} iterations (tol={SVM_TOL}). "
            "No model metrics or deployment artifacts should be treated as final."
        )
    return model


def build_calibrated_model(X_train, y_train, groups_train, feature_indices):
    X_selected = X_train[:, feature_indices]
    calibration_splitter = StratifiedGroupKFold(
        n_splits=3, shuffle=True, random_state=43
    )
    calibration_splits = list(
        calibration_splitter.split(X_selected, y_train, groups_train)
    )

    model = CalibratedClassifierCV(
        estimator=LinearSVC(
            C=1.0,
            dual=False,
            max_iter=SVM_MAX_ITER,
            tol=SVM_TOL,
            class_weight="balanced",
            random_state=42,
        ),
        method='sigmoid',
        cv=calibration_splits,
    )
    with warnings.catch_warnings(record=True) as caught_warnings:
        warnings.simplefilter("always", ConvergenceWarning)
        model.fit(X_selected, y_train)

    convergence_warnings = [
        warning
        for warning in caught_warnings
        if issubclass(warning.category, ConvergenceWarning)
    ]
    if convergence_warnings:
        raise RuntimeError(
            "At least one LinearSVC calibration fold did not converge. "
            "The deployment model was not exported."
        )
    return model


def fit_and_export_model(
    X_train, y_train, groups_train, classes, scaler, feature_indices
):
    model = build_calibrated_model(
        X_train, y_train, groups_train, feature_indices
    )
    joblib.dump(scaler, 'scaler.pkl')
    joblib.dump(np.asarray(classes), 'classes.pkl')
    np.save('best_features.npy', feature_indices)
    joblib.dump(model, 'svm_model.pkl')
    return model


def main():
    features, labels, groups = load_grouped_feature_rows()
    train_indices, _, _ = grouped_split_indices(labels, groups)
    classes = np.unique(labels)
    class_to_idx = {label: index for index, label in enumerate(classes)}
    y_train = np.asarray([class_to_idx[label] for label in labels[train_indices]])

    feature_indices = np.load("best_features.npy")
    if (
        feature_indices.size == 0
        or np.any(feature_indices < 0)
        or np.any(feature_indices >= features.shape[1])
    ):
        raise ValueError("best_features.npy is empty or contains invalid indices")

    scaler = StandardScaler()
    X_train = scaler.fit_transform(features[train_indices])
    fit_and_export_model(
        X_train,
        y_train,
        groups[train_indices],
        classes,
        scaler,
        feature_indices,
    )


if __name__ == "__main__":
    main()
