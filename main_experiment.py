import pandas as pd
import numpy as np
import os
import matplotlib.pyplot as plt
import seaborn as sns

from sklearn.linear_model import RidgeClassifier
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, confusion_matrix, classification_report
from sklearn.preprocessing import StandardScaler
from optimizers import BinaryPSO, BinaryGA, BinaryGWO, BinaryWOA, BinarySCA
from dataset_splits import grouped_split_indices, load_grouped_feature_rows
from export_model import SVM_MAX_ITER, SVM_TOL, fit_and_export_model, fit_linear_svc
import time


def load_and_scale_data():
    features, labels, groups = load_grouped_feature_rows()
    train_indices, val_indices, test_indices = grouped_split_indices(labels, groups)

    classes = np.unique(labels)
    class_to_idx = {cls: idx for idx, cls in enumerate(classes)}
    y = np.asarray([class_to_idx[label] for label in labels])

    X_train = features[train_indices]
    X_val = features[val_indices]
    X_test = features[test_indices]
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_val_scaled = scaler.transform(X_val)
    X_test_scaled = scaler.transform(X_test)

    return (
        X_train_scaled,
        y[train_indices],
        X_val_scaled,
        y[val_indices],
        X_test_scaled,
        y[test_indices],
        groups[train_indices],
        classes,
        scaler,
    )

def create_fitness_function(X_train, y_train, X_val, y_val):
    def fitness(solution):
        selected_features = np.where(solution == 1)[0]
        
        if len(selected_features) == 0:
            return 1.0
            
        X_train_sel = X_train[:, selected_features]
        X_val_sel = X_val[:, selected_features]
        
        clf = RidgeClassifier(class_weight='balanced')
        clf.fit(X_train_sel, y_train)
        preds = clf.predict(X_val_sel)
        
        error_rate = 1.0 - f1_score(y_val, preds, average='macro', zero_division=0)
        
        alpha = 0.99
        beta = 0.01
        total_features = X_train.shape[1]
        
        fitness_value = alpha * error_rate + beta * (len(selected_features) / total_features)
        return fitness_value
        
    return fitness

def evaluate_model(
    X_train, y_train, X_val, y_val, selected_features=None, X_test=None
):
    if selected_features is not None:
        X_train = X_train[:, selected_features]
        X_val = X_val[:, selected_features]
        if X_test is not None:
            X_test = X_test[:, selected_features]

    clf = fit_linear_svc(X_train, y_train)
    preds = clf.predict(X_val)
    test_preds = clf.predict(X_test) if X_test is not None else None
    
    metrics = {
        'Accuracy': accuracy_score(y_val, preds),
        'Precision': precision_score(y_val, preds, average='weighted', zero_division=0),
        'Recall': recall_score(y_val, preds, average='weighted', zero_division=0),
        'F1-Score': f1_score(y_val, preds, average='weighted', zero_division=0),
        'Macro-F1': f1_score(y_val, preds, average='macro', zero_division=0),
        'SVM Iterations': int(np.max(np.asarray(clf.n_iter_))),
    }
    return metrics, preds, test_preds

def run_algorithm(
    algo_class, algo_name, pop_size, num_features, max_iter, fitness_func,
    X_train, y_train, X_val, y_val, X_test
):
    print(f"\n--- Dang chay Binary {algo_name} ---", flush=True)
    start_time = time.time()
    optimizer = algo_class(pop_size, num_features, max_iter, fitness_func)
    best_pos, curve = optimizer.optimize()
    
    features_idx = np.where(best_pos == 1)[0]
    if len(features_idx) == 0:
        features_idx = np.arange(num_features)
    
    metrics, preds, test_preds = evaluate_model(
        X_train, y_train, X_val, y_val, features_idx, X_test
    )
    exec_time = time.time() - start_time
    
    result_dict = {
        'Model': f'{algo_name}-SVM',
        'Features Used': len(features_idx),
        'Accuracy': metrics['Accuracy'],
        'F1-Score': metrics['F1-Score'],
        'Macro-F1': metrics['Macro-F1'],
        'SVM Iterations': metrics['SVM Iterations'],
        'Time (s)': round(exec_time, 2)
    }
    
    return result_dict, curve, metrics['Macro-F1'], features_idx, test_preds

