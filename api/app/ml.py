"""Carga de modelos entrenados y prediccion batch."""
from __future__ import annotations

import os
from pathlib import Path

import joblib
import numpy as np

from .preprocessing import build_feature_frame

# Ubicacion de los .pkl. Por defecto apunta al repo ML clonado en ../ml_model/models.
# Se puede sobreescribir con la variable de entorno PETMATCHER_MODELS_DIR.
DEFAULT_MODELS_DIR = Path(__file__).resolve().parents[2] / "ml_model" / "models"
MODELS_DIR = Path(os.environ.get("PETMATCHER_MODELS_DIR", DEFAULT_MODELS_DIR))

MODEL_FILES = {
    "Regresion Lineal": MODELS_DIR / "regresion_lineal.pkl",
    "KNN": MODELS_DIR / "knn.pkl",
    "Arbol de Decision": MODELS_DIR / "arbol_decision.pkl",
    "HistGradientBoosting": MODELS_DIR / "hist_gradient_boosting.pkl",
}

# Como se calcula la efectividad final:
#   ""            -> promedio de TODOS los modelos cargados (default)
#   <nombre>      -> usa solo ese modelo (p.ej. "HistGradientBoosting")
# `por_modelo` en la respuesta siempre muestra todos, sirva cual sirva.
#
# Rendimiento medido sobre dataset_synthetic (GroupKFold por paciente):
#   promedio de 3 (sin HistGB) .... R2 0.606  top-1 49.5%
#   promedio de 4 ................. R2 0.648  top-1 57.5%   <- default
#   solo HistGradientBoosting ..... R2 0.666  top-1 63.7%
PREDICT_MODEL = os.environ.get("PETMATCHER_PREDICT_MODEL", "").strip()

_MODELS: dict = {}


def load_models() -> list[str]:
    """Carga en memoria los modelos que existan en MODELS_DIR.

    Devuelve la lista de archivos ausentes, a titulo informativo: un directorio
    con solo los 3 modelos originales (sin HistGradientBoosting) sigue siendo
    valido y el servicio arranca igual.
    """
    _MODELS.clear()
    faltantes = []
    for nombre, path in MODEL_FILES.items():
        if path.exists():
            _MODELS[nombre] = joblib.load(path)
        else:
            faltantes.append(str(path))
    return faltantes


def models_loaded() -> bool:
    """Hay servicio si se cargo al menos un modelo."""
    return len(_MODELS) > 0


def loaded_model_names() -> list[str]:
    return list(_MODELS)


def _clamp(v: float) -> float:
    return float(max(0.0, min(100.0, v)))


def interpretar(valor: float) -> str:
    if valor >= 80:
        return "alta"
    if valor >= 60:
        return "media"
    if valor >= 40:
        return "baja"
    return "no_recomendado"


def predict_batch(patient: dict, animals: list[dict]) -> list[dict]:
    """Para un paciente y N animales, devuelve el ranking ordenado desc. por efectividad.

    Cada animal se combina con el perfil del paciente en una fila y se predice de
    forma vectorizada con todos los modelos cargados. La efectividad final es el
    promedio, salvo que PETMATCHER_PREDICT_MODEL fije uno solo.
    """
    if not models_loaded():
        raise RuntimeError("Modelos no cargados. Verifica PETMATCHER_MODELS_DIR / .pkl")
    if not animals:
        return []

    rows = [{**patient, **animal} for animal in animals]
    x = build_feature_frame(rows)

    # Prediccion vectorizada por modelo -> matriz (n_modelos, n_animales)
    preds_por_modelo = {nombre: modelo.predict(x) for nombre, modelo in _MODELS.items()}
    if PREDICT_MODEL and PREDICT_MODEL in preds_por_modelo:
        promedio = preds_por_modelo[PREDICT_MODEL]
    else:
        matriz = np.vstack([preds_por_modelo[n] for n in _MODELS])  # (n_modelos, N)
        promedio = matriz.mean(axis=0)

    resultados = []
    for i, animal in enumerate(animals):
        efectividad = _clamp(float(promedio[i]))
        resultados.append(
            {
                "animal_id": animal.get("id"),
                "efectividad": round(efectividad, 2),
                "categoria": interpretar(efectividad),
                "por_modelo": {
                    nombre: round(_clamp(float(preds_por_modelo[nombre][i])), 2)
                    for nombre in _MODELS
                },
            }
        )

    resultados.sort(key=lambda r: r["efectividad"], reverse=True)
    return resultados
