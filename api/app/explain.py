"""Explicacion del ranking en lenguaje natural, apoyada en evidencia calculada.

PRINCIPIO DE DISENO
    Al LLM NO se le pide que explique el modelo: se le pide que REDACTE evidencia
    que ya calculamos nosotros. Si se le pasara solo "Relampago 82%, Sombra 35%"
    inventaria razones clinicas plausibles pero falsas, en prosa convincente.
    Aca el LLM es un traductor, no un adivino.

QUE SE CALCULA (todo desde el modelo que la API ya esta sirviendo)
    - Contribucion local por feature, por ablacion: se reemplaza cada atributo del
      animal por el valor tipico de los candidatos de ESTE ranking y se mide cuanto
      cae/sube la prediccion. Es exacto para lo que mide.
    - Contraste directo entre el primero y el segundo.
    - Distancia a los umbrales de categoria.
    - Rasgos del paciente que mueven el resultado.

Si el LLM no esta disponible, el endpoint devuelve la evidencia igual: la UI puede
mostrarla estructurada. La funcionalidad no depende de que haya un modelo prendido.
"""
from __future__ import annotations

import json
import os
import statistics
from typing import Any

import requests

from .adhd_rs import HIPERACTIVIDAD, INATENCION, perfil as perfil_adhd
from .ml import _MODELS, PREDICT_MODEL, interpretar
from .preprocessing import build_feature_frame

AVISO_EXPLICACION = (
    "Texto generado por un modelo de lenguaje a partir de evidencia calculada por el "
    "modelo de ML, que fue entrenado con DATOS SINTÉTICOS. Es apoyo a la interpretación, "
    "no una indicación clínica. La decisión es del terapeuta."
)

LMSTUDIO_URL = os.environ.get("LMSTUDIO_URL", "http://host.docker.internal:1234")
LMSTUDIO_MODEL = os.environ.get("LMSTUDIO_MODEL", "local-model")
LMSTUDIO_TIMEOUT = int(os.environ.get("LMSTUDIO_TIMEOUT", "120"))

# Atributos del animal sobre los que se mide contribucion.
ANIMAL_NUM = ["edad_animal", "peso_kg", "nivel_energia_animal",
              "nivel_sociabilidad_animal", "nivel_calma_animal",
              "tolerancia_ruido", "tolerancia_contacto",
              "experiencia_terapeutica_meses"]
ANIMAL_CAT = ["tipo_animal", "raza", "tipo_entrenamiento", "certificado_terapia",
              "sexo_animal"]
PRESENTACION_TXT = {
    "combinada": "combinada", "inatenta": "predominantemente inatenta",
    "hiperactiva_impulsiva": "predominantemente hiperactiva/impulsiva",
    "sin_presentacion": "sin presentación (no alcanza el umbral de síntomas)",
}

ETIQUETA = {
    "edad_animal": "edad", "peso_kg": "peso", "nivel_energia_animal": "energía",
    "nivel_sociabilidad_animal": "sociabilidad", "nivel_calma_animal": "calma",
    "tolerancia_ruido": "tolerancia al ruido",
    "tolerancia_contacto": "tolerancia al contacto",
    "experiencia_terapeutica_meses": "experiencia terapéutica (meses)",
    "tipo_animal": "tipo de animal", "raza": "raza",
    "tipo_entrenamiento": "entrenamiento", "certificado_terapia": "certificado",
    "sexo_animal": "sexo",
}


def _predict(filas: list[dict]) -> list[float]:
    """Predice con el mismo criterio que /predict/batch."""
    x = build_feature_frame(filas)
    preds = {n: m.predict(x) for n, m in _MODELS.items()}
    if PREDICT_MODEL and PREDICT_MODEL in preds:
        vals = preds[PREDICT_MODEL]
    else:
        vals = [sum(p[i] for p in preds.values()) / len(preds) for i in range(len(filas))]
    return [float(max(0.0, min(100.0, v))) for v in vals]


