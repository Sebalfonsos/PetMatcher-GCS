"""Puntuación y perfil de la ADHD-RS (adultos, 18 ítems, 0-3).

Del artículo (Richarte et al., 2017): suma de ítems, subescalas IN/H-I y puntos de corte 24 / 21.
Presentación según DSM-5 (adultos, >= 17 años): >= 5 síntomas en un dominio, con síntoma =
ítem puntuado 2 o 3 (convención habitual de la ADHD-RS; el artículo no la declara).
Combinada = ambos dominios; inatenta = solo inatención; hiperactiva/impulsiva = solo H/I.
No evaluable con la escala: inicio antes de los 12 años, varios entornos, deterioro funcional,
exclusión de otros trastornos y severidad.
"""
import csv
import sys

INATENCION = [1, 3, 5, 7, 9, 11, 13, 15, 17]
HIPERACTIVIDAD = [2, 4, 6, 8, 10, 12, 14, 16, 18]
CORTE_COMBINADO = 24
CORTE_INATENTO = 21
UMBRAL_SINTOMA = 2      # ítem puntuado "frecuentemente" o más
UMBRAL_N_SINTOMAS = 5   # criterio DSM-5 en adultos (>= 5 síntomas por dominio)


def perfil(resp):
    """resp: dict {1..18: 0..3} o lista de 18 valores. Devuelve dict con puntajes y perfil."""
    if not isinstance(resp, dict):
        resp = {i + 1: v for i, v in enumerate(resp)}
    if sorted(resp) != list(range(1, 19)) or any(v not in (0, 1, 2, 3) for v in resp.values()):
        raise ValueError("Se requieren los 18 ítems con valores 0-3")

    inn = sum(resp[i] for i in INATENCION)
    hi = sum(resp[i] for i in HIPERACTIVIDAD)
    tot = inn + hi
    n_in = sum(resp[i] >= UMBRAL_SINTOMA for i in INATENCION)
    n_hi = sum(resp[i] >= UMBRAL_SINTOMA for i in HIPERACTIVIDAD)

    in_alto = n_in >= UMBRAL_N_SINTOMAS
    hi_alto = n_hi >= UMBRAL_N_SINTOMAS
    if in_alto and hi_alto:
        presentacion, corte = "combinada", CORTE_COMBINADO
    elif in_alto:
        presentacion, corte = "inatenta", CORTE_INATENTO
    elif hi_alto:
        presentacion, corte = "hiperactiva_impulsiva", CORTE_COMBINADO  # sin corte propio en el artículo
    else:
        presentacion, corte = "sin_presentacion", CORTE_COMBINADO

    cribado_positivo = tot >= corte  # el artículo no aclara >= vs >
    return {
        "IN": inn, "HI": hi, "TOT": tot,
        "n_sintomas_IN": n_in, "n_sintomas_HI": n_hi,
        "presentacion": presentacion,
        "corte_usado": corte,
        "cribado_positivo": int(cribado_positivo),
        "tot_ge_24": int(tot >= CORTE_COMBINADO),
        "tot_ge_21": int(tot >= CORTE_INATENTO),
    }


def procesar_csv(entrada, salida):
    """CSV de entrada con columnas id, i1..i18. Escribe las columnas originales + derivadas."""
    with open(entrada, newline="", encoding="utf-8") as f:
        filas = list(csv.DictReader(f))
    out = []
    for fila in filas:
        r = perfil({i: int(fila[f"i{i}"]) for i in range(1, 19)})
        out.append({**fila, **r})
    with open(salida, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(out[0]))
        w.writeheader()
        w.writerows(out)


if __name__ == "__main__":
    if len(sys.argv) == 3:
        procesar_csv(sys.argv[1], sys.argv[2])
    else:
        print(perfil([2, 1, 3, 0, 2, 1, 2, 0, 3, 1, 2, 0, 3, 1, 2, 0, 3, 1]))


# ---------------------------------------------------------------------------
# Cuestionario (fuente única: la app Flutter lo pide a GET /adhd-rs/cuestionario)
# ---------------------------------------------------------------------------
OPCIONES = [
    {"valor": 0, "etiqueta": "Nunca o casi nunca"},
    {"valor": 1, "etiqueta": "Algunas veces"},
    {"valor": 2, "etiqueta": "Frecuentemente"},
    {"valor": 3, "etiqueta": "Muy frecuentemente"},
]

INSTRUCCION = ("Marque la opción que mejor describa su comportamiento durante "
               "los últimos 6 meses.")

ITEMS = [
    "Al hacer mi trabajo no logro fijar mi atención en los detalles o cometo errores por no tener cuidado",
    "Meneo las manos o los pies o me muevo constantemente en mi asiento",
    "Tengo dificultad para sostener mi atención en las tareas o en las actividades de diversión",
    "Me levanto del asiento en situaciones en donde se espera que permanezca sentado",
    "No presto atención cuando se me habla directamente",
    "Me siento inquieto",
    "No sigo instrucciones de principio a fin y no termino el trabajo asignado",
    "Tengo dificultades para llevar a cabo actividades en mi tiempo libre de manera calmada o para hacer cosas divertidas tranquilamente",
    "Tengo dificultad para organizar las tareas y actividades",
    "Me siento como si tuviese que \"moverme continuamente\" o \"como si me empujara un motor\"",
    "Me disgusta, evito o estoy reticente a llevar a cabo trabajo que requiera esfuerzo mental sostenido",
    "Hablo en exceso",
    "Pierdo cosas que son necesarias para llevar a cabo tareas o actividades",
    "Contesto abruptamente antes de que otros terminen de hacerme la pregunta",
    "Me distraigo fácilmente",
    "Tengo dificultad para esperar mi turno",
    "Soy olvidadizo en las actividades diarias",
    "Interrumpo a los demás o soy entrometido",
]

# Nombres de las features del paciente que salen del test (orden fijo del modelo).
FEATURES_TEST = ["adhd_in", "adhd_hi", "adhd_tot", "n_sintomas_in", "n_sintomas_hi",
                 "presentacion", "cribado_positivo"]


def features_modelo(resp) -> dict:
    """Perfil del test traducido a las columnas que consume el modelo."""
    p = perfil(resp)
    return {
        "adhd_in": p["IN"], "adhd_hi": p["HI"], "adhd_tot": p["TOT"],
        "n_sintomas_in": p["n_sintomas_IN"], "n_sintomas_hi": p["n_sintomas_HI"],
        "presentacion": p["presentacion"], "cribado_positivo": p["cribado_positivo"],
    }
