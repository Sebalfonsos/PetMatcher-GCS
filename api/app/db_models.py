"""Modelos ORM: pacientes, animales y (asignación embebida en animal)."""
from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import JSON, Boolean, DateTime, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base


class PatientORM(Base):
    __tablename__ = "patients"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    nombre: Mapped[str] = mapped_column(String, default="Paciente")
    # Datos basicos
    edad_paciente: Mapped[int] = mapped_column(Integer, default=0)
    sexo_paciente: Mapped[str] = mapped_column(String, default="femenino")
    entorno_familiar: Mapped[str] = mapped_column(String, default="estable")
    preferencia_animal: Mapped[str] = mapped_column(String, default="perro")
    experiencia_previa_con_animales: Mapped[str] = mapped_column(String, default="no")
    # Test ADHD-RS: las 18 respuestas (0-3). Es lo UNICO que se guarda; IN/HI/presentacion
    # se calculan al leer (adhd_rs.perfil) para no desincronizarse. NULL = paciente legado.
    respuestas_adhd: Mapped[list[int] | None] = mapped_column(JSON, nullable=True)


class AnimalORM(Base):
    __tablename__ = "animals"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    nombre: Mapped[str] = mapped_column(String, default="Sin nombre")
    # 13 features
    tipo_animal: Mapped[str] = mapped_column(String, default="perro")
    sexo_animal: Mapped[str] = mapped_column(String, default="macho")
    edad_animal: Mapped[int] = mapped_column(Integer, default=0)
    raza: Mapped[str] = mapped_column(String, default="mestizo")
    peso_kg: Mapped[float] = mapped_column(Float, default=10.0)
    nivel_energia_animal: Mapped[int] = mapped_column(Integer, default=3)
    nivel_sociabilidad_animal: Mapped[int] = mapped_column(Integer, default=3)
    nivel_calma_animal: Mapped[int] = mapped_column(Integer, default=3)
    tolerancia_ruido: Mapped[int] = mapped_column(Integer, default=3)
    tolerancia_contacto: Mapped[int] = mapped_column(Integer, default=3)
    tipo_entrenamiento: Mapped[str] = mapped_column(String, default="apoyo emocional")
    experiencia_terapeutica_meses: Mapped[int] = mapped_column(Integer, default=0)
    certificado_terapia: Mapped[str] = mapped_column(String, default="no")

    notas: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Asignación: null = disponible. FK lógica al paciente.
    asignado_a_paciente_id: Mapped[str | None] = mapped_column(
        ForeignKey("patients.id", ondelete="SET NULL"), nullable=True
    )


def _ahora() -> datetime:
    return datetime.now(timezone.utc)


class RankingORM(Base):
    """Ultimo ranking generado para un paciente (uno por paciente).

    Guarda una INSTANTANEA de lo que se uso (paciente y animales con sus features),
    no solo los resultados: asi la explicacion se calcula sobre exactamente lo mismo
    que el ranking, aunque luego se edite al paciente o a un animal. Para saber si
    sigue vigente se comparan las firmas con el estado actual.
    """

    __tablename__ = "rankings"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    patient_id: Mapped[str] = mapped_column(
        ForeignKey("patients.id", ondelete="CASCADE"), unique=True, index=True)
    generado_en: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_ahora)
    # Features del paciente usadas (5 basicos + respuestas_adhd) y su firma.
    paciente: Mapped[dict] = mapped_column(JSON)
    paciente_firma: Mapped[str] = mapped_column(String)
    # Animales rankeados: [{id, nombre, ...13 features}] y firma por animal {id: hash}.
    animales: Mapped[list] = mapped_column(JSON)
    animales_firma: Mapped[dict] = mapped_column(JSON)
    # Salida de predict_batch, ordenada: [{animal_id, efectividad, categoria, por_modelo}].
    resultados: Mapped[list] = mapped_column(JSON)
    # Firma de (paciente + animal_id/efectividad): igual firma = el ranking no cambio.
    firma: Mapped[str] = mapped_column(String)


class ExplicacionORM(Base):
    """Respuesta de "Mas informacion del resultado". Una por ranking: si el ranking
    se reemplaza, la explicacion se borra en cascada y se puede generar otra."""

    __tablename__ = "explicaciones"

    ranking_id: Mapped[str] = mapped_column(
        ForeignKey("rankings.id", ondelete="CASCADE"), primary_key=True)
    generado_en: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_ahora)
    texto: Mapped[str] = mapped_column(Text)
    evidencia: Mapped[dict] = mapped_column(JSON)
    aviso: Mapped[str] = mapped_column(Text, default="")
    detalle_llm: Mapped[str] = mapped_column(Text, default="")


class UserORM(Base):
    """Usuario del sistema. Rol `admin` (gestiona usuarios y ve la auditoria) o
    `terapeuta` (usa pacientes, animales y rankings)."""

    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    username: Mapped[str] = mapped_column(String, unique=True, index=True)
    nombre: Mapped[str] = mapped_column(String, default="")
    password_hash: Mapped[str] = mapped_column(String)
    rol: Mapped[str] = mapped_column(String, default="terapeuta")
    activo: Mapped[bool] = mapped_column(Boolean, default=True)
    # Se incrementa al cambiar/restablecer la contrasena: invalida los tokens emitidos antes.
    token_version: Mapped[int] = mapped_column(Integer, default=0)
    creado_en: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_ahora)
    ultimo_login: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class AuditORM(Base):
    """Registro de eventos por usuario. Es de solo anadir: no hay rutas que lo editen.

    `username` se copia a proposito (sin FK): el historial sobrevive al borrado del usuario.
    `detalle` NO guarda datos clinicos, solo nombres de campos cambiados y similares.
    """

    __tablename__ = "audit_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    ts: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_ahora, index=True)
    user_id: Mapped[str | None] = mapped_column(String, nullable=True, index=True)
    username: Mapped[str] = mapped_column(String, default="", index=True)
    accion: Mapped[str] = mapped_column(String, index=True)
    recurso_tipo: Mapped[str | None] = mapped_column(String, nullable=True)
    recurso_id: Mapped[str | None] = mapped_column(String, nullable=True)
    exito: Mapped[bool] = mapped_column(Boolean, default=True)
    ip: Mapped[str | None] = mapped_column(String, nullable=True)
    detalle: Mapped[dict | None] = mapped_column(JSON, nullable=True)
