FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# La consola habla con la API por la red interna de compose. Se sobreescribe
# en docker-compose.yml; este default sirve para correrla suelta.
ENV PETMATCHER_API_URL=http://localhost:8000

EXPOSE 8501

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request;urllib.request.urlopen('http://localhost:8501/_stcore/health')"

# fileWatcherType=poll: en Windows los eventos inotify NO atraviesan los bind
# mounts de Docker Desktop, así que el watcher por defecto nunca se entera de un
# cambio y Streamlit sigue ejecutando el bytecode viejo aunque el archivo en el
# contenedor ya esté actualizado. El sondeo sí funciona.
CMD ["streamlit", "run", "app.py", \
     "--server.port=8501", \
     "--server.address=0.0.0.0", \
     "--server.headless=true", \
     "--server.fileWatcherType=poll", \
     "--server.runOnSave=true", \
     "--browser.gatherUsageStats=false"]
