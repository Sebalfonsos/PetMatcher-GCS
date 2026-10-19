"""PetMatcher — consola de exploración del modelo (Streamlit).

Equivalente a la interfaz original de `ml_model/app.py`, pero **consumiendo la
API** en vez de cargar los `.pkl` por su cuenta.

POR QUE VIA API Y NO CARGANDO EL .pkl:
    Replicar el preprocesado en un tercer lugar reintroduce el riesgo descrito en
    plan.md §11 (un desajuste de encoding u orden de columnas da predicciones
    inválidas y silenciosas). La API ya devuelve `por_modelo`, así que se ve lo
    mismo que en el original sin duplicar una línea de lógica de dominio.
    El catálogo de valores también viene de la API (`GET /catalog`).

Levantar:  docker compose up --build   ->   http://localhost:8501
"""
from __future__ import annotations

import json
import os

import pandas as pd
import requests
import streamlit as st

API = os.environ.get("PETMATCHER_API_URL", "http://localhost:8000").rstrip("/")
TIMEOUT = 20

st.set_page_config(page_title="PetMatcher — Consola del modelo",
                   page_icon="🐾", layout="wide")


# --------------------------------------------------------------------------- #
# Sesion: la consola exige iniciar sesion con un usuario de PetMatcher (la API
# registra sus acciones en el log de eventos igual que las de la app).
# --------------------------------------------------------------------------- #
def _h() -> dict:
    return {"Authorization": f"Bearer {st.session_state.get('token', '')}"}


def _vencida(r) -> None:
    """Si la API responde 401 la sesion caduco: vuelve al login."""
    if r.status_code == 401:
        st.session_state.pop("token", None)
        st.rerun()


if "token" not in st.session_state:
    st.title("🐾 PetMatcher — Consola del modelo")
    with st.form("login"):
        usuario = st.text_input("Usuario")
        clave = st.text_input("Contraseña", type="password")
        entrar = st.form_submit_button("Entrar")
    if entrar:
        try:
            r = requests.post(f"{API}/auth/login",
                              json={"username": usuario, "password": clave}, timeout=TIMEOUT)
        except Exception as exc:
            st.error(f"No se pudo contactar la API: {exc}")
        else:
            if r.ok:
                st.session_state["token"] = r.json()["access_token"]
                st.session_state["usuario"] = r.json()["user"]["username"]
                st.rerun()
            else:
                st.error(r.json().get("detail", "No se pudo iniciar sesión"))
    st.stop()

with st.sidebar:
    st.caption(f"Sesión: {st.session_state.get('usuario', '')}")
    if st.button("Cerrar sesión"):
        try:
            requests.post(f"{API}/auth/logout", headers=_h(), timeout=TIMEOUT)
        except Exception:
            pass
        st.session_state.pop("token", None)
        st.rerun()


# --------------------------------------------------------------------------- #
# Acceso a la API
# --------------------------------------------------------------------------- #
@st.cache_data(ttl=60)
def _catalog(token: str):  # el token entra en la clave de cache: no se comparte entre sesiones
    r = requests.get(f"{API}/catalog", headers={"Authorization": f"Bearer {token}"},
                     timeout=TIMEOUT)
    r.raise_for_status()
    return r.json()


@st.cache_data(ttl=10)
def get_health():
    try:
        return requests.get(f"{API}/health", timeout=TIMEOUT).json()
    except Exception as exc:
        return {"status": "unreachable", "error": str(exc)}


def get_catalog():
    return _catalog(st.session_state.get("token", ""))


def get_animals():
    r = requests.get(f"{API}/animals", headers=_h(), timeout=TIMEOUT)
    _vencida(r)
    r.raise_for_status()
    return r.json()


def predict(patient: dict, animals: list[dict]):
    r = requests.post(f"{API}/predict/batch",
                      json={"patient": patient, "animals": animals},
                      headers=_h(), timeout=TIMEOUT)
    _vencida(r)
    r.raise_for_status()
    return r.json()


