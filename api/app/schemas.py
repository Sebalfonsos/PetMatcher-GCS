"""Esquemas Pydantic para el contrato de la API (ver plan.md seccion 4)."""
from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator


class PatientProfile(BaseModel):
    """Perfil del paciente = datos basicos (5) + las 18 respuestas del test ADHD-RS.

    Las 7 features del test (IN, HI, total, n de sintomas, presentacion, cribado) NO se
    reciben: la API las deriva de `respuestas_adhd` (api/app/adhd_rs.py), de modo que
    no puede haber un perfil incoherente con las respuestas. Los campos categoricos
    aceptan las etiquetas del modelo o el indice numerico ya codificado."""

    edad_paciente: int = Field(..., ge=17, le=99)  # ADHD-RS: adultos (17+, DSM-5)
    sexo_paciente: str = "femenino"  # masculino | femenino
    entorno_familiar: str = "estable"  # inestable | moderadamente estable | estable
    preferencia_animal: str = "perro"  # perro | gato | conejo | caballo
    experiencia_previa_con_animales: str = "no"  # no | si
    respuestas_adhd: list[int] = Field(..., min_length=18, max_length=18)

    @field_validator("respuestas_adhd")
    @classmethod
    def _valores_0_3(cls, v):
        if any(x not in (0, 1, 2, 3) for x in v):
            raise ValueError("Cada respuesta del ADHD-RS debe estar entre 0 y 3")
        return v


class PerfilADHD(BaseModel):
    """Resultado de puntuar el test (ver docs/guia-aplicacion-medicion-perfil-ADHD-RS.md)."""

    IN: int
    HI: int
    TOT: int
    n_sintomas_IN: int
    n_sintomas_HI: int
    presentacion: str
    corte_usado: int
    cribado_positivo: int
    tot_ge_24: int
    tot_ge_21: int


class ScoreRequest(BaseModel):
    respuestas_adhd: list[int] = Field(..., min_length=18, max_length=18)

    @field_validator("respuestas_adhd")
    @classmethod
    def _valores_0_3(cls, v):
        if any(x not in (0, 1, 2, 3) for x in v):
            raise ValueError("Cada respuesta del ADHD-RS debe estar entre 0 y 3")
        return v


class AnimalProfile(BaseModel):
    """Perfil del animal: 13 features + id para el ranking."""

    id: str
    tipo_animal: str = "perro"  # perro | gato | conejo | caballo
    sexo_animal: str = "macho"  # macho | hembra
    edad_animal: int = Field(4, ge=0, le=40)
    raza: str = "labrador retriever"
    peso_kg: float = Field(20.0, gt=0)
    nivel_energia_animal: int = Field(3, ge=1, le=5)
    nivel_sociabilidad_animal: int = Field(3, ge=1, le=5)
    nivel_calma_animal: int = Field(3, ge=1, le=5)
    tolerancia_ruido: int = Field(3, ge=1, le=5)
    tolerancia_contacto: int = Field(3, ge=1, le=5)
    tipo_entrenamiento: str = "apoyo emocional"
    experiencia_terapeutica_meses: int = Field(12, ge=0, le=240)
    certificado_terapia: str = "no"  # no | si


class BatchPredictRequest(BaseModel):
    patient: PatientProfile
    animals: list[AnimalProfile]


# ---------- Persistencia: Animales ----------

class AnimalBase(BaseModel):
    nombre: str = "Sin nombre"
    tipo_animal: str = "perro"
    sexo_animal: str = "macho"
    edad_animal: int = Field(3, ge=0, le=40)
    raza: str = "mestizo"
    peso_kg: float = Field(10.0, gt=0)
    nivel_energia_animal: int = Field(3, ge=1, le=5)
    nivel_sociabilidad_animal: int = Field(3, ge=1, le=5)
    nivel_calma_animal: int = Field(3, ge=1, le=5)
    tolerancia_ruido: int = Field(3, ge=1, le=5)
    tolerancia_contacto: int = Field(3, ge=1, le=5)
    tipo_entrenamiento: str = "apoyo emocional"
    experiencia_terapeutica_meses: int = Field(12, ge=0, le=240)
    certificado_terapia: str = "no"
    notas: Optional[str] = None


class AnimalIn(AnimalBase):
    """Payload para crear/actualizar un animal."""


class AnimalOut(AnimalBase):
    id: str
    asignado_a_paciente_id: Optional[str] = None

    model_config = {"from_attributes": True}


class AssignRequest(BaseModel):
    patient_id: str


# ---------- Persistencia: Pacientes ----------

class PatientIn(PatientProfile):
    nombre: str = "Paciente"


class PatientOut(BaseModel):
    """Sin restricciones de rango: debe poder devolver pacientes legados (<17 anios)."""

    id: str
    nombre: str
    edad_paciente: int
    sexo_paciente: str
    entorno_familiar: str
    preferencia_animal: str
    experiencia_previa_con_animales: str
    # Pacientes anteriores al test ADHD-RS no tienen respuestas: deben completarlo.
    respuestas_adhd: Optional[list[int]] = None
    perfil_adhd: Optional[PerfilADHD] = None


class PredictResult(BaseModel):
    animal_id: Optional[str]
    efectividad: float
    categoria: str  # alta | media | baja | no_recomendado
    por_modelo: dict[str, float]


class ExplainRequest(BaseModel):
    patient: PatientProfile
    animals: list[AnimalProfile]
    nombre_paciente: str = "el paciente"
    nombres_animales: dict[str, str] = {}  # animal_id -> nombre, para el texto


class ExplainResponse(BaseModel):
    explicacion: Optional[str] = None   # texto del LLM; None si no estaba disponible
    evidencia: dict                     # hechos calculados (siempre presentes)
    llm_disponible: bool
    detalle_llm: str = ""               # modelo usado, o el error
    aviso: str


class HealthResponse(BaseModel):
    status: str
    models_loaded: bool
    models_dir: str
    modelos: list[str] = []          # modelos efectivamente cargados
    modelo_prediccion: str = "promedio"  # cual define la efectividad final


# ---------- Persistencia: Rankings y explicaciones ----------

class ResultadoRanking(BaseModel):
    animal_id: str
    nombre: str
    tipo_animal: str
    raza: str
    efectividad: float
    categoria: str
    por_modelo: dict[str, float] = {}


class ExplicacionOut(BaseModel):
    texto: str
    evidencia: dict
    aviso: str = ""
    generado_en: datetime


class RankingOut(BaseModel):
    id: Optional[str] = None            # None si no habia animales disponibles (no se guarda)
    patient_id: str
    generado_en: Optional[datetime] = None
    resultados: list[ResultadoRanking] = []
    # El ranking guardado ya no refleja la realidad (paciente o animales cambiaron).
    obsoleto: bool = False
    motivos: list[str] = []
    # Al pedir uno nuevo salio identico al guardado: se conserva (y su explicacion).
    sin_cambios: bool = False
    explicacion: Optional[ExplicacionOut] = None
