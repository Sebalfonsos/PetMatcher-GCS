"""Login, perfil propio, CRUD de usuarios (admin) y consulta del log de eventos (admin)."""
from __future__ import annotations

import os
import re
import secrets
import uuid
from datetime import datetime, timezone
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .db import SessionLocal, get_session
from .db_models import AuditORM, UserORM
from .security import (
    bloqueado, crear_token, current_user, hash_password, limpiar_fallos, registrar,
    registrar_fallo, require_admin, verificar_o_relleno, verify_password,
)

router = APIRouter()

_USERNAME = re.compile(r"^[A-Za-z0-9_.-]{3,40}$")
Rol = Literal["admin", "terapeuta"]


def _validar_username(v: str) -> str:
    v = v.strip().lower()
    if not _USERNAME.match(v):
        raise ValueError("Usuario de 3 a 40 caracteres: letras, numeros, . _ -")
    return v


class LoginIn(BaseModel):
    username: str = Field(..., max_length=80)
    password: str = Field(..., max_length=200)


class UserOut(BaseModel):
    id: str
    username: str
    nombre: str
    rol: Rol
    activo: bool
    creado_en: datetime
    ultimo_login: datetime | None = None

    model_config = {"from_attributes": True}


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expira: datetime
    user: UserOut


class UserCreate(BaseModel):
    username: str
    nombre: str = Field("", max_length=120)
    password: str = Field(..., min_length=10, max_length=128)
    rol: Rol = "terapeuta"

    _u = field_validator("username")(_validar_username)


class UserUpdate(BaseModel):
    nombre: str | None = Field(None, max_length=120)
    rol: Rol | None = None
    activo: bool | None = None
    password: str | None = Field(None, min_length=10, max_length=128)  # restablecer


class PasswordChange(BaseModel):
    actual: str = Field(..., max_length=200)
    nueva: str = Field(..., min_length=10, max_length=128)


class AuditOut(BaseModel):
    id: int
    ts: datetime
    user_id: str | None
    username: str
    accion: str
    recurso_tipo: str | None
    recurso_id: str | None
    exito: bool
    ip: str | None
    detalle: dict | None

    model_config = {"from_attributes": True}


class AuditPage(BaseModel):
    total: int
    items: list[AuditOut]


# ---------- Auth ----------

@router.post("/auth/login", response_model=TokenOut, tags=["auth"])
async def login(payload: LoginIn, request: Request,
                session: AsyncSession = Depends(get_session)):
    username = payload.username.strip().lower()
    ip = request.client.host if request.client else "?"
    clave = f"{username}|{ip}"
    espera = bloqueado(clave)
    if espera:
        await registrar(session, request, "auth.bloqueado", "usuario", None,
                        {"username": username}, exito=False, username=username, commit=True)
        raise HTTPException(429, f"Demasiados intentos. Reintenta en {espera} s",
                            headers={"Retry-After": str(espera)})

    user = (await session.execute(
        select(UserORM).where(UserORM.username == username))).scalar_one_or_none()
    ok = verificar_o_relleno(payload.password, user)
    if not ok or user is None or not user.activo:
        registrar_fallo(clave)
        await registrar(
            session, request, "auth.login_fallido", "usuario", user.id if user else None,
            {"username": username, "motivo": "inactivo" if ok and user else "credenciales"},
            exito=False, username=username, commit=True)
        # Mismo mensaje para usuario inexistente, clave mala o cuenta desactivada.
        raise HTTPException(401, "Usuario o contrasena incorrectos")

    limpiar_fallos(clave)
    user.ultimo_login = datetime.now(timezone.utc)
    await registrar(session, request, "auth.login", "usuario", user.id, user=user)
    await session.commit()
    token, exp = crear_token(user)
    return TokenOut(access_token=token, expira=exp, user=UserOut.model_validate(user))


@router.get("/auth/me", response_model=UserOut, tags=["auth"])
async def me(user: UserORM = Depends(current_user)):
    return user


@router.post("/auth/logout", status_code=204, tags=["auth"])
async def logout(request: Request, user: UserORM = Depends(current_user),
                 session: AsyncSession = Depends(get_session)):
    """El token es sin estado: el cliente lo descarta. Esto solo deja el evento en el log."""
    await registrar(session, request, "auth.logout", "usuario", user.id, commit=True)


@router.post("/auth/password", status_code=204, tags=["auth"])
async def cambiar_password(payload: PasswordChange, request: Request,
                           user: UserORM = Depends(current_user),
                           session: AsyncSession = Depends(get_session)):
    if not verify_password(payload.actual, user.password_hash):
        await registrar(session, request, "auth.cambiar_password", "usuario", user.id,
                        exito=False, commit=True)
        raise HTTPException(400, "La contrasena actual no es correcta")
    user.password_hash = hash_password(payload.nueva)
    user.token_version += 1  # cierra las demas sesiones
    await registrar(session, request, "auth.cambiar_password", "usuario", user.id)
    await session.commit()


# ---------- Usuarios (solo admin) ----------

async def _admins_activos(session: AsyncSession) -> int:
    return await session.scalar(
        select(func.count()).select_from(UserORM)
        .where(UserORM.rol == "admin", UserORM.activo.is_(True))) or 0


async def _user_or_404(session: AsyncSession, user_id: str) -> UserORM:
    u = await session.get(UserORM, user_id)
    if u is None:
        raise HTTPException(404, "Usuario no encontrado")
    return u


@router.get("/admin/users", response_model=list[UserOut], tags=["admin"])
async def list_users(_: UserORM = Depends(require_admin),
                     session: AsyncSession = Depends(get_session)):
    res = await session.execute(select(UserORM).order_by(UserORM.username))
    return list(res.scalars())


