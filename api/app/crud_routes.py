"""Rutas CRUD de animales y pacientes (persistencia en PostgreSQL)."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .adhd_rs import perfil as perfil_adhd
from .db import get_session
from .db_models import AnimalORM, PatientORM
from .security import campos_cambiados, registrar
from .schemas import (
    AnimalIn,
    AnimalOut,
    AssignRequest,
    PatientIn,
    PatientOut,
)

router = APIRouter()


def patient_out(p: PatientORM) -> PatientOut:
    """ORM -> respuesta, con el perfil ADHD-RS calculado al vuelo (no se almacena)."""
    resp = p.respuestas_adhd
    return PatientOut(
        id=p.id, nombre=p.nombre, edad_paciente=p.edad_paciente,
        sexo_paciente=p.sexo_paciente, entorno_familiar=p.entorno_familiar,
        preferencia_animal=p.preferencia_animal,
        experiencia_previa_con_animales=p.experiencia_previa_con_animales,
        respuestas_adhd=resp,
        perfil_adhd=perfil_adhd(resp) if resp else None,
    )


# ---------- Animales ----------

@router.get("/animals", response_model=list[AnimalOut], tags=["animals"])
async def list_animals(session: AsyncSession = Depends(get_session)):
    res = await session.execute(select(AnimalORM).order_by(AnimalORM.nombre))
    return list(res.scalars())


@router.post("/animals", response_model=AnimalOut, status_code=201, tags=["animals"])
async def create_animal(payload: AnimalIn, request: Request,
                        session: AsyncSession = Depends(get_session)):
    animal = AnimalORM(id=str(uuid.uuid4()), **payload.model_dump())
    session.add(animal)
    await registrar(session, request, "animal.crear", "animal", animal.id,
                    {"nombre": animal.nombre})
    await session.commit()
    await session.refresh(animal)
    return animal


async def _get_or_404(session: AsyncSession, animal_id: str) -> AnimalORM:
    animal = await session.get(AnimalORM, animal_id)
    if animal is None:
        raise HTTPException(status_code=404, detail="Animal no encontrado")
    return animal


@router.get("/animals/{animal_id}", response_model=AnimalOut, tags=["animals"])
async def get_animal(animal_id: str, session: AsyncSession = Depends(get_session)):
    return await _get_or_404(session, animal_id)


@router.put("/animals/{animal_id}", response_model=AnimalOut, tags=["animals"])
async def update_animal(
    animal_id: str, payload: AnimalIn, request: Request,
    session: AsyncSession = Depends(get_session)
):
    animal = await _get_or_404(session, animal_id)
    nuevos = payload.model_dump()
    await registrar(session, request, "animal.editar", "animal", animal.id,
                    {"nombre": animal.nombre, "campos": campos_cambiados(animal, nuevos)})
    for k, v in nuevos.items():
        setattr(animal, k, v)
    await session.commit()
    await session.refresh(animal)
    return animal


@router.delete("/animals/{animal_id}", status_code=204, tags=["animals"])
async def delete_animal(animal_id: str, request: Request,
                        session: AsyncSession = Depends(get_session)):
    animal = await _get_or_404(session, animal_id)
    await registrar(session, request, "animal.eliminar", "animal", animal.id,
                    {"nombre": animal.nombre})
    await session.delete(animal)
    await session.commit()


@router.post("/animals/{animal_id}/assign", response_model=AnimalOut, tags=["animals"])
async def assign_animal(
    animal_id: str, payload: AssignRequest, request: Request,
    session: AsyncSession = Depends(get_session)
):
    animal = await _get_or_404(session, animal_id)
    if animal.asignado_a_paciente_id is not None:
        raise HTTPException(status_code=409, detail="El animal ya está asignado")
    patient = await session.get(PatientORM, payload.patient_id)
    if patient is None:
        raise HTTPException(status_code=404, detail="Paciente no encontrado")
    animal.asignado_a_paciente_id = payload.patient_id
    await registrar(session, request, "animal.asignar", "animal", animal.id,
                    {"nombre": animal.nombre, "paciente_id": patient.id})
    await session.commit()
    await session.refresh(animal)
    return animal


@router.post("/animals/{animal_id}/release", response_model=AnimalOut, tags=["animals"])
async def release_animal(animal_id: str, request: Request,
                         session: AsyncSession = Depends(get_session)):
    animal = await _get_or_404(session, animal_id)
    await registrar(session, request, "animal.liberar", "animal", animal.id,
                    {"nombre": animal.nombre, "paciente_id": animal.asignado_a_paciente_id})
    animal.asignado_a_paciente_id = None
    await session.commit()
    await session.refresh(animal)
    return animal


# ---------- Pacientes ----------

@router.get("/patients", response_model=list[PatientOut], tags=["patients"])
async def list_patients(session: AsyncSession = Depends(get_session)):
    res = await session.execute(select(PatientORM).order_by(PatientORM.nombre))
    return [patient_out(p) for p in res.scalars()]


@router.post("/patients", response_model=PatientOut, status_code=201, tags=["patients"])
async def create_patient(payload: PatientIn, request: Request,
                         session: AsyncSession = Depends(get_session)):
    patient = PatientORM(id=str(uuid.uuid4()), **payload.model_dump())
    session.add(patient)
    await registrar(session, request, "paciente.crear", "paciente", patient.id)
    await session.commit()
    await session.refresh(patient)
    return patient_out(patient)


async def _patient_or_404(session: AsyncSession, patient_id: str) -> PatientORM:
    patient = await session.get(PatientORM, patient_id)
    if patient is None:
        raise HTTPException(status_code=404, detail="Paciente no encontrado")
    return patient


@router.get("/patients/{patient_id}", response_model=PatientOut, tags=["patients"])
async def get_patient(patient_id: str, request: Request,
                      session: AsyncSession = Depends(get_session)):
    patient = await _patient_or_404(session, patient_id)
    # Acceso a datos de salud de un paciente concreto: se registra (los listados no).
    await registrar(session, request, "paciente.ver", "paciente", patient.id, commit=True)
    return patient_out(patient)


@router.put("/patients/{patient_id}", response_model=PatientOut, tags=["patients"])
async def update_patient(
    patient_id: str, payload: PatientIn, request: Request,
    session: AsyncSession = Depends(get_session)
):
    patient = await _patient_or_404(session, patient_id)
    nuevos = payload.model_dump()
    await registrar(session, request, "paciente.editar", "paciente", patient.id,
                    {"campos": campos_cambiados(patient, nuevos)})
    for k, v in nuevos.items():
        setattr(patient, k, v)
    await session.commit()
    await session.refresh(patient)
    return patient_out(patient)


@router.delete("/patients/{patient_id}", status_code=204, tags=["patients"])
async def delete_patient(patient_id: str, request: Request,
                         session: AsyncSession = Depends(get_session)):
    patient = await _patient_or_404(session, patient_id)
    await registrar(session, request, "paciente.eliminar", "paciente", patient.id)
    # Libera los animales que tuviera asignados antes de borrar.
    res = await session.execute(
        select(AnimalORM).where(AnimalORM.asignado_a_paciente_id == patient_id)
    )
    for animal in res.scalars():
        animal.asignado_a_paciente_id = None
    await session.delete(patient)
    await session.commit()
