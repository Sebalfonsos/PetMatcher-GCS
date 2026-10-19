FROM python:3.11-slim

WORKDIR /code

# Dependencias del sistema mínimas para numpy/scikit-learn ya vienen en slim + wheels.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Los .pkl del modelo se montan como volumen en /models (ver docker-compose.yml).
ENV PETMATCHER_MODELS_DIR=/models

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
