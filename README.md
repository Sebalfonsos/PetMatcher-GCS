# PetMatcher

App que empareja pacientes de terapia asistida con animales (TAA) con los animales de una base de
datos. Un modelo de ML predice un índice de efectividad (0–100) por cada par paciente↔animal y la
app muestra el ranking. El perfil del paciente sale del test **ADHD-RS** (18 ítems, 0–3).


## Requisitos

- Docker y Docker Compose
- Flutter SDK (`^3.12.2`) para la app
- *(Opcional)* [LM Studio](https://lmstudio.ai) en `http://localhost:4321` para las explicaciones en lenguaje natural. Sin él, la API devuelve igual la evidencia calculada.

## Ejecutar

### 1. Backend (API + base de datos + consola)

```bash
cp .env.example .env
# Edita .env: define PETMATCHER_JWT_SECRET y PETMATCHER_ADMIN_PASSWORD
docker compose up --build
```

Genera el secreto JWT con:

```bash
python -c "import secrets;print(secrets.token_urlsafe(48))"
```

- API: http://localhost:8000
- Consola Streamlit: http://localhost:8501
- Al primer arranque se crea el administrador con `PETMATCHER_ADMIN_USER` / `PETMATCHER_ADMIN_PASSWORD`
  (contraseña mínima de 10 caracteres). Si no defines clave, se genera una y se imprime una vez en los logs de `api`.

### 2. App Flutter

```bash
cd app
flutter pub get
flutter run -d chrome        # o: -d windows
```

La app apunta a `http://localhost:8000` (web/escritorio) o `http://10.0.2.2:8000` (emulador Android).
Para otra dirección:

```bash
flutter run --dart-define=API_BASE_URL=http://TU_HOST:8000
```
