"""Preprocesado replicado EXACTAMENTE del modelo original (ml_model/app.py).

No modificar mapeos ni orden de columnas sin re-verificar contra train.py / app.py
del repo https://github.com/Sebalfonsos/petmatcherMLMODEL, o las predicciones serian
invalidas. Ver plan.md seccion 2.1 y 11.
"""
from __future__ import annotations

import pandas as pd

from .adhd_rs import features_modelo

# Catalogo identico al del modelo original. La indexacion de 'raza' y
# 'tipo_entrenamiento' depende de sorted(set(...)) sobre estos valores.
CATALOGO_ANIMALES = {
    "perro": {
        "razas": ["labrador retriever", "golden retriever", "border collie", "beagle", "mestizo"],
        "entrenamientos": [
            "apoyo emocional",
            "obediencia terapeutica",
            "acompanamiento en tdah",
            "regulacion conductual",
        ],
    },
    "gato": {
        "razas": ["mestizo", "siames", "persa", "ragdoll"],
        "entrenamientos": [
            "acompanamiento emocional",
            "reduccion de ansiedad",
            "estimulacion sensorial suave",
        ],
    },
    "conejo": {
        "razas": ["mini lop", "holandes", "cabeza de leon"],
        "entrenamientos": [
            "estimulacion sensorial",
            "acompanamiento tranquilo",
            "reduccion de estres",
        ],
    },
    "caballo": {
        "razas": ["criollo", "cuarto de milla", "pony", "andaluz"],
        "entrenamientos": [
            "equinoterapia",
            "estimulacion motora",
            "regulacion emocional",
            "trabajo de confianza",
        ],
    },
}


def build_label_mappings():
    razas = []
    entrenamientos = []
    for tipo_data in CATALOGO_ANIMALES.values():
        razas.extend(tipo_data["razas"])
        entrenamientos.extend(tipo_data["entrenamientos"])
    razas_unicas = sorted(set(razas))
    entrenamientos_unicos = sorted(set(entrenamientos))
    return {
        "sexo_paciente": {"masculino": 0, "femenino": 1},
        # Presentacion segun DSM-5 (ver adhd_rs.py). El orden es parte del contrato.
        "presentacion": {"sin_presentacion": 0, "inatenta": 1,
                         "hiperactiva_impulsiva": 2, "combinada": 3},
        "entorno_familiar": {"inestable": 0, "moderadamente estable": 1, "estable": 2},
        "preferencia_animal": {"perro": 0, "gato": 1, "conejo": 2, "caballo": 3},
        "experiencia_previa_con_animales": {"no": 0, "si": 1},
        "tipo_animal": {"perro": 0, "gato": 1, "conejo": 2, "caballo": 3},
        "sexo_animal": {"macho": 0, "hembra": 1},
        "raza": {valor: idx for idx, valor in enumerate(razas_unicas)},
        "tipo_entrenamiento": {valor: idx for idx, valor in enumerate(entrenamientos_unicos)},
        "certificado_terapia": {"no": 0, "si": 1},
    }


LABEL_MAPPINGS = build_label_mappings()

# v2 (ADHD-RS): el perfil conductual del paciente ya no son 6 niveles 1-5 sino lo
# que entrega el test ADHD-RS (7 features derivadas de las 18 respuestas).
FEATURE_COLUMNS = [
    # Paciente: datos basicos (5)
    "edad_paciente",
    "sexo_paciente",
    "entorno_familiar",
    "preferencia_animal",
    "experiencia_previa_con_animales",
    # Paciente: ADHD-RS (7)
    "adhd_in",
    "adhd_hi",
    "adhd_tot",
    "n_sintomas_in",
    "n_sintomas_hi",
    "presentacion",
    "cribado_positivo",
    # Animal (13)
    "tipo_animal",
    "sexo_animal",
    "edad_animal",
    "raza",
    "peso_kg",
    "nivel_energia_animal",
    "nivel_sociabilidad_animal",
    "nivel_calma_animal",
    "tolerancia_ruido",
    "tolerancia_contacto",
    "tipo_entrenamiento",
    "experiencia_terapeutica_meses",
    "certificado_terapia",
]

# Campos categoricos que se mapean string -> numero. El resto se usan numericos.
CATEGORICAL_FIELDS = set(LABEL_MAPPINGS.keys())


def _encode_value(field: str, value):
    """Codifica un valor: si es categorico y string, aplica el mapping (fallback 0).
    Si ya viene numerico se respeta (permite enviar el indice directamente)."""
    if field in CATEGORICAL_FIELDS and isinstance(value, str):
        return LABEL_MAPPINGS[field].get(value, 0)
    return value


def build_feature_frame(rows: list[dict]) -> pd.DataFrame:
    """Construye el DataFrame de features en el orden exacto FEATURE_COLUMNS,
    aplicando el mismo encoding y to_numeric(coerce).fillna(0) del modelo original."""
    encoded = []
    for row in rows:
        # Si llegan las 18 respuestas del test, las features ADHD-RS se DERIVAN aca:
        # asi ningun cliente puede mandar un perfil incoherente con sus respuestas.
        if row.get("respuestas_adhd") is not None:
            row = {**row, **features_modelo(row["respuestas_adhd"])}
        encoded.append({col: _encode_value(col, row.get(col, 0)) for col in FEATURE_COLUMNS})
    df = pd.DataFrame(encoded)[FEATURE_COLUMNS]
    df = df.apply(pd.to_numeric, errors="coerce").fillna(0)
    return df