def _tipico(animales: list[dict]) -> dict:
    """Animal 'tipico' de este ranking: mediana de lo numerico, moda de lo categorico."""
    base = {}
    for f in ANIMAL_NUM:
        vals = [a[f] for a in animales if f in a and a[f] is not None]
        if vals:
            base[f] = statistics.median(vals)
    for f in ANIMAL_CAT:
        vals = [a[f] for a in animales if f in a and a[f] is not None]
        if vals:
            base[f] = statistics.mode(vals)
    return base


def _contribuciones(paciente: dict, animal: dict, base: dict, pred: float,
                    top: int = 5) -> list[dict]:
    """Cuanto aporta cada atributo del animal vs. el candidato tipico del ranking."""
    campos = [f for f in ANIMAL_NUM + ANIMAL_CAT
              if f in base and f in animal and animal[f] != base[f]]
    if not campos:
        return []
    filas = [{**paciente, **animal, f: base[f]} for f in campos]
    sin = _predict(filas)
    out = []
    for f, p_sin in zip(campos, sin):
        out.append({"atributo": ETIQUETA.get(f, f), "valor": animal[f],
                    "valor_tipico": base[f], "aporte": round(pred - p_sin, 2)})
    out.sort(key=lambda d: -abs(d["aporte"]))
    return [c for c in out[:top] if abs(c["aporte"]) >= 0.5]


def _sin_dominio(paciente: dict, items: list[int]) -> dict:
    """Copia del paciente con ese dominio del test en 0 (ablacion: 'sin esa sintomatologia')."""
    resp = list(paciente["respuestas_adhd"])
    for i in items:
        resp[i - 1] = 0
    return {**paciente, "respuestas_adhd": resp}


def _factores_paciente(paciente: dict, animal: dict, pred: float,
                       top: int = 4) -> list[dict]:
    """Que partes del test del paciente mueven el resultado.

    Se pone en 0 cada dominio (inatencion, hiperactividad/impulsividad) y se mide
    cuanto cambia la prediccion con este animal.
    """
    if not paciente.get("respuestas_adhd"):
        return []
    p = perfil_adhd(paciente["respuestas_adhd"])
    casos = [
        (f"inatención (IN {p['IN']}/27, {p['n_sintomas_IN']} síntomas)", INATENCION),
        (f"hiperactividad/impulsividad (HI {p['HI']}/27, {p['n_sintomas_HI']} síntomas)",
         HIPERACTIVIDAD),
    ]
    sin = _predict([{**_sin_dominio(paciente, items), **animal} for _, items in casos])
    out = [{"rasgo": nombre, "aporte": round(pred - v, 2)}
           for (nombre, _), v in zip(casos, sin)]
    out.sort(key=lambda d: -abs(d["aporte"]))
    return [c for c in out[:top] if abs(c["aporte"]) >= 0.5]


# Reglas de compatibilidad (las mismas que el generador sintetico v3). El aporte de
# cada una se MIDE (ablacion conjunta paciente x animal), no se supone: por eso el LLM
# puede decir "su HI es alto y este animal es muy calmado" sin inventar nada.
#   (nombre de la regla, atributo del animal, dominio del paciente a neutralizar)
PARES = [
    ("hiperactividad/impulsividad alta con un animal calmado", "nivel_calma_animal", "HI"),
    ("hiperactividad/impulsividad alta con tolerancia al contacto", "tolerancia_contacto", "HI"),
    ("inatención alta con un animal sociable (motivación e interacción)",
     "nivel_sociabilidad_animal", "IN"),
    ("presentación combinada con tolerancia al ruido", "tolerancia_ruido", "COMB"),
]


def _aplica(p: dict, dom: str) -> bool:
    """La regla aplica solo si el paciente cumple su condicion segun el test."""
    if dom == "HI":
        return p["n_sintomas_HI"] >= 5
    if dom == "IN":
        return p["n_sintomas_IN"] >= 5
    return p["presentacion"] == "combinada"


def _dato_paciente(p: dict, dom: str) -> str:
    if dom == "HI":
        return f"HI {p['HI']}/27 ({p['n_sintomas_HI']} síntomas)"
    if dom == "IN":
        return f"IN {p['IN']}/27 ({p['n_sintomas_IN']} síntomas)"
    return "presentación combinada"