def generate_charts(df_results, curves, cm, y_test, best_preds, classes, best_model_name):
    # 1. Bieu do hoi tu (Convergence Curve)
    plt.figure(figsize=(10, 6))
    for name, curve in curves.items():
        plt.plot(curve, label=name, linewidth=2)
    plt.title('Convergence Curves of Metaheuristic Algorithms')
    plt.xlabel('Iteration')
    plt.ylabel('Fitness Value (Lower is better)')
    plt.legend()
    plt.grid(True)
    plt.tight_layout()
    plt.savefig('report_results/1_Convergence_Curve.png', dpi=300)
    
    # 2. Ma tran nham lan (Confusion Matrix)
    plt.figure(figsize=(10, 8))
    sns.heatmap(cm, annot=True, fmt='d', cmap='Blues', xticklabels=classes, yticklabels=classes)
    plt.title(f'Held-out Test Confusion Matrix ({best_model_name})')
    plt.xlabel('Predicted Label')
    plt.ylabel('True Label')
    plt.xticks(rotation=45, ha='right')
    plt.tight_layout()
    plt.savefig('report_results/2_Confusion_Matrix.png', dpi=300)
    
    # 3. So sanh hieu suat Accuracy va F1-Score
    df_metrics = df_results.melt(id_vars='Model', value_vars=['Accuracy', 'F1-Score'], var_name='Metric', value_name='Score')
    plt.figure(figsize=(10, 6))
    sns.barplot(data=df_metrics, x='Model', y='Score', hue='Metric', palette='Set2')
    plt.title('Validation Performance Comparison')
    plt.ylim(0.0, 1.0)
    plt.ylabel('Score')
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    plt.tight_layout()
    plt.savefig('report_results/3_Performance_Comparison.png', dpi=300)
    
    # 4. So sanh so luong dac trung duoc giu lai
    plt.figure(figsize=(10, 6))
    ax = sns.barplot(data=df_results, x='Model', y='Features Used', palette='viridis')
    plt.title('Feature Reduction by Metaheuristic Algorithms')
    plt.ylabel('Number of Features')
    
    for p in ax.patches:
        ax.annotate(f'{int(p.get_height())}', (p.get_x() + p.get_width() / 2., p.get_height()), 
                    ha='center', va='bottom', fontsize=10, color='black', xytext=(0, 5), 
                    textcoords='offset points')
                    
    plt.tight_layout()
    plt.savefig('report_results/4_Feature_Reduction.png', dpi=300)
    
    # 5. Ban do nhiet chi so chi tiet (Classification Report)
    report_dict = classification_report(
        y_test,
        best_preds,
        labels=np.arange(len(classes)),
        target_names=classes,
        output_dict=True,
        zero_division=0,
    )
    pd.DataFrame(report_dict).transpose().to_csv('report_results/test_metrics.csv')
    report_df = pd.DataFrame(report_dict).iloc[:len(classes), :3]
    
    plt.figure(figsize=(10, 6))
    sns.heatmap(report_df, annot=True, cmap='YlGnBu', vmin=0.0, vmax=1.0, fmt='.3f')
    plt.title(f'Held-out Test Metrics per Class ({best_model_name})')
    plt.tight_layout()
    plt.savefig('report_results/5_Classification_Report_Heatmap.png', dpi=300)

