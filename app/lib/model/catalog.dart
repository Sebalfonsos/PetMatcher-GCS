/// MODEL — Catálogo de dominio. DEBE coincidir EXACTAMENTE con las etiquetas que
/// el modelo ML espera (ver api/app/preprocessing.py -> LABEL_MAPPINGS y
/// CATALOGO_ANIMALES). Si cambian allí, cambian aquí.
///
/// Solo dominio: los helpers de presentación (emoji, etiquetas legibles) están
/// en `view/widgets/catalog_ui.dart`.
library;

class Catalog {
  /// Edad mínima del paciente: el ADHD-RS aplica a adultos (17+, DSM-5).
  static const edadMinimaPaciente = 17;
  static const sexoPaciente = ['femenino', 'masculino'];
  static const entornoFamiliar = ['inestable', 'moderadamente estable', 'estable'];
  static const preferenciaAnimal = ['perro', 'gato', 'conejo', 'caballo'];
  static const siNo = ['no', 'si'];
  static const tipoAnimal = ['perro', 'gato', 'conejo', 'caballo'];
  static const sexoAnimal = ['macho', 'hembra'];

  /// Razas y entrenamientos por tipo de animal (idéntico a CATALOGO_ANIMALES del modelo).
  static const razasPorTipo = <String, List<String>>{
    'perro': ['labrador retriever', 'golden retriever', 'border collie', 'beagle', 'mestizo'],
    'gato': ['mestizo', 'siames', 'persa', 'ragdoll'],
    'conejo': ['mini lop', 'holandes', 'cabeza de leon'],
    'caballo': ['criollo', 'cuarto de milla', 'pony', 'andaluz'],
  };

  static const entrenamientosPorTipo = <String, List<String>>{
    'perro': ['apoyo emocional', 'obediencia terapeutica', 'acompanamiento en tdah', 'regulacion conductual'],
    'gato': ['acompanamiento emocional', 'reduccion de ansiedad', 'estimulacion sensorial suave'],
    'conejo': ['estimulacion sensorial', 'acompanamiento tranquilo', 'reduccion de estres'],
    'caballo': ['equinoterapia', 'estimulacion motora', 'regulacion emocional', 'trabajo de confianza'],
  };

  static List<String> razas(String tipo) => razasPorTipo[tipo] ?? const [];
  static List<String> entrenamientos(String tipo) => entrenamientosPorTipo[tipo] ?? const [];
}
