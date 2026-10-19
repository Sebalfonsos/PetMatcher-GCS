"""Rankings y explicaciones guardados (persistencia en PostgreSQL).

REGLAS DE NEGOCIO
    - Hay UN ranking vigente por paciente. Volver a entrar muestra el guardado.
    - "Generar nuevo" recalcula con los animales disponibles AHORA. Si el resultado es
      identico al guardado, se conserva el guardado (`sin_cambios`) y con el su
      explicacion; si cambia, lo reemplaza y la explicacion vieja se borra.
    - La explicacion es una por ranking: solo se puede generar de nuevo cuando el
      ranking cambia (409 si ya existe una para el ranking vigente).
"""
from __future__ import annotations

import hashlib
import json
import uuid

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.concurrency import iterate_in_threadpool, run_in_threadpool
from fastapi.responses import StreamingResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .db import SessionLocal, get_session
from .db_models import AnimalORM, ExplicacionORM, PatientORM, RankingORM
from .security import registrar
from .explain import (
    AVISO_EXPLICACION,
    construir_evidencia,
    construir_prompt,
    llamar_lm_studio_stream,
    lm_studio_disponible,
)
from .ml import models_loaded, predict_batch
from .schemas import ExplicacionOut, RankingOut, ResultadoRanking

router = APIRouter()

ANIMAL_FEATURES = [
    "tipo_animal", "sexo_animal", "edad_animal", "raza", "peso_kg",
    "nivel_energia_animal", "nivel_sociabilidad_animal", "nivel_calma_animal",
    "tolerancia_ruido", "tolerancia_contacto", "tipo_entrenamiento",
    "experiencia_terapeutica_meses", "certificado_terapia",
]
PACIENTE_FEATURES = [
    "edad_paciente", "sexo_paciente", "entorno_familiar", "preferencia_animal",
    "experiencia_previa_con_animales", "respuestas_adhd",
]

# Explicaciones que se estan generando ahora: evita dos generaciones simultaneas
# (doble toque) sobre el mismo ranking.
_GENERANDO: set[str] = set()


def _hash(obj) -> str:
    return hashlib.sha1(json.dumps(obj, sort_keys=True, default=str).encode()).hexdigest()


def _features_paciente(p: PatientORM) -> dict:
    return {k: getattr(p, k) for k in PACIENTE_FEATURES}


def _features_animal(a: AnimalORM) -> dict:
    return {"id": a.id, "nombre": a.nombre, **{k: getattr(a, k) for k in ANIMAL_FEATURES}}


def _firma_animal(a: dict) -> str:
    return _hash({k: a[k] for k in ANIMAL_FEATURES})


async def _disponibles(session: AsyncSession) -> list[AnimalORM]:
    res = await session.execute(
        select(AnimalORM).where(AnimalORM.asignado_a_paciente_id.is_(None))
        .order_by(AnimalORM.nombre))
    return list(res.scalars())


async def _patient_or_404(session: AsyncSession, patient_id: str) -> PatientORM:
    p = await session.get(PatientORM, patient_id)
    if p is None:
        raise HTTPException(status_code=404, detail="Paciente no encontrado")
    return p


def _motivos(r: RankingORM, paciente: PatientORM, disponibles: list[AnimalORM]) -> list[str]:
    """Por que el ranking guardado ya no refleja la realidad (lista vacia = vigente)."""
    motivos = []
    if _hash(_features_paciente(paciente)) != r.paciente_firma:
        motivos.append("Se editó al paciente (datos o test) desde que se generó.")
    actuales = {a.id: _firma_animal(_features_animal(a)) for a in disponibles}
    guardados = r.animales_firma
    if any(i not in actuales for i in guardados):
        motivos.append("Algún animal del ranking fue asignado o eliminado.")
    if any(i not in guardados for i in actuales):
        motivos.append("Hay animales disponibles que no estaban en el ranking.")
    if any(i in actuales and actuales[i] != f for i, f in guardados.items()):
        motivos.append("Se editó algún animal del ranking.")
    return motivos


def _out(r: RankingORM, expl: ExplicacionORM | None, motivos: list[str],
         sin_cambios: bool = False) -> RankingOut:
    por_id = {a["id"]: a for a in r.animales}
    resultados = [
        ResultadoRanking(
            animal_id=x["animal_id"], nombre=por_id[x["animal_id"]]["nombre"],
            tipo_animal=por_id[x["animal_id"]]["tipo_animal"],
            raza=por_id[x["animal_id"]]["raza"], efectividad=x["efectividad"],
            categoria=x["categoria"], por_modelo=x.get("por_modelo", {}))
        for x in r.resultados]
    return RankingOut(
        id=r.id, patient_id=r.patient_id, generado_en=r.generado_en,
        resultados=resultados, obsoleto=bool(motivos), motivos=motivos,
        sin_cambios=sin_cambios,
        explicacion=None if expl is None else ExplicacionOut(
            texto=expl.texto, evidencia=expl.evidencia, aviso=expl.aviso,
            generado_en=expl.generado_en))


@router.get("/patients/{patient_id}/ranking", response_model=RankingOut | None,
            tags=["rankings"])
