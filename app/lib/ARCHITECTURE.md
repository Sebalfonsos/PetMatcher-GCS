# Arquitectura de la app Flutter — MVVM

La estructura de carpetas **es** la arquitectura: cada carpeta de primer nivel es una
capa de MVVM. Si un archivo no sabés dónde va, la tabla de abajo lo decide.

```
lib/
├── main.dart                    punto de entrada, arma el ProviderScope
│
├── model/                       ← MODEL: datos, entidades y reglas de negocio
│   ├── models.dart              Patient, Animal, MatchResult + regla AnimalesDisponibles
│   ├── api_client.dart          PetMatcherApi (dio → FastAPI) + apiProvider
│   └── catalog.dart             catálogo de dominio (atado a api/app/preprocessing.py)
│
├── viewmodel/                   ← VIEWMODEL: estado y lógica de presentación
│   ├── animal_viewmodel.dart    AnimalViewModel + animalViewModelProvider
│   ├── patients_viewmodel.dart  PatientsViewModel + patientsProvider
│   ├── ranking_viewmodel.dart   rankingProvider (family sobre Patient)
│   └── theme_viewmodel.dart     themeModeProvider
│
└── view/                        ← VIEW: todo lo que se dibuja
    ├── router.dart              go_router: mapea rutas a pantallas
    ├── theme/theme.dart         AppTheme, PetColors, PetGradients
    ├── widgets/
    │   ├── widgets.dart         PercentRing, LevelSlider, LabeledDropdown…
    │   └── catalog_ui.dart      emoji y etiquetas legibles (presentación)
    └── screens/                 las 8 pantallas, una carpeta por feature
        ├── onboarding/  patient_form/  patients/  animals/
        └── ranking/     animal_detail/
```

| capa | líneas | archivos |
|---|---|---|
| model | 386 | 3 |
| viewmodel | 110 | 4 |
| view | 2.219 | 12 |

## Dónde va cada cosa

| si el archivo… | va en |
|---|---|
| define una entidad o una regla de negocio | `model/` |
| habla con la API o con almacenamiento | `model/` |
| expone estado a la UI (Riverpod Notifier/Provider) | `viewmodel/` |
| orquesta llamadas al model para una pantalla | `viewmodel/` |
| construye Widgets | `view/` |
| decide colores, textos, iconos o navegación | `view/` |

## Regla de dependencias

```
view  ──►  viewmodel  ──►  model
  └────────────────────────►┘   (solo para leer entidades: Patient, Animal…)
```

- **Model no importa nada de arriba.** No conoce ni la vista ni los viewmodels.
- **ViewModel no importa View.** No sabe qué widget lo consume.
- **View no importa `api_client`.** Si una pantalla necesita datos, pasa por un
  ViewModel. Que una vista llame a la API directo es la fuga más común.

Que la View importe `model/models.dart` **sí es correcto**: necesita los tipos
`Patient` y `Animal` para mostrarlos. Lo que no puede es acceder a la fuente de datos.

Verificación rápida (debe devolver vacío en los tres casos):

```bash
grep -rn "package:petmatcher/view" lib/model/        # model → view
grep -rn "package:petmatcher/viewmodel" lib/model/   # model → viewmodel
grep -rn "api_client" lib/view/                      # view → fuente de datos
```

## Nota sobre Riverpod como ViewModel

Los `AsyncNotifier` de Riverpod cumplen el rol de ViewModel: mantienen el estado,
exponen operaciones a la vista y no conocen los widgets. `rankingProvider` y
`themeModeProvider` son ViewModels sin clase — providers que derivan estado. Están
en `viewmodel/` porque cumplen la misma función.

`rankingProvider` es `family` sobre `Patient` a propósito: no hay estado global de
"paciente activo", el paciente viaja por navegación (plan.md §6.1).