def explain_stream(patient: dict, animals: list[dict], nombre: str, nombres: dict):
    """POST /explain/stream: va emitiendo los mensajes NDJSON a medida que llegan.

    Con el 7B la generación tarda ~un minuto, pero el primer token sale a los
    0,6 s: leer mientras se escribe hace que la espera no se sienta.
    """
    with requests.post(f"{API}/explain/stream", json={
            "patient": patient, "animals": animals,
            "nombre_paciente": nombre, "nombres_animales": nombres},
            headers=_h(), stream=True, timeout=300) as r:
        _vencida(r)
        r.raise_for_status()
        # Se decodifica a mano en UTF-8 en vez de usar decode_unicode=True: ese
        # parametro se fia del charset que declare el servidor y, si falta,
        # requests asume Latin-1 y rompe tildes y ñ. Acá el formato lo definimos
        # nosotros y siempre es UTF-8.
        for linea in r.iter_lines():
            if linea:
                yield json.loads(linea.decode("utf-8"))


COLOR = {"alta": "#16a34a", "media": "#d97706", "baja": "#dc2626",
         "no_recomendado": "#6b7280"}


def tabla(registros: list[dict]) -> pd.DataFrame:
    """DataFrame seguro para st.dataframe.

    Las columnas de la evidencia mezclan tipos (energía 5, certificado 'no'), y
    pyarrow falla al serializar un object column heterogéneo. Se pasan a texto.
    """
    df = pd.DataFrame(registros)
    for c in df.columns:
        if df[c].dtype == "object":
            df[c] = df[c].astype(str)
    return df


def badge(cat: str) -> str:
    return (f"<span style='background:{COLOR.get(cat, '#6b7280')};color:white;"
            f"padding:3px 10px;border-radius:999px;font-size:0.8rem;"
            f"font-weight:600'>{cat}</span>")


# --------------------------------------------------------------------------- #
# Barra lateral: estado del servicio
# --------------------------------------------------------------------------- #
health = get_health()
with st.sidebar:
    st.markdown("### Estado del servicio")
    if health.get("status") == "ok":
        st.success("API operativa · modelos cargados")
    elif health.get("status") == "degraded":
        st.warning("API arriba, pero SIN modelos cargados")
    else:
        st.error("API inalcanzable")
        st.caption(health.get("error", ""))
    st.caption(f"Endpoint: `{API}`")
    if health.get("models_dir"):
        st.caption(f"Modelos: `{health['models_dir']}`")
    st.divider()
    st.caption(
        "⚠️ **Datos sintéticos.** El modelo demuestra que el pipeline funciona, "
        "no eficacia terapéutica. Ver `dataset_synthetic/SCHEMA.md`."
    )

st.title("🐾 PetMatcher — Consola del modelo")
st.caption("Interactuá directamente con el modelo entrenado a través de la API.")

# --------------------------------------------------------------------------- #
# Navegación
#
# NO se usa `st.tabs`: su pestaña activa vive solo en el frontend, así que
# cualquier rerun (apretar un botón, mover un slider) la resetea a la primera.
#
# Y la sección se guarda en `seccion_actual`, una clave NORMAL de session_state,
# no en la clave del widget. Motivo: Streamlit descarta las claves de widgets que
# no se renderizaron en una corrida, y más abajo hay `st.stop()` (API caída,
# /catalog ilegible). Si esa rama se ejecuta, el widget no se registra, su clave
# se pierde y la corrida siguiente vuelve a la sección 1. Una clave normal
# sobrevive a eso.
#
# Por la misma razón el widget se declara ACÁ ARRIBA, antes de cualquier
# `st.stop()`: así se registra en todas las corridas.
# --------------------------------------------------------------------------- #
SEC_PRED = "🎯 Predicción individual"
SEC_RANK = "🏆 Ranking de animales"
SEC_SENS = "📊 Sensibilidad"
SEC_INFO = "ℹ️ Modelo y contrato"
SECCIONES = [SEC_PRED, SEC_RANK, SEC_SENS, SEC_INFO]

if st.session_state.get("seccion_actual") not in SECCIONES:
    st.session_state["seccion_actual"] = SEC_PRED


def _cambiar_seccion():
    elegido = st.session_state.get("nav_widget")
    if elegido in SECCIONES:
        st.session_state["seccion_actual"] = elegido


st.radio("Sección", SECCIONES, key="nav_widget",
         index=SECCIONES.index(st.session_state["seccion_actual"]),
         horizontal=True, label_visibility="collapsed",
         on_change=_cambiar_seccion)
seccion = st.session_state["seccion_actual"]
st.divider()

if health.get("status") == "unreachable":
    st.error(f"No se puede alcanzar la API en {API}. ¿Está levantado el servicio? "
             "`docker compose up --build`")
    st.stop()

try:
    cat = get_catalog()
except Exception as exc:
    st.error(f"No se pudo leer /catalog: {exc}")
    st.stop()

OPC = cat["opciones"]
RAZAS = cat["razas_por_tipo"]
ENTREN = cat["entrenamientos_por_tipo"]


# --------------------------------------------------------------------------- #
# 1. Predicción individual: 1 paciente x 1 animal
# --------------------------------------------------------------------------- #
# Perfiles de ejemplo (18 respuestas 0-3, items 1..18; impares = IN, pares = HI).
PERFILES_EJEMPLO = {
    "Ejemplo resuelto P001 (inatenta)": "212012212120113020",
    "Hiperactivo/impulsivo": "030303030303030303",
    "Inatento": "303030303030303030",
    "Combinado": "333333333333333333",
    "Sin presentación": "101010101010101010",
}


def score_adhd(respuestas: list[int]):
    r = requests.post(f"{API}/adhd-rs/score", json={"respuestas_adhd": respuestas},
                      headers=_h(), timeout=TIMEOUT)
    _vencida(r)
    r.raise_for_status()
    return r.json()


def form_paciente(prefix: str = "") -> dict:
    """Datos basicos + las 18 respuestas del ADHD-RS (las 7 features se derivan en la API)."""
    c1, c2 = st.columns(2)
    with c1:
        edad = st.number_input("Edad (17 o más)", 17, 99, 31, key=f"{prefix}edad_p")
        sexo = st.selectbox("Sexo", OPC["sexo_paciente"], key=f"{prefix}sexo_p")
        entorno = st.selectbox("Entorno familiar", OPC["entorno_familiar"],
                               key=f"{prefix}ent")
    with c2:
        pref = st.selectbox("Animal de preferencia", OPC["preferencia_animal"],
                            key=f"{prefix}pref")
        exp = st.selectbox("Experiencia previa con animales",
                           OPC["experiencia_previa_con_animales"], key=f"{prefix}exp")
    st.markdown("**Test ADHD-RS** — 18 respuestas de 0 a 3 en orden "
                "(impares = inatención, pares = hiperactividad/impulsividad)")
    ej = st.selectbox("Cargar un perfil de ejemplo", list(PERFILES_EJEMPLO),
                      key=f"{prefix}ej")
    # La clave incluye el ejemplo elegido: cambiarlo reinicia el campo de texto.
    txt = st.text_input("Respuestas (18 dígitos)", PERFILES_EJEMPLO[ej],
                        key=f"{prefix}resp_{ej}", max_chars=18)
    resp = [int(c) for c in txt if c in "0123"]
    if len(txt) != 18 or len(resp) != 18:
        st.warning("Escribí exactamente 18 dígitos entre 0 y 3.")
        resp = [0] * 18
    else:
        try:
            pf = score_adhd(resp)
            st.caption(f"IN {pf['IN']}/27 · HI {pf['HI']}/27 · total {pf['TOT']}/54 · "
                       f"síntomas IN {pf['n_sintomas_IN']} / HI {pf['n_sintomas_HI']} · "
                       f"**{pf['presentacion']}** · cribado "
                       f"{'positivo' if pf['cribado_positivo'] else 'negativo'} "
                       f"(corte {pf['corte_usado']})")
        except Exception as exc:
            st.error(f"No se pudo puntuar el test: {exc}")
    return {
        "edad_paciente": edad, "sexo_paciente": sexo,
        "entorno_familiar": entorno, "preferencia_animal": pref,
        "experiencia_previa_con_animales": exp, "respuestas_adhd": resp,
    }