async def get_ranking(patient_id: str, request: Request,
                      session: AsyncSession = Depends(get_session)):
    """Ranking guardado del paciente (con su explicacion), o `null` si nunca se hizo."""
    paciente = await _patient_or_404(session, patient_id)
    res = await session.execute(select(RankingORM).where(RankingORM.patient_id == patient_id))
    r = res.scalar_one_or_none()
    if r is None:
        return None
    expl = await session.get(ExplicacionORM, r.id)
    await registrar(session, request, "ranking.ver", "paciente", patient_id, commit=True)
    return _out(r, expl, _motivos(r, paciente, await _disponibles(session)))


@router.post("/patients/{patient_id}/ranking", response_model=RankingOut, tags=["rankings"])
async def create_ranking(patient_id: str, request: Request,
                         session: AsyncSession = Depends(get_session)):
    """Genera el ranking AHORA con los animales disponibles y lo guarda."""
    if not models_loaded():
        raise HTTPException(status_code=503, detail="Modelos no cargados")
    paciente = await _patient_or_404(session, patient_id)
    if not paciente.respuestas_adhd:
        raise HTTPException(status_code=422,
                            detail="El paciente no tiene el test ADHD-RS: no hay perfil para emparejar")
    disponibles = await _disponibles(session)
    existente = (await session.execute(
        select(RankingORM).where(RankingORM.patient_id == patient_id))).scalar_one_or_none()
    if not disponibles:
        # Nada que rankear: no se guarda un ranking vacio (se conserva el anterior).
        return RankingOut(patient_id=patient_id)

    pf = _features_paciente(paciente)
    animales = [_features_animal(a) for a in disponibles]
    resultados = await run_in_threadpool(predict_batch, pf, animales)
    pfirma = _hash(pf)
    firma = _hash([pfirma] + [[x["animal_id"], x["efectividad"]] for x in resultados])

    if existente is not None and existente.firma == firma:
        expl = await session.get(ExplicacionORM, existente.id)
        await registrar(session, request, "ranking.generar", "paciente", patient_id,
                        {"sin_cambios": True}, commit=True)
        return _out(existente, expl, [], sin_cambios=True)

    if existente is not None:
        await session.delete(existente)  # la explicacion cae en cascada (FK ON DELETE CASCADE)
        await session.flush()
    nuevo = RankingORM(
        id=str(uuid.uuid4()), patient_id=patient_id, paciente=pf, paciente_firma=pfirma,
        animales=animales, animales_firma={a["id"]: _firma_animal(a) for a in animales},
        resultados=resultados, firma=firma)
    session.add(nuevo)
    await registrar(session, request, "ranking.generar", "paciente", patient_id,
                    {"sin_cambios": False, "animales": len(animales)})
    await session.commit()
    await session.refresh(nuevo)
    return _out(nuevo, None, [])


@router.post("/rankings/{ranking_id}/explicacion/stream", tags=["rankings"])
async def explicar_ranking(ranking_id: str, request: Request,
                           session: AsyncSession = Depends(get_session)):
    """Genera la explicacion del ranking guardado, en NDJSON (igual que /explain/stream),
    y la guarda al terminar. 409 si ese ranking ya tiene una: solo se regenera si el
    ranking cambia."""
    if not models_loaded():
        raise HTTPException(status_code=503, detail="Modelos no cargados")
    r = await session.get(RankingORM, ranking_id)
    if r is None:
        raise HTTPException(status_code=404, detail="Ranking no encontrado")
    if await session.get(ExplicacionORM, ranking_id) is not None:
        raise HTTPException(
            status_code=409,
            detail="Este ranking ya tiene una explicación guardada. Solo se genera de "
                   "nuevo si el ranking cambia.")
    if ranking_id in _GENERANDO:
        raise HTTPException(status_code=409, detail="Ya se está generando la explicación")
    paciente = await session.get(PatientORM, r.patient_id)
    nombre = paciente.nombre if paciente else "el paciente"
    pf, animales, resultados = r.paciente, r.animales, r.resultados
    evidencia = await run_in_threadpool(
        construir_evidencia, {**pf, "nombre": nombre}, animales, resultados)

    _GENERANDO.add(ranking_id)
    usuario = request.state.user  # la sesion de la peticion ya estara cerrada al terminar el stream

    def linea(obj) -> str:
        return json.dumps(obj, ensure_ascii=False) + "\n"

    async def generar():
        texto, error = "", None
        try:
            yield linea({"tipo": "evidencia", "datos": evidencia})
            disponible, detalle = await run_in_threadpool(lm_studio_disponible)
            if not disponible:
                error = detalle
                yield linea({"tipo": "error", "detalle": detalle})
            else:
                try:
                    async for delta in iterate_in_threadpool(
                            llamar_lm_studio_stream(construir_prompt(evidencia))):
                        texto += delta
                        yield linea({"tipo": "texto", "delta": delta})
                except Exception as exc:
                    error = str(exc)
                    yield linea({"tipo": "error", "detalle": error})
            # Solo se guarda un texto completo: con error a mitad de camino, o sin
            # LLM, queda sin guardar y se puede volver a intentar.
            if texto.strip() and error is None:
                async with SessionLocal() as s2:
                    s2.add(ExplicacionORM(ranking_id=ranking_id, texto=texto,
                                          evidencia=evidencia, aviso=AVISO_EXPLICACION))
                    await registrar(s2, request, "explicacion.generar", "paciente",
                                    r.patient_id, user=usuario)
                    await s2.commit()
            yield linea({"tipo": "fin", "aviso": AVISO_EXPLICACION})
        finally:
            _GENERANDO.discard(ranking_id)

    return StreamingResponse(
        generar(),
        media_type="application/x-ndjson; charset=utf-8",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
