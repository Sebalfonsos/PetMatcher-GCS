"""PetMatcher API - sirve el modelo ML de efectividad terapeutica.

Arranque local (dev):
    cd api
    python -m venv .venv && .venv\\Scripts\\activate   (Windows)
    pip install -r requirements.txt
    uvicorn main:app --reload

Docs interactivas: http://localhost:8000/docs
"""
from __future__ import annotations

import json
import os
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware

from app import adhd_rs
from app.auth_routes import asegurar_admin_inicial, router as auth_router
from app.crud_routes import router as crud_router
from app.ranking_routes import router as ranking_router
from app.init_db import init_db
from app.security import SECRETO_EFIMERO, current_user
from app.ml import (
    MODELS_DIR,
    PREDICT_MODEL,
    load_models,
    loaded_model_names,
    models_loaded,
    predict_batch,
)
from app.preprocessing import CATALOGO_ANIMALES, FEATURE_COLUMNS, LABEL_MAPPINGS
from app.explain import (
    AVISO_EXPLICACION,
    construir_evidencia,
    llamar_lm_studio_stream,
    construir_prompt,
    llamar_lm_studio,
    lm_studio_disponible,
)
from app.schemas import (
    BatchPredictRequest,
    ExplainRequest,
    ExplainResponse,
    HealthResponse,
    PerfilADHD,
    PredictResult,
    ScoreRequest,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    faltantes = load_models()
    if faltantes:
        print("[PetMatcher] ADVERTENCIA: faltan modelos:", faltantes)
    else:
        print("[PetMatcher] Modelos cargados desde", MODELS_DIR)
    try:
        await init_db()
        print("[PetMatcher] Base de datos lista")
        await asegurar_admin_inicial()
    except Exception as exc:  # la API sigue sirviendo predicción aunque falle la BD
        print("[PetMatcher] ADVERTENCIA: no se pudo inicializar la BD:", exc)
    if SECRETO_EFIMERO:
        print("[PetMatcher] AVISO: PETMATCHER_JWT_SECRET no esta definido; las sesiones "
              "se cierran en cada reinicio. Definelo en produccion.")
    yield


app = FastAPI(title="PetMatcher API", version="0.1.0", lifespan=lifespan)

# CORS: por defecto solo localhost/127.0.0.1 en cualquier puerto (Flutter web en dev).
# En produccion: PETMATCHER_CORS_ORIGINS="https://app.ejemplo.com,https://otro.com".
_origenes = [o.strip() for o in os.environ.get("PETMATCHER_CORS_ORIGINS", "").split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_origenes,
    allow_origin_regex=None if _origenes else r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_methods=["*"],
    allow_headers=["*"],
)

# Todo requiere sesion salvo /health y /auth/login (el router de auth protege lo suyo).
_protegido = [Depends(current_user)]
app.include_router(auth_router)
app.include_router(crud_router, dependencies=_protegido)
app.include_router(ranking_router, dependencies=_protegido)


@app.get("/health", response_model=HealthResponse)
def health():
    return HealthResponse(
        status="ok" if models_loaded() else "degraded",
        models_loaded=models_loaded(),
        models_dir=str(MODELS_DIR),
        modelos=loaded_model_names(),
        modelo_prediccion=PREDICT_MODEL or "promedio",
    )


@app.get("/catalog", tags=["catalog"], dependencies=_protegido)
def catalog():
    """Valores validos de los campos categoricos, tal como los espera el modelo.

    Existe para que los clientes (Streamlit, Flutter) NO dupliquen el catalogo:
    duplicarlo es la via directa al desajuste de preprocesado descrito en
    plan.md seccion 11. Fuente unica: app/preprocessing.py.
    """
    return {
        "opciones": {k: list(v.keys()) for k, v in LABEL_MAPPINGS.items()},
        "razas_por_tipo": {t: d["razas"] for t, d in CATALOGO_ANIMALES.items()},
        "entrenamientos_por_tipo": {t: d["entrenamientos"] for t, d in CATALOGO_ANIMALES.items()},
        "features": FEATURE_COLUMNS,
        "features_adhd_rs": adhd_rs.FEATURES_TEST,
        "umbrales_categoria": {"alta": 80, "media": 60, "baja": 40},
    }


@app.get("/adhd-rs/cuestionario", tags=["adhd-rs"], dependencies=_protegido)
def adhd_cuestionario():
    """Los 18 items, las opciones de respuesta y la instruccion del test.

    Fuente unica del texto: la app Flutter lo pide aca en vez de duplicarlo.
    `subescala` es IN (impares) o HI (pares), segun la guia de aplicacion.
    """
    return {
        "instruccion": adhd_rs.INSTRUCCION,
        "opciones": adhd_rs.OPCIONES,
        "items": [
            {"n": i + 1, "texto": t,
             "subescala": "IN" if (i + 1) in adhd_rs.INATENCION else "HI"}
            for i, t in enumerate(adhd_rs.ITEMS)
        ],
        "advertencia": ("La ADHD-RS es una herramienta de cribado y apoyo. No diagnostica "
                        "TDAH por si sola: el diagnostico lo confirma un profesional."),
    }


@app.post("/adhd-rs/score", response_model=PerfilADHD, tags=["adhd-rs"], dependencies=_protegido)
def adhd_score(req: ScoreRequest):
    """Puntua las 18 respuestas (0-3): IN, HI, total, sintomas, presentacion y cribado."""
    return adhd_rs.perfil(req.respuestas_adhd)


@app.post("/predict/batch", response_model=list[PredictResult], dependencies=_protegido)
def predict_batch_endpoint(req: BatchPredictRequest):
    if not models_loaded():
        raise HTTPException(status_code=503, detail="Modelos no cargados")
    patient = req.patient.model_dump()
    animals = [a.model_dump() for a in req.animals]
    return predict_batch(patient, animals)


@app.post("/explain", response_model=ExplainResponse, tags=["explain"], dependencies=_protegido)
def explain_endpoint(req: ExplainRequest):
    """Explica el ranking en lenguaje natural, apoyado en evidencia calculada.

    El LLM NO explica el modelo: redacta hechos que calculamos nosotros por
    ablacion sobre el modelo servido (ver app/explain.py). Si LM Studio no esta
    disponible se devuelve igual la evidencia, y el cliente la muestra estructurada.
    """
    if not models_loaded():
        raise HTTPException(status_code=503, detail="Modelos no cargados")

    patient = req.patient.model_dump()
    animals = [a.model_dump() for a in req.animals]
    for a in animals:
        if a["id"] in req.nombres_animales:
            a["nombre"] = req.nombres_animales[a["id"]]

    resultados = predict_batch(patient, animals)
    evidencia = construir_evidencia({**patient, "nombre": req.nombre_paciente},
                                    animals, resultados)

    disponible, detalle = lm_studio_disponible()
    texto = None
    if disponible:
        try:
            texto = llamar_lm_studio(construir_prompt(evidencia))
        except Exception as exc:
            disponible, detalle = False, f"error al generar: {exc}"

    return ExplainResponse(explicacion=texto, evidencia=evidencia,
                           llm_disponible=disponible, detalle_llm=detalle,
                           aviso=AVISO_EXPLICACION)


@app.post("/explain/stream", tags=["explain"], dependencies=_protegido)
def explain_stream_endpoint(req: ExplainRequest):
    """Igual que /explain pero emite el texto a medida que el LLM lo genera.

    Formato NDJSON (un objeto JSON por linea), para que el cliente pueda ir
    pintando sin esperar el final:
        {"tipo":"evidencia","datos":{...}}   una vez, al principio
        {"tipo":"texto","delta":"..."}       muchas
        {"tipo":"fin","aviso":"..."}         una vez, al final
        {"tipo":"error","detalle":"..."}     si el LLM falla a mitad de camino

    Con el modelo de 7B una generacion tarda ~un minuto; ver el texto aparecer
    hace que la espera sea tolerable.
    """
    if not models_loaded():
        raise HTTPException(status_code=503, detail="Modelos no cargados")

    patient = req.patient.model_dump()
    animals = [a.model_dump() for a in req.animals]
    for a in animals:
        if a["id"] in req.nombres_animales:
            a["nombre"] = req.nombres_animales[a["id"]]

    resultados = predict_batch(patient, animals)
    evidencia = construir_evidencia({**patient, "nombre": req.nombre_paciente},
                                    animals, resultados)

    def generar():
        yield json.dumps({"tipo": "evidencia", "datos": evidencia},
                         ensure_ascii=False) + "\n"
        disponible, detalle = lm_studio_disponible()
        if not disponible:
            yield json.dumps({"tipo": "error", "detalle": detalle},
                             ensure_ascii=False) + "\n"
        else:
            try:
                for delta in llamar_lm_studio_stream(construir_prompt(evidencia)):
                    yield json.dumps({"tipo": "texto", "delta": delta},
                                     ensure_ascii=False) + "\n"
            except Exception as exc:
                yield json.dumps({"tipo": "error", "detalle": str(exc)},
                                 ensure_ascii=False) + "\n"
        yield json.dumps({"tipo": "fin", "aviso": AVISO_EXPLICACION},
                         ensure_ascii=False) + "\n"

    return StreamingResponse(
        generar(),
        # El charset es OBLIGATORIO: sin el, el cliente no sabe que viene en UTF-8
        # y decodifica como Latin-1, con lo que las tildes y la ñ salen rotas
        # ("Relámpago" -> "RelÃ¡mpago").
        media_type="application/x-ndjson; charset=utf-8",
        # Evita que un proxy intermedio acumule la respuesta y anule el streaming.
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