def form_animal(prefix: str = "") -> dict:
    c1, c2 = st.columns(2)
    with c1:
        tipo = st.selectbox("Tipo", OPC["tipo_animal"], key=f"{prefix}tipo_a")
        raza = st.selectbox("Raza", RAZAS.get(tipo, []), key=f"{prefix}raza_{tipo}")
        sexo = st.selectbox("Sexo", OPC["sexo_animal"], key=f"{prefix}sexo_a")
        edad = st.number_input("Edad (años)", 0, 40, 4, key=f"{prefix}edad_a")
        peso = st.number_input("Peso (kg)", 0.1, 900.0, 20.0, step=0.5,
                               key=f"{prefix}peso")
        entren = st.selectbox("Entrenamiento", ENTREN.get(tipo, []),
                              key=f"{prefix}entren_{tipo}")
    with c2:
        energia = st.slider("Energía", 1, 5, 4, key=f"{prefix}ene")
        socia = st.slider("Sociabilidad", 1, 5, 5, key=f"{prefix}soc_a")
        calma = st.slider("Calma", 1, 5, 4, key=f"{prefix}cal")
        ruido = st.slider("Tolerancia al ruido", 1, 5, 4, key=f"{prefix}rui")
        contacto = st.slider("Tolerancia al contacto", 1, 5, 4, key=f"{prefix}con")
        meses = st.number_input("Experiencia terapéutica (meses)", 0, 240, 24,
                                key=f"{prefix}mes")
        cert = st.selectbox("Certificado de terapia", OPC["certificado_terapia"],
                            key=f"{prefix}cert")
    return {
        "id": "demo", "tipo_animal": tipo, "sexo_animal": sexo, "edad_animal": edad,
        "raza": raza, "peso_kg": peso, "nivel_energia_animal": energia,
        "nivel_sociabilidad_animal": socia, "nivel_calma_animal": calma,
        "tolerancia_ruido": ruido, "tolerancia_contacto": contacto,
        "tipo_entrenamiento": entren, "experiencia_terapeutica_meses": meses,
        "certificado_terapia": cert,
    }


if seccion == SEC_PRED:
    st.subheader("Un paciente contra un animal")
    st.caption("Las 25 features del modelo (5 datos básicos + 7 del ADHD-RS + 13 del animal).")
    ca, cb = st.columns(2)
    with ca:
        st.markdown("#### 🧑 Perfil del paciente")
        paciente = form_paciente("p_")
    with cb:
        st.markdown("#### 🐕 Perfil del animal")
        animal = form_animal("a_")

    if st.button("Calcular efectividad", type="primary", use_container_width=True):
        try:
            res = predict(paciente, [animal])[0]
        except Exception as exc:
            st.error(f"Error al predecir: {exc}")
        else:
            st.divider()
            k1, k2 = st.columns([1, 2])
            with k1:
                st.metric("Efectividad estimada", f"{res['efectividad']:.1f} %")
                st.markdown(badge(res["categoria"]), unsafe_allow_html=True)
            with k2:
                por = res.get("por_modelo", {})
                if por:
                    st.markdown("**Predicción de cada modelo**")
                    df = pd.DataFrame(
                        [{"modelo": k, "efectividad_%": v} for k, v in por.items()]
                    ).sort_values("efectividad_%", ascending=False)
                    st.dataframe(df, use_container_width=True, hide_index=True)
                    st.bar_chart(df.set_index("modelo"), height=180)
                    disp = max(por.values()) - min(por.values())
                    if disp > 15:
                        st.warning(
                            f"Los modelos discrepan en {disp:.1f} puntos. "
                            "El promedio de un ensemble disperso es poco confiable "
                            "(ver plan.md §11)."
                        )