def main():
    np.random.seed(42)
    os.makedirs('report_results', exist_ok=True)
    (
        X_train, y_train, X_val, y_val, X_test, y_test,
        groups_train, classes, scaler
    ) = load_and_scale_data()
    num_features = X_train.shape[1]
    
    fitness_func = create_fitness_function(X_train, y_train, X_val, y_val)
    results_summary = []
    curves = {}
    
    best_optimizer_macro_f1 = -1.0
    best_model_name = ""
    best_features = None
    best_test_preds = None
    
    print(
        f"\n--- Baseline SVM (Full {num_features} Features; "
        f"max_iter={SVM_MAX_ITER}, tol={SVM_TOL}) ---",
        flush=True,
    )
    start_time = time.time()
    base_metrics, _, baseline_test_preds = evaluate_model(
        X_train, y_train, X_val, y_val, X_test=X_test
    )
    base_time = time.time() - start_time
    print(
        f"Baseline converged in {base_metrics['SVM Iterations']} iterations "
        f"({base_time:.1f}s).",
        flush=True,
    )
    
    results_summary.append({
        'Model': 'Baseline SVM',
        'Features Used': num_features,
        'Accuracy': base_metrics['Accuracy'],
        'F1-Score': base_metrics['F1-Score'],
        'Macro-F1': base_metrics['Macro-F1'],
        'SVM Iterations': base_metrics['SVM Iterations'],
        'Time (s)': round(base_time, 2)
    })
    pd.DataFrame(results_summary).to_csv(
        'report_results/Algorithm_Comparison.csv', index=False
    )
    
    pop_size = 10
    max_iter = 15
    
    algorithms = {
        'PSO': BinaryPSO,
        'GA': BinaryGA,
        'GWO': BinaryGWO,
        'WOA': BinaryWOA,
        'SCA': BinarySCA
    }
    
    for name, algo_class in algorithms.items():
        res_dict, curve, macro_f1, features_idx, test_preds = run_algorithm(
            algo_class, name, pop_size, num_features, max_iter, fitness_func, 
            X_train, y_train, X_val, y_val, X_test
        )
        
        results_summary.append(res_dict)
        curves[name] = curve
        pd.DataFrame(results_summary).to_csv(
            'report_results/Algorithm_Comparison.csv', index=False
        )
        
        if macro_f1 > best_optimizer_macro_f1:
            best_optimizer_macro_f1 = macro_f1
            best_features = features_idx
            best_test_preds = test_preds
            best_model_name = f"{name}-SVM"

    df_results = pd.DataFrame(results_summary)
    df_results.to_csv('report_results/Algorithm_Comparison.csv', index=False)
    
    print(df_results.to_string(index=False))

    if best_features is None or best_test_preds is None:
        raise RuntimeError("No feature-optimized model was produced.")
    np.save('best_features.npy', best_features)

    test_models = [
        ("Baseline SVM", baseline_test_preds),
        (best_model_name, best_test_preds),
    ]
    test_summaries = []
    for model_name, predictions in test_models:
        test_summaries.append({
            'Model': model_name,
            'Accuracy': accuracy_score(y_test, predictions),
            'Weighted-F1': f1_score(
                y_test, predictions, average='weighted', zero_division=0
            ),
            'Macro-F1': f1_score(
                y_test, predictions, average='macro', zero_division=0
            ),
        })
    pd.DataFrame(test_summaries).to_csv(
        'report_results/held_out_test_summary.csv', index=False
    )

    best_test_report = classification_report(
        y_test,
        best_test_preds,
        labels=np.arange(len(classes)),
        target_names=classes,
        output_dict=True,
        zero_division=0,
    )
    pd.DataFrame(best_test_report).transpose().to_csv(
        'report_results/test_metrics.csv'
    )
    baseline_test_report = classification_report(
        y_test,
        baseline_test_preds,
        labels=np.arange(len(classes)),
        target_names=classes,
        output_dict=True,
        zero_division=0,
    )
    pd.DataFrame(baseline_test_report).transpose().to_csv(
        'report_results/baseline_test_metrics.csv'
    )

    print("\nHeld-out test comparison (same split and converged LinearSVC):")
    print(pd.DataFrame(test_summaries).to_string(index=False))
    print(
        f"\nSelected deployment model by validation Macro-F1: "
        f"{best_model_name} ({best_optimizer_macro_f1:.4f})"
    )
    fit_and_export_model(
        X_train, y_train, groups_train, classes, scaler, best_features
    )

    cm = confusion_matrix(
        y_test, best_test_preds, labels=np.arange(len(classes))
    )
    generate_charts(
        df_results, curves, cm, y_test, best_test_preds, classes, best_model_name
    )
    

if __name__ == '__main__':
    main()