"""Configuración de base de datos (SQLAlchemy async + PostgreSQL)."""
from __future__ import annotations

import os

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

# En Docker viene de docker-compose (servicio db). Fallback a localhost para dev local.
DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql+asyncpg://petmatcher:petmatcher@localhost:5432/petmatcher",
)

engine = create_async_engine(DATABASE_URL, echo=False, pool_pre_ping=True)
SessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


async def get_session() -> AsyncSession:
    async with SessionLocal() as session:
        yield session