def _pares_afinidad(paciente: dict, animal: dict, base: dict, pred: float,
                    nombre_paciente: str = "el paciente",
                    nombre_animal: str = "el animal") -> list[dict]:
    """Aporte de cada regla que APLICA a este paciente.

    Una regla aplica solo si el paciente la cumple segun su test (>= 5 sintomas en el
    dominio, o presentacion combinada). Se reemplaza el atributo del animal por el
    valor tipico del ranking y se mide cuanto cae la prediccion: eso es lo que ESE
    atributo aporta a ESE paciente.
    """
    if not paciente.get("respuestas_adhd"):
        return []
    perfil = perfil_adhd(paciente["respuestas_adhd"])
    campos = [(n, ra, dom) for n, ra, dom in PARES
              if ra in animal and ra in base and _aplica(perfil, dom)]
    if not campos:
        return []
    filas = [{**paciente, **animal, ra: base[ra]} for _, ra, _ in campos]
    sin = _predict(filas)
    out = []
    for (nombre, ra, dom), p_sin in zip(campos, sin):
        ap = round(pred - p_sin, 2)
        # El signo viene RESUELTO en palabras: un modelo chico invierte "resta"
        # por "suma" con facilidad.
        verbo = "suma" if ap > 0 else "resta"
        out.append({
            "_orden": abs(ap),
            "frase_lista_para_usar": (
                f"{nombre_paciente} tiene {_dato_paciente(perfil, dom)} y "
                f"{nombre_animal} tiene {ETIQUETA.get(ra, ra)} {animal[ra]} "
                f"({nombre}); ese atributo {verbo} {abs(ap)} puntos"),
        })
    out.sort(key=lambda d: -d["_orden"])
    return [{"frase_lista_para_usar": c["frase_lista_para_usar"]} for c in out[:4]]


def _preferencia(paciente: dict, animal: dict) -> str:
    pref, tipo = paciente.get("preferencia_animal"), animal.get("tipo_animal")
    if pref is None or tipo is None:
        return ""
    if pref == tipo:
        return f"coincide con su animal de preferencia ({pref})"
    return f"NO es su animal de preferencia (prefiere {pref}, este es {tipo})"


def _contraste(a1: dict, a2: dict) -> list[dict]:
    """En que se diferencian el primero y el segundo."""
    dif = []
    for f in ANIMAL_NUM + ANIMAL_CAT:
        if f in a1 and f in a2 and a1[f] != a2[f]:
            dif.append({"atributo": ETIQUETA.get(f, f),
                        "primero": a1[f], "segundo": a2[f]})
    return dif


def _resumen_paciente(paciente: dict) -> dict:
    """Datos basicos + perfil del test ADHD-RS (sin las 18 respuestas crudas)."""
    out = {k: v for k, v in paciente.items()
           if k not in ("id", "nombre", "respuestas_adhd")}
    if paciente.get("respuestas_adhd"):
        out["perfil_adhd_rs"] = perfil_adhd(paciente["respuestas_adhd"])
    return out