# --------------------------------------------------------------------------- #
# 2. Ranking: 1 paciente x N animales de la base
# --------------------------------------------------------------------------- #
if seccion == SEC_RANK:
    st.subheader("Un paciente contra los animales de la base")
    st.caption("Usa `GET /animals` y `POST /predict/batch`: el mismo flujo que la app Flutter.")
    paciente_r = form_paciente("r_")
    solo_disp = st.checkbox("Solo animales disponibles (regla de negocio: "
                            "un animal asignado se excluye)", value=True)

    if st.button("Generar ranking", type="primary", use_container_width=True):
        try:
            animales = get_animals()
        except Exception as exc:
            st.error(f"No se pudieron leer los animales: {exc}")
            animales = []
        if solo_disp:
            animales = [a for a in animales if not a.get("asignado_a_paciente_id")]
        if not animales:
            st.info("No hay animales en la base. Cargá algunos desde la app Flutter "
                    "o con `POST /animals`.")
        else:
            payload = []
            for a in animales:
                payload.append({k: a[k] for k in (
                    "id", "tipo_animal", "sexo_animal", "edad_animal", "raza", "peso_kg",
                    "nivel_energia_animal", "nivel_sociabilidad_animal",
                    "nivel_calma_animal", "tolerancia_ruido", "tolerancia_contacto",
                    "tipo_entrenamiento", "experiencia_terapeutica_meses",
                    "certificado_terapia") if k in a})
            try:
                res = predict(paciente_r, payload)
            except Exception as exc:
                st.error(f"Error al predecir: {exc}")
            else:
                # Guardado en sesión: el botón de explicación provoca un rerun y
                # sin esto se perdería el ranking recién calculado.
                st.session_state["rank"] = {
                    "res": res, "paciente": paciente_r, "payload": payload,
                    "nombres": {a["id"]: a.get("nombre", a["id"]) for a in animales},
                }
                st.session_state.pop("explicacion", None)

    datos = st.session_state.get("rank")
    if datos:
        res, nombres = datos["res"], datos["nombres"]
        st.divider()
        st.markdown(f"**{len(res)} animales evaluados**, mejor → peor")
        for i, r in enumerate(res, 1):
            c1, c2, c3 = st.columns([0.5, 3, 1.4])
            c1.markdown(f"### {i}")
            c2.markdown(f"**{nombres.get(r['animal_id'], r['animal_id'])}**")
            c2.progress(min(r["efectividad"] / 100, 1.0))
            c3.metric("", f"{r['efectividad']:.1f}%")
            c3.markdown(badge(r["categoria"]), unsafe_allow_html=True)
        df = pd.DataFrame([{"animal": nombres.get(r["animal_id"], r["animal_id"]),
                            "efectividad": r["efectividad"],
                            "categoria": r["categoria"]} for r in res])
        with st.expander("Ver tabla / exportar"):
            st.dataframe(df, use_container_width=True, hide_index=True)
            st.download_button("Descargar CSV", df.to_csv(index=False),
                               "ranking.csv", "text/csv")

        st.divider()
        # st.write_stream ya deja el texto pintado en la corrida en la que se
        # genera. Sin esta marca, el bloque de más abajo lo volvería a dibujar con
        # st.markdown y la explicación saldría DOS veces en la misma pantalla.
        recien_generado = False
        if st.button("🧠 Más información del resultado", use_container_width=True,
                     help="Genera una orientación para el terapeuta a partir de la "
                          "evidencia calculada sobre el modelo."):
            recien_generado = True
            recibido: dict = {"evidencia": None, "error": None, "aviso": ""}

            def _fragmentos():
                """Deja pasar el texto y va guardando lo demás en `recibido`."""
                for msg in explain_stream(datos["paciente"], datos["payload"],
                                          "el paciente", nombres):
                    tipo = msg.get("tipo")
                    if tipo == "texto":
                        yield msg["delta"]
                    elif tipo == "evidencia":
                        recibido["evidencia"] = msg["datos"]
                    elif tipo == "error":
                        recibido["error"] = msg.get("detalle", "")
                    elif tipo == "fin":
                        recibido["aviso"] = msg.get("aviso", "")

            try:
                # st.write_stream pinta cada fragmento apenas llega y devuelve
                # el texto completo al terminar.
                texto = st.write_stream(_fragmentos())
            except Exception as exc:
                st.error(f"No se pudo generar la explicación: {exc}")
            else:
                st.session_state["explicacion"] = {
                    "explicacion": texto or None,
                    "evidencia": recibido["evidencia"] or {},
                    "detalle_llm": recibido["error"] or "",
                    "aviso": recibido["aviso"],
                }

        exp = st.session_state.get("explicacion")
        if exp:
            if exp.get("explicacion"):
                # Solo se redibuja cuando NO se acaba de transmitir: en la corrida
                # del streaming el texto ya está en pantalla.
                if not recien_generado:
                    st.markdown(exp["explicacion"])
            else:
                st.warning(
                    "**LLM local no disponible** — se muestra la evidencia calculada "
                    "sin redactar. Levantá LM Studio (Developer → Start Server, "
                    "puerto 1234) y volvé a intentar."
                )
                st.caption(f"Detalle: {exp.get('detalle_llm','')[:200]}")

            with st.expander("🔍 Evidencia calculada (lo único que ve el LLM)",
                             expanded=not exp.get("explicacion")):
                ev = exp["evidencia"]
                st.caption(
                    "Cada aporte es cuánto sube o baja la efectividad ese atributo "
                    "respecto de un candidato típico de esta misma lista, medido "
                    "recalculando la predicción con el modelo servido."
                )
                for it in ev["ranking"]:
                    dec = it.get("atributos_decisivos")
                    if not dec:
                        continue
                    st.markdown(f"**#{it['posicion']} {it['nombre']}** — "
                                f"{it['efectividad']}% ({it['categoria']})")
                    st.dataframe(tabla(dec), use_container_width=True,
                                 hide_index=True)
                    if it.get("nota_umbral"):
                        st.caption(it["nota_umbral"])
                if ev.get("primero_vs_segundo"):
                    pv = ev["primero_vs_segundo"]
                    st.markdown("**Primero vs segundo**")
                    st.info(pv.get("lectura_ya_resuelta", ""))
                    difs = pv.get("diferencias_de_atributos")
                    if difs:
                        st.dataframe(tabla(difs), use_container_width=True,
                                     hide_index=True)
                if ev.get("rasgos_del_paciente_que_influyen"):
                    st.markdown("**Rasgos del paciente que mueven el resultado**")
                    st.dataframe(tabla(ev["rasgos_del_paciente_que_influyen"]),
                                 use_container_width=True, hide_index=True)
            st.caption(f"⚠️ {exp['aviso']}")


