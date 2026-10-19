"""Autenticacion (JWT), hash de contrasenas, roles y registro de auditoria."""
from __future__ import annotations

import base64
import hashlib
import hmac
import os
import secrets
import time
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from .db import get_session
from .db_models import AuditORM, UserORM

ROLES = ("admin", "terapeuta")
TOKEN_HORAS = int(os.environ.get("PETMATCHER_TOKEN_HORAS", "8"))
_ALG = "HS256"

# Sin PETMATCHER_JWT_SECRET se genera uno al arrancar: funciona, pero cada reinicio
# cierra todas las sesiones. En produccion hay que fijarlo.
_SECRET = os.environ.get("PETMATCHER_JWT_SECRET") or secrets.token_urlsafe(48)
SECRETO_EFIMERO = not os.environ.get("PETMATCHER_JWT_SECRET")

_bearer = HTTPBearer(auto_error=False)


# ---------- Contrasenas (scrypt, solo libreria estandar) ----------

_N, _R, _P = 2**14, 8, 1


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    h = hashlib.scrypt(password.encode(), salt=salt, n=_N, r=_R, p=_P, dklen=32)
    b = lambda x: base64.b64encode(x).decode()
    return f"scrypt${_N}${_R}${_P}${b(salt)}${b(h)}"


def verify_password(password: str, stored: str) -> bool:
    try:
        _, n, r, p, salt, h = stored.split("$")
        esperado = base64.b64decode(h)
        calculado = hashlib.scrypt(
            password.encode(), salt=base64.b64decode(salt),
            n=int(n), r=int(r), p=int(p), dklen=len(esperado))
        return hmac.compare_digest(calculado, esperado)
    except Exception:
        return False


# Hash de relleno: para que un usuario inexistente tarde lo mismo que uno real.
_HASH_FALSO = hash_password(secrets.token_urlsafe(16))


def verificar_o_relleno(password: str, user: UserORM | None) -> bool:
    if user is None:
        verify_password(password, _HASH_FALSO)
        return False
    return verify_password(password, user.password_hash)


# ---------- Bloqueo por intentos fallidos (en memoria, un solo proceso) ----------

_MAX_FALLOS = 5
_BLOQUEO_SEG = 300
_fallos: dict[str, tuple[int, float]] = {}


def bloqueado(clave: str) -> int:
    """Segundos que faltan para poder reintentar (0 si no esta bloqueado)."""
    n, hasta = _fallos.get(clave, (0, 0.0))
    if n >= _MAX_FALLOS and hasta > time.time():
        return int(hasta - time.time()) + 1
    return 0


def registrar_fallo(clave: str) -> None:
    n, hasta = _fallos.get(clave, (0, 0.0))
    if hasta and hasta <= time.time():
        n = 0
    _fallos[clave] = (n + 1, time.time() + _BLOQUEO_SEG)


def limpiar_fallos(clave: str) -> None:
    _fallos.pop(clave, None)


# ---------- Tokens ----------

def crear_token(user: UserORM) -> tuple[str, datetime]:
    exp = datetime.now(timezone.utc) + timedelta(hours=TOKEN_HORAS)
    token = jwt.encode(
        {"sub": user.id, "tv": user.token_version, "exp": exp}, _SECRET, algorithm=_ALG)
    return token, exp


async def current_user(
    request: Request,
    cred: HTTPAuthorizationCredentials | None = Depends(_bearer),
    session: AsyncSession = Depends(get_session),
) -> UserORM:
    """Usuario autenticado. Se relee de la BD en cada peticion: desactivarlo, cambiarle
    el rol o la contrasena surte efecto de inmediato, sin esperar a que venza el token."""
    if cred is None:
        raise HTTPException(401, "No autenticado", headers={"WWW-Authenticate": "Bearer"})
    try:
        data = jwt.decode(cred.credentials, _SECRET, algorithms=[_ALG])
    except jwt.PyJWTError:
        raise HTTPException(401, "Sesion invalida o vencida",
                            headers={"WWW-Authenticate": "Bearer"})
    user = await session.get(UserORM, data.get("sub"))
    if user is None or not user.activo or user.token_version != data.get("tv"):
        raise HTTPException(401, "Sesion invalida o vencida",
                            headers={"WWW-Authenticate": "Bearer"})
    request.state.user = user
    return user


async def require_admin(user: UserORM = Depends(current_user)) -> UserORM:
    if user.rol != "admin":
        raise HTTPException(403, "Requiere rol administrador")
    return user


# ---------- Auditoria ----------

def _ip(request: Request | None) -> str | None:
    return request.client.host if request is not None and request.client else None


async def registrar(
    session: AsyncSession,
    request: Request | None,
    accion: str,
    recurso_tipo: str | None = None,
    recurso_id: str | None = None,
    detalle: dict | None = None,
    *,
    exito: bool = True,
    user: UserORM | None = None,
    username: str | None = None,
    commit: bool = False,
) -> None:
    """Anade un evento a la sesion. Por defecto NO confirma: lo hace el commit de la
    ruta, asi la accion y su registro quedan en la misma transaccion. Para eventos de
    solo lectura (o fallidos) pasar commit=True."""
    u = user or getattr(getattr(request, "state", None), "user", None)
    session.add(AuditORM(
        user_id=u.id if u else None, username=u.username if u else (username or ""),
        accion=accion, recurso_tipo=recurso_tipo, recurso_id=recurso_id,
        exito=exito, ip=_ip(request), detalle=detalle))
    if commit:
        await session.commit()


def campos_cambiados(obj, nuevos: dict) -> list[str]:
    """Nombres de los campos que cambian (nunca los valores: son datos clinicos)."""
    return sorted(k for k, v in nuevos.items() if getattr(obj, k) != v)