def construir_evidencia(paciente: dict, animales: list[dict],
                        resultados: list[dict]) -> dict:
    """Arma el paquete de hechos verificables que va a recibir el LLM."""
    por_id = {a["id"]: a for a in animales}
    base = _tipico(animales)
    umbrales = {"alta": 80, "media": 60, "baja": 40}

    ranking = []
    # Detalle fino solo para los 3 primeros y el ultimo: es lo que se compara.
    detallar = set(range(min(2, len(resultados)))) | {len(resultados) - 1}
    for i, r in enumerate(resultados):
        a = por_id.get(r["animal_id"], {})
        item = {
            "posicion": i + 1,
            "nombre": a.get("nombre") or r["animal_id"],
            "tipo": a.get("tipo_animal"),
            "efectividad": r["efectividad"],
            "categoria": r["categoria"],
        }
        if i in detallar and a:
            item["atributos_decisivos"] = _contribuciones(paciente, a, base, r["efectividad"])
            # Lo que permite narrar el ENCAJE y no solo listar atributos sueltos.
            item["encuentros_con_el_paciente"] = _pares_afinidad(
                paciente, a, base, r["efectividad"],
                paciente.get("nombre", "el paciente"), item["nombre"])
            item["sobre_la_preferencia"] = _preferencia(paciente, a)
            falta = min((u - r["efectividad"] for u in umbrales.values()
                         if r["efectividad"] < u), default=None)
            if falta is not None and falta <= 10:
                # Redactado como frase para que el LLM no reinterprete el numero:
                # confundir esto con la distancia al otro candidato es el error tipico.
                item["nota_umbral"] = (
                    f"le faltan {falta:.2f} puntos para subir a la categoria "
                    f"siguiente (esto NO es la diferencia con otro candidato)")
        ranking.append(item)

    ev: dict[str, Any] = {
        "paciente": _resumen_paciente(paciente),
        "nombre_paciente": paciente.get("nombre", "el paciente"),
        "candidatos_evaluados": len(resultados),
        "rango_efectividad": [resultados[-1]["efectividad"], resultados[0]["efectividad"]],
        "umbrales_categoria": umbrales,
        "ranking": ranking,
        "candidato_tipico_de_referencia": {ETIQUETA.get(k, k): v for k, v in base.items()},
    }
    if len(resultados) >= 2:
        a1, a2 = por_id.get(resultados[0]["animal_id"]), por_id.get(resultados[1]["animal_id"])
        if a1 and a2:
            dif = round(resultados[0]["efectividad"] - resultados[1]["efectividad"], 2)
            # La conclusion viene RESUELTA: un modelo chico se equivoca al comparar
            # numeros y al aplicar el umbral de 5 puntos. Que solo lo repita.
            if dif < 5:
                lectura = (f"{a1.get('nombre')} supera a {a2.get('nombre')} por solo "
                           f"{dif} puntos: a esa distancia el modelo NO los distingue "
                           f"de forma confiable, se deben presentar como equivalentes")
            else:
                lectura = (f"{a1.get('nombre')} supera claramente a {a2.get('nombre')} "
                           f"por {dif} puntos")
            # Sin numeros sueltos: un modelo chico los reasigna a otras parejas.
            # La cifra viaja dentro de la frase, donde no se puede desprender.
            ev["primero_vs_segundo"] = {
                "lectura_ya_resuelta": lectura,
                "diferencias_de_atributos": _contraste(a1, a2),
            }
        if a1:
            ev["rasgos_del_paciente_que_influyen"] = _factores_paciente(
                paciente, a1, resultados[0]["efectividad"])
    return ev