# --------------------------------------------------------------------------- #
# 3. Sensibilidad: cómo responde el modelo al mover una variable
# --------------------------------------------------------------------------- #
if seccion == SEC_SENS:
    st.subheader("¿Cómo reacciona el modelo si muevo una variable?")
    st.caption("Fija un paciente y un animal, y barre una feature de 1 a 5. "
               "Sirve para ver si el modelo aprendió interacciones o solo efectos promedio.")
    c1, c2 = st.columns(2)
    with c1:
        paciente_s = form_paciente("s_")
    with c2:
        animal_s = form_animal("sa_")

    variable = st.selectbox("Variable del animal a barrer", [
        "nivel_calma_animal", "tolerancia_contacto", "nivel_sociabilidad_animal",
        "tolerancia_ruido", "nivel_energia_animal"])
    st.caption("Reglas de compatibilidad con las que se generó el dataset sintético: "
               "HI alto ↔ calma y tolerancia al contacto · IN alto ↔ sociabilidad · "
               "presentación combinada ↔ tolerancia al ruido.")

    if st.button("Ejecutar barrido", type="primary", use_container_width=True):
        filas = []
        try:
            # Se compara el mismo animal entre perfiles tipicos del test.
            for nombre_perfil in ("Inatento", "Hiperactivo/impulsivo", "Combinado"):
                resp = [int(c) for c in PERFILES_EJEMPLO[nombre_perfil]]
                p = {**paciente_s, "respuestas_adhd": resp}
                animales = [{**animal_s, "id": f"v{v}", variable: v} for v in range(1, 6)]
                res = predict(p, animales)
                orden = {r["animal_id"]: r["efectividad"] for r in res}
                for v in range(1, 6):
                    filas.append({variable: v, nombre_perfil: orden[f"v{v}"]})
        except Exception as exc:
            st.error(f"Error al predecir: {exc}")
        else:
            df = pd.DataFrame(filas).groupby(variable).first()
            st.line_chart(df)
            st.dataframe(df.round(2), use_container_width=True)
            pend = {c: df[c].iloc[-1] - df[c].iloc[0] for c in df.columns}
            st.markdown("**Efecto total de mover la variable de 1 a 5:**")
            for k, v in pend.items():
                st.write(f"- `{k}` → **{v:+.1f}** puntos")
            vals = list(pend.values())
            if max(vals) - min(vals) > 2:
                st.success("Las curvas tienen pendientes distintas: el modelo aprendió "
                           "una **interacción** con el perfil del test, no solo un efecto "
                           "promedio.")
            else:
                st.info("Las curvas son casi paralelas: acá el modelo se comporta de "
                        "forma aditiva (sin interacción apreciable).")