@router.post("/admin/users", response_model=UserOut, status_code=201, tags=["admin"])
async def create_user(payload: UserCreate, request: Request,
                      _: UserORM = Depends(require_admin),
                      session: AsyncSession = Depends(get_session)):
    existe = await session.scalar(
        select(UserORM.id).where(UserORM.username == payload.username))
    if existe:
        raise HTTPException(409, "Ese usuario ya existe")
    u = UserORM(id=str(uuid.uuid4()), username=payload.username, nombre=payload.nombre,
                password_hash=hash_password(payload.password), rol=payload.rol)
    session.add(u)
    await registrar(session, request, "usuario.crear", "usuario", u.id,
                    {"username": u.username, "rol": u.rol})
    await session.commit()
    await session.refresh(u)
    return u


@router.put("/admin/users/{user_id}", response_model=UserOut, tags=["admin"])
async def update_user(user_id: str, payload: UserUpdate, request: Request,
                      admin: UserORM = Depends(require_admin),
                      session: AsyncSession = Depends(get_session)):
    u = await _user_or_404(session, user_id)
    cambios: dict = {}
    if payload.nombre is not None and payload.nombre != u.nombre:
        u.nombre = payload.nombre
        cambios["nombre"] = True
    if payload.rol is not None and payload.rol != u.rol:
        cambios["rol"] = {"de": u.rol, "a": payload.rol}
        u.rol = payload.rol
    if payload.activo is not None and payload.activo != u.activo:
        cambios["activo"] = payload.activo
        u.activo = payload.activo
    if payload.password is not None:
        u.password_hash = hash_password(payload.password)
        u.token_version += 1
        cambios["password_restablecida"] = True
    # No dejar el sistema sin administradores (ni auto-bloquearse por error).
    if (u.rol != "admin" or not u.activo) and u.id == admin.id:
        raise HTTPException(400, "No puedes quitarte el rol admin ni desactivarte a ti mismo")
    await session.flush()
    if await _admins_activos(session) == 0:
        await session.rollback()
        raise HTTPException(400, "Debe quedar al menos un administrador activo")
    if cambios:
        await registrar(session, request, "usuario.editar", "usuario", u.id,
                        {"username": u.username, **cambios})
    await session.commit()
    await session.refresh(u)
    return u


@router.delete("/admin/users/{user_id}", status_code=204, tags=["admin"])
async def delete_user(user_id: str, request: Request,
                      admin: UserORM = Depends(require_admin),
                      session: AsyncSession = Depends(get_session)):
    u = await _user_or_404(session, user_id)
    if u.id == admin.id:
        raise HTTPException(400, "No puedes eliminar tu propio usuario")
    if u.rol == "admin" and u.activo and await _admins_activos(session) <= 1:
        raise HTTPException(400, "Debe quedar al menos un administrador activo")
    await registrar(session, request, "usuario.eliminar", "usuario", u.id,
                    {"username": u.username, "rol": u.rol})
    await session.delete(u)
    await session.commit()


# ---------- Log de eventos (solo admin) ----------

@router.get("/admin/audit", response_model=AuditPage, tags=["admin"])
async def list_audit(
    request: Request,
    _: UserORM = Depends(require_admin),
    session: AsyncSession = Depends(get_session),
    username: str | None = None,
    accion: str | None = Query(None, description="Prefijo, p. ej. 'paciente.' o 'auth.login'"),
    exito: bool | None = None,
    desde: datetime | None = None,
    hasta: datetime | None = None,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    filtros = []
    if username:
        filtros.append(AuditORM.username == username.strip().lower())
    if accion:
        filtros.append(AuditORM.accion.startswith(accion))
    if exito is not None:
        filtros.append(AuditORM.exito.is_(exito))
    if desde:
        filtros.append(AuditORM.ts >= desde)
    if hasta:
        filtros.append(AuditORM.ts <= hasta)
    total = await session.scalar(select(func.count()).select_from(AuditORM).where(*filtros))
    res = await session.execute(
        select(AuditORM).where(*filtros)
        .order_by(AuditORM.ts.desc(), AuditORM.id.desc()).limit(limit).offset(offset))
    return AuditPage(total=total or 0, items=[AuditOut.model_validate(r) for r in res.scalars()])


# ---------- Arranque: primer administrador ----------

async def asegurar_admin_inicial() -> None:
    """Si no hay usuarios, crea el primer admin. Credenciales de PETMATCHER_ADMIN_USER /
    PETMATCHER_ADMIN_PASSWORD; sin clave se genera una al azar y se imprime UNA vez."""
    async with SessionLocal() as session:
        n = await session.scalar(select(func.count()).select_from(UserORM))
        if n:
            return
        username = (os.environ.get("PETMATCHER_ADMIN_USER") or "admin").strip().lower()
        password = os.environ.get("PETMATCHER_ADMIN_PASSWORD")
        generada = not password
        if generada:
            password = secrets.token_urlsafe(12)
        u = UserORM(id=str(uuid.uuid4()), username=username, nombre="Administrador",
                    password_hash=hash_password(password), rol="admin")
        session.add(u)
        session.add(AuditORM(username="sistema", accion="usuario.crear", recurso_tipo="usuario",
                             recurso_id=u.id, detalle={"username": username, "rol": "admin",
                                                       "origen": "arranque"}))
        await session.commit()
        if generada:
            print(f"[PetMatcher] Primer administrador creado: usuario '{username}' "
                  f"contrasena '{password}'  (cambiala al entrar)")
        else:
            print(f"[PetMatcher] Primer administrador creado: usuario '{username}'")