SYSTEM_PROMPT = """\
Sos un asistente que ayuda a un TERAPEUTA a interpretar la salida de un modelo de
machine learning que ordena animales de terapia asistida segun su compatibilidad
estimada con un paciente adulto cuyo perfil sale del test ADHD-RS (cribado de TDAH).

TU ROL
Traducis evidencia numerica ya calculada a lenguaje claro para un profesional.
NO sos quien decide. La decision clinica es del terapeuta.

REGLAS ESTRICTAS (su incumplimiento invalida la respuesta)
1. NO HAGAS NINGUNA CUENTA. No restes, no compares magnitudes, no infieras quien
   gana. Todas las comparaciones ya vienen resueltas en la evidencia: copialas.
   En particular usa "quien_lidera" y "lectura_ya_resuelta" tal como estan.
2. Usa UNICAMENTE los datos del bloque EVIDENCIA. No agregues hechos, cifras,
   nombres ni atributos que no esten ahi.
3. Cada numero que escribas tiene que aparecer literalmente en la evidencia. Si no
   esta, no lo escribas.
4. "nota_umbral" es la distancia de ESE candidato al siguiente escalon de categoria.
   NO es la diferencia con otro candidato. No las mezcles.
5. Nunca inventes mecanismos clinicos ni cites literatura. Si te falta informacion
   para afirmar algo, no lo afirmes.
6. Los numeros de "aporte" indican cuanto sube o baja la efectividad estimada ese
   atributo respecto de un candidato tipico de esta misma lista. Es una medida del
   MODELO, no un efecto terapeutico comprobado. Redactalo asi.
7. No des ordenes ni recomendaciones categoricas ("debe asignar"). Usa formulaciones
   orientativas ("el modelo favorece", "convendria considerar").
8. Si existe "rasgos_del_paciente_que_influyen", mencionalos en la seccion "Por que
   encabeza": son los partes del test del paciente que mueven el resultado.
9. NO menciones que los datos son sinteticos ni agregues disclaimers sobre la
   naturaleza del modelo: de eso se encarga la interfaz, con un aviso fijo debajo
   del texto. Repetirlo en cada respuesta solo agrega ruido.
10. Responde en espanol rioplatense, en prosa clara, sin jerga de machine learning
   (nada de "features", "SMD", "R2"). Habla de "atributos" y "efectividad estimada".

COMO ESCRIBIR (esto es lo mas importante del pedido)
Escribi como le hablarias a un colega terapeuta, no como un reporte automatico.

- NADA de listas de atributos sueltos tipo "sociabilidad: +10.6". Eso no le sirve
  a nadie. Contá el ENCUENTRO entre el paciente y el animal.
- El bloque "encuentros" de cada candidato es tu material principal: son
  oraciones YA ESCRITAS con los datos correctos.
  Tu trabajo es HILAR esas frases en prosa, agregando conectores y el porque
  clinico. NO cambies sus numeros, ni sus valores, ni el verbo suma/resta.
  Podes reescribir el estilo, pero cada cifra y cada "suma"/"resta" tiene que
  quedar igual que en la frase original.
- NO inventes cifras redondeadas ("unos seis puntos") si la frase dice otra cosa.
  Escribi la cifra tal cual aparece.
- Deci tambien por que el ultimo candidato NO encaja, con el mismo criterio: que
  necesidad del paciente queda sin cubrir.
- Prosa, parrafos cortos. Sin vinetas salvo que aclaren de verdad.

FORMATO DE SALIDA (markdown, maximo 450 palabras)
### En pocas palabras
Dos o tres frases, en tono de colega: quien encabeza, con que efectividad y
categoria, y si la ventaja es clara o ajustada (usa "lectura_ya_resuelta").

### Por que este animal encaja con este paciente
El nucleo. Narra los encuentros regla paciente-animal que mas aportan, explicando la
logica de cada uno. Menciona la preferencia declarada usando "sobre_la_preferencia".

### Por que otros no
Tomá el ultimo del ranking y contá que le falta para este paciente en particular.
Si hay un segundo candidato cercano, deci en que caso podria preferirse.

### A tener en cuenta
Limitaciones concretas de ESTE ranking, en una o dos frases: diferencias ajustadas
entre candidatos, o alguno cerca de un umbral de categoria. Nada de advertencias
genericas sobre el modelo o los datos.
"""


def compactar_para_llm(ev: dict) -> dict:
    """Recorta la evidencia a lo que el LLM realmente usa para redactar.

    La evidencia completa se sigue devolviendo al cliente (el panel de auditoria
    de la UI la necesita); lo que viaja al modelo es esta version.

    Se quitan: el dict crudo del paciente y `rasgos_del_paciente_que_influyen`
    (ya estan dentro de las frases de los encuentros), `atributos_decisivos`
    (redundante desde que existen los encuentros) y `candidato_tipico_de_referencia`
    (nunca se cita). Los candidatos sin detalle pasan a ser una linea de texto.

    Ademas de gastar menos tokens, menos ruido mejora la fidelidad de los modelos
    chicos: cada campo extra es una cifra mas que pueden mezclar.
    """
    podio, resto = [], []
    for r in ev.get("ranking", []):
        if r.get("encuentros_con_el_paciente"):
            item = {k: r[k] for k in ("posicion", "nombre", "tipo", "efectividad",
                                      "categoria") if k in r}
            item["encuentros"] = [e["frase_lista_para_usar"]
                                  for e in r["encuentros_con_el_paciente"]]
            for k in ("sobre_la_preferencia", "nota_umbral"):
                if r.get(k):
                    item[k] = r[k]
            podio.append(item)
        else:
            resto.append(f"{r['posicion']}. {r['nombre']} ({r.get('tipo','?')}) "
                         f"{r['efectividad']}% {r['categoria']}")

    compacta = {
        "paciente": ev.get("nombre_paciente", "el paciente"),
        "candidatos_evaluados": ev.get("candidatos_evaluados"),
        "umbrales_categoria": ev.get("umbrales_categoria"),
        "candidatos_con_detalle": podio,
    }
    if resto:
        compacta["resto_del_ranking"] = resto
    if ev.get("primero_vs_segundo"):
        compacta["primero_vs_segundo"] = ev["primero_vs_segundo"]
    return compacta


