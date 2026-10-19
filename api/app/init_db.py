"""Creación de tablas y datos de ejemplo (dev). En producción usar Alembic."""
from __future__ import annotations

import uuid

from sqlalchemy import func, select, text

from .db import Base, SessionLocal, engine
from .db_models import AnimalORM

_SEED_ANIMALS = [
    dict(nombre="Max", tipo_animal="perro", sexo_animal="macho", edad_animal=4,
         raza="golden retriever", peso_kg=30, nivel_energia_animal=3,
         nivel_sociabilidad_animal=5, nivel_calma_animal=4, tolerancia_ruido=5,
         tolerancia_contacto=5, tipo_entrenamiento="acompanamiento en tdah",
         experiencia_terapeutica_meses=30, certificado_terapia="si",
         notas="Muy paciente con niños. Ideal para TDAH."),
    dict(nombre="Luna", tipo_animal="perro", sexo_animal="hembra", edad_animal=3,
         raza="border collie", peso_kg=18, nivel_energia_animal=5,
         nivel_sociabilidad_animal=4, nivel_calma_animal=2, tolerancia_ruido=3,
         tolerancia_contacto=4, tipo_entrenamiento="regulacion conductual",
         experiencia_terapeutica_meses=18, certificado_terapia="si",
         notas="Enérgica, buena para sesiones activas."),
    dict(nombre="Michi", tipo_animal="gato", sexo_animal="hembra", edad_animal=2,
         raza="ragdoll", peso_kg=5, nivel_energia_animal=2,
         nivel_sociabilidad_animal=3, nivel_calma_animal=5, tolerancia_ruido=2,
         tolerancia_contacto=3, tipo_entrenamiento="reduccion de ansiedad",
         experiencia_terapeutica_meses=10, certificado_terapia="no",
         notas="Tranquila, para pacientes con ansiedad."),
    dict(nombre="Copo", tipo_animal="conejo", sexo_animal="macho", edad_animal=1,
         raza="mini lop", peso_kg=2, nivel_energia_animal=2,
         nivel_sociabilidad_animal=3, nivel_calma_animal=5, tolerancia_ruido=1,
         tolerancia_contacto=2, tipo_entrenamiento="acompanamiento tranquilo",
         experiencia_terapeutica_meses=4, certificado_terapia="no",
         notas="Estimulación sensorial suave."),
    dict(nombre="Trueno", tipo_animal="caballo", sexo_animal="macho", edad_animal=8,
         raza="criollo", peso_kg=420, nivel_energia_animal=4,
         nivel_sociabilidad_animal=4, nivel_calma_animal=3, tolerancia_ruido=3,
         tolerancia_contacto=4, tipo_entrenamiento="equinoterapia",
         experiencia_terapeutica_meses=40, certificado_terapia="si",
         notas="Equinoterapia, gran experiencia."),
]


# Columnas del perfil conductual v1 (6 niveles 1-5), reemplazadas por el test ADHD-RS.
_COLUMNAS_LEGADAS = ["nivel_hiperactividad", "nivel_atencion", "nivel_impulsividad",
                     "nivel_ansiedad", "nivel_sociabilidad", "sensibilidad_sensorial"]


async def _migrar_pacientes_v2(conn) -> None:
    """Migracion ligera (sin Alembic): create_all no altera tablas existentes.

    Si la tabla `patients` viene del esquema v1 se agrega `respuestas_adhd` y se
    quitan las 6 columnas de niveles (eran NOT NULL: sin quitarlas, los INSERT nuevos
    fallan). Los pacientes antiguos se conservan SIN respuestas y la app les pide
    completar el test. Idempotente.
    """
    await conn.execute(text(
        "ALTER TABLE patients ADD COLUMN IF NOT EXISTS respuestas_adhd JSON"))
    for col in _COLUMNAS_LEGADAS:
        await conn.execute(text(f"ALTER TABLE patients DROP COLUMN IF EXISTS {col}"))


async def init_db(seed: bool = True) -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await _migrar_pacientes_v2(conn)

    if not seed:
        return

    async with SessionLocal() as session:
        count = await session.scalar(select(func.count()).select_from(AnimalORM))
        if count and count > 0:
            return
        for data in _SEED_ANIMALS:
            session.add(AnimalORM(id=str(uuid.uuid4()), **data))
        await session.commit()