# --------------------------------------------------------------------------- #
# 4. Info
# --------------------------------------------------------------------------- #
if seccion == SEC_INFO:
    st.subheader("Modelo servido")
    c1, c2, c3 = st.columns(3)
    c1.metric("Estado", health.get("status", "?"))
    c2.metric("Modelos cargados", "sí" if health.get("models_loaded") else "no")
    c3.metric("Features", len(cat["features"]))
    st.caption(f"Directorio de modelos: `{health.get('models_dir', '?')}`")

    st.markdown("#### Umbrales de categoría")
    u = cat["umbrales_categoria"]
    st.write(f"- **alta** ≥ {u['alta']}  ·  **media** ≥ {u['media']}  ·  "
             f"**baja** ≥ {u['baja']}  ·  **no_recomendado** < {u['baja']}")
    st.caption("Se aplican sobre la predicción continua. El modelo es un REGRESOR: "
               "las categorías las calcula `interpretar()` en `api/app/ml.py`.")

    st.markdown("#### Las features, en el orden que espera el modelo")
    st.dataframe(pd.DataFrame({"#": range(1, len(cat["features"]) + 1),
                               "feature": cat["features"]}),
                 use_container_width=True, hide_index=True, height=330)

    st.markdown("#### Advertencia")
    st.warning(
        "Los modelos están entrenados sobre un **dataset sintético**. El perfil del "
        "paciente se calcula con el test ADHD-RS (Richarte et al. 2017); las magnitudes "
        "de efecto por dominio vienen del metaanálisis de Yu et al. 2025 (evidencia "
        "pediátrica) y las reglas de compatibilidad (HI↔calma/contacto, IN↔sociabilidad, "
        "combinada↔ruido) son supuestos de diseño. La mezcla de presentaciones también "
        "es un supuesto. Esta consola sirve para explorar "
        "el comportamiento del modelo, no para decidir tratamientos."
    )