def construir_prompt(evidencia: dict) -> list[dict]:
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content":
            "EVIDENCIA (unica fuente de verdad permitida):\n\n"
            + json.dumps(compactar_para_llm(evidencia), ensure_ascii=False, indent=1)
            + "\n\nRedacta la orientacion para el terapeuta siguiendo el formato indicado."},
    ]


def _modelo_activo() -> str:
    """Nombre del modelo cargado en LM Studio.

    Se consulta en vez de hardcodearlo: LM Studio identifica los modelos por su
    ruta completa (p.ej. 'qwen2.5-3b-instruct'), y mandar un nombre que no existe
    es la causa mas comun de 404 al integrarlo. Si LMSTUDIO_MODEL trae algo
    distinto del default, gana lo configurado.
    """
    if LMSTUDIO_MODEL and LMSTUDIO_MODEL != "local-model":
        return LMSTUDIO_MODEL
    try:
        r = requests.get(f"{LMSTUDIO_URL.rstrip('/')}/v1/models", timeout=4)
        r.raise_for_status()
        for m in r.json().get("data", []):
            if m.get("id"):
                return m["id"]
    except Exception:
        pass
    return LMSTUDIO_MODEL


def llamar_lm_studio(mensajes: list[dict], temperatura: float = 0.1) -> str:
    """Llama al servidor local de LM Studio (API compatible con OpenAI)."""
    r = requests.post(
        f"{LMSTUDIO_URL.rstrip('/')}/v1/chat/completions",
        json={"model": _modelo_activo(), "messages": mensajes,
              "temperature": temperatura, "max_tokens": 900, "stream": False},
        timeout=LMSTUDIO_TIMEOUT,
    )
    r.raise_for_status()
    return r.json()["choices"][0]["message"]["content"].strip()


def llamar_lm_studio_stream(mensajes: list[dict], temperatura: float = 0.1):
    """Igual que llamar_lm_studio pero devuelve los fragmentos a medida que salen.

    LM Studio expone el formato SSE de OpenAI: lineas `data: {json}` y un
    `data: [DONE]` al final. Se emite solo el texto nuevo de cada fragmento.
    """
    with requests.post(
        f"{LMSTUDIO_URL.rstrip('/')}/v1/chat/completions",
        json={"model": _modelo_activo(), "messages": mensajes,
              "temperature": temperatura, "max_tokens": 900, "stream": True},
        timeout=LMSTUDIO_TIMEOUT, stream=True,
    ) as r:
        r.raise_for_status()
        # Se decodifica a mano en UTF-8. Con decode_unicode=True, requests mira el
        # charset del Content-Type; LM Studio responde `text/event-stream` SIN
        # charset y, para tipos text/*, requests asume ISO-8859-1 por RFC 2616.
        # Resultado: las tildes y la ñ del modelo llegan rotas ("RelÃ¡mpago").
        for linea_b in r.iter_lines():
            if not linea_b:
                continue
            linea = linea_b.decode("utf-8", errors="replace")
            if not linea.startswith("data:"):
                continue
            cuerpo = linea[5:].strip()
            if cuerpo == "[DONE]":
                break
            try:
                delta = json.loads(cuerpo)["choices"][0]["delta"].get("content")
            except (json.JSONDecodeError, KeyError, IndexError):
                continue
            if delta:
                yield delta


def lm_studio_disponible() -> tuple[bool, str]:
    try:
        r = requests.get(f"{LMSTUDIO_URL.rstrip('/')}/v1/models", timeout=4)
        r.raise_for_status()
        ids = [m.get("id") for m in r.json().get("data", [])]
        return True, (", ".join(i for i in ids if i) or "sin modelos cargados")
    except Exception as exc:
        return False, str(exc)
