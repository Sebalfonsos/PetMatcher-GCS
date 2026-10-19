/// MODEL — Entidades de dominio de PetMatcher y sus reglas de negocio.
///
/// Los nombres de campo replican las 25 features del modelo ML (plan.md §2.1).
/// Acá viven `Patient`, `Animal`, `MatchResult` y la regla [AnimalesDisponibles].
/// Los DTO de navegación NO van acá: viven junto a la pantalla que los consume.
library;

import 'package:petmatcher/model/adhd.dart';

class Patient {
  final String id;
  final String nombre;
  // Datos básicos (5 features)
  final int edadPaciente;
  final String sexoPaciente;
  final String entornoFamiliar;
  final String preferenciaAnimal;
  final String experienciaPreviaConAnimales;
  // Test ADHD-RS: las 18 respuestas (0-3) son lo único que se guarda. El perfil
  // (IN/HI/presentación…) lo calcula la API. Null = paciente anterior al test.
  final List<int>? respuestasAdhd;
  final PerfilAdhd? perfilAdhd;

  final String? animalAsignadoId;

  const Patient({
    required this.id,
    required this.nombre,
    required this.edadPaciente,
    required this.sexoPaciente,
    required this.entornoFamiliar,
    required this.preferenciaAnimal,
    required this.experienciaPreviaConAnimales,
    this.respuestasAdhd,
    this.perfilAdhd,
    this.animalAsignadoId,
  });

  /// Sin test no hay perfil y el modelo no puede predecir.
  bool get tieneTest => respuestasAdhd != null && respuestasAdhd!.length == 18;

  factory Patient.fromJson(Map<String, dynamic> j) => Patient(
        id: j['id'] as String,
        nombre: j['nombre'] as String? ?? 'Paciente',
        edadPaciente: (j['edad_paciente'] as num).toInt(),
        sexoPaciente: j['sexo_paciente'] as String,
        entornoFamiliar: j['entorno_familiar'] as String,
        preferenciaAnimal: j['preferencia_animal'] as String,
        experienciaPreviaConAnimales: j['experiencia_previa_con_animales'] as String,
        respuestasAdhd:
            (j['respuestas_adhd'] as List?)?.map((e) => (e as num).toInt()).toList(),
        perfilAdhd: j['perfil_adhd'] == null
            ? null
            : PerfilAdhd.fromJson(j['perfil_adhd'] as Map<String, dynamic>),
      );

  Patient copyWith({String? id, PerfilAdhd? perfilAdhd}) => Patient(
        id: id ?? this.id,
        nombre: nombre,
        edadPaciente: edadPaciente,
        sexoPaciente: sexoPaciente,
        entornoFamiliar: entornoFamiliar,
        preferenciaAnimal: preferenciaAnimal,
        experienciaPreviaConAnimales: experienciaPreviaConAnimales,
        respuestasAdhd: respuestasAdhd,
        perfilAdhd: perfilAdhd ?? this.perfilAdhd,
        animalAsignadoId: animalAsignadoId,
      );

  /// Perfil en el formato que espera la API (/predict/batch -> patient).
  Map<String, dynamic> toFeatures() => {
        'edad_paciente': edadPaciente,
        'sexo_paciente': sexoPaciente,
        'entorno_familiar': entornoFamiliar,
        'preferencia_animal': preferenciaAnimal,
        'experiencia_previa_con_animales': experienciaPreviaConAnimales,
        'respuestas_adhd': respuestasAdhd,
      };
}

class Animal {
  final String id;
  final String nombre;
  // 13 features
  final String tipoAnimal;
  final String sexoAnimal;
  final int edadAnimal;
  final String raza;
  final double pesoKg;
  final int nivelEnergiaAnimal;
  final int nivelSociabilidadAnimal;
  final int nivelCalmaAnimal;
  final int toleranciaRuido;
  final int toleranciaContacto;
  final String tipoEntrenamiento;
  final int experienciaTerapeuticaMeses;
  final String certificadoTerapia;

  final String? notas;
  final String? asignadoAPacienteId; // null = disponible

  const Animal({
    required this.id,
    required this.nombre,
    required this.tipoAnimal,
    required this.sexoAnimal,
    required this.edadAnimal,
    required this.raza,
    required this.pesoKg,
    required this.nivelEnergiaAnimal,
    required this.nivelSociabilidadAnimal,
    required this.nivelCalmaAnimal,
    required this.toleranciaRuido,
    required this.toleranciaContacto,
    required this.tipoEntrenamiento,
    required this.experienciaTerapeuticaMeses,
    required this.certificadoTerapia,
    this.notas,
    this.asignadoAPacienteId,
  });

  bool get disponible => asignadoAPacienteId == null;

  factory Animal.fromJson(Map<String, dynamic> j) => Animal(
        id: j['id'] as String,
        nombre: j['nombre'] as String? ?? 'Sin nombre',
        tipoAnimal: j['tipo_animal'] as String,
        sexoAnimal: j['sexo_animal'] as String,
        edadAnimal: (j['edad_animal'] as num).toInt(),
        raza: j['raza'] as String,
        pesoKg: (j['peso_kg'] as num).toDouble(),
        nivelEnergiaAnimal: (j['nivel_energia_animal'] as num).toInt(),
        nivelSociabilidadAnimal: (j['nivel_sociabilidad_animal'] as num).toInt(),
        nivelCalmaAnimal: (j['nivel_calma_animal'] as num).toInt(),
        toleranciaRuido: (j['tolerancia_ruido'] as num).toInt(),
        toleranciaContacto: (j['tolerancia_contacto'] as num).toInt(),
        tipoEntrenamiento: j['tipo_entrenamiento'] as String,
        experienciaTerapeuticaMeses: (j['experiencia_terapeutica_meses'] as num).toInt(),
        certificadoTerapia: j['certificado_terapia'] as String,
        notas: j['notas'] as String?,
        asignadoAPacienteId: j['asignado_a_paciente_id'] as String?,
      );

  /// Cuerpo para crear/actualizar en la API (features + nombre + notas, sin id).
  Map<String, dynamic> toApiBody() => {
        'nombre': nombre,
        'notas': notas,
        ...toFeatures()..remove('id'),
      };

  Map<String, dynamic> toFeatures() => {
        'id': id,
        'tipo_animal': tipoAnimal,
        'sexo_animal': sexoAnimal,
        'edad_animal': edadAnimal,
        'raza': raza,
        'peso_kg': pesoKg,
        'nivel_energia_animal': nivelEnergiaAnimal,
        'nivel_sociabilidad_animal': nivelSociabilidadAnimal,
        'nivel_calma_animal': nivelCalmaAnimal,
        'tolerancia_ruido': toleranciaRuido,
        'tolerancia_contacto': toleranciaContacto,
        'tipo_entrenamiento': tipoEntrenamiento,
        'experiencia_terapeutica_meses': experienciaTerapeuticaMeses,
        'certificado_terapia': certificadoTerapia,
      };

  Animal copyWith({
    String? nombre,
    String? tipoAnimal,
    String? sexoAnimal,
    int? edadAnimal,
    String? raza,
    double? pesoKg,
    int? nivelEnergiaAnimal,
    int? nivelSociabilidadAnimal,
    int? nivelCalmaAnimal,
    int? toleranciaRuido,
    int? toleranciaContacto,
    String? tipoEntrenamiento,
    int? experienciaTerapeuticaMeses,
    String? certificadoTerapia,
    String? notas,
    Object? asignadoAPacienteId = _sentinel,
  }) {
    return Animal(
      id: id,
      nombre: nombre ?? this.nombre,
      tipoAnimal: tipoAnimal ?? this.tipoAnimal,
      sexoAnimal: sexoAnimal ?? this.sexoAnimal,
      edadAnimal: edadAnimal ?? this.edadAnimal,
      raza: raza ?? this.raza,
      pesoKg: pesoKg ?? this.pesoKg,
      nivelEnergiaAnimal: nivelEnergiaAnimal ?? this.nivelEnergiaAnimal,
      nivelSociabilidadAnimal: nivelSociabilidadAnimal ?? this.nivelSociabilidadAnimal,
      nivelCalmaAnimal: nivelCalmaAnimal ?? this.nivelCalmaAnimal,
      toleranciaRuido: toleranciaRuido ?? this.toleranciaRuido,
      toleranciaContacto: toleranciaContacto ?? this.toleranciaContacto,
      tipoEntrenamiento: tipoEntrenamiento ?? this.tipoEntrenamiento,
      experienciaTerapeuticaMeses: experienciaTerapeuticaMeses ?? this.experienciaTerapeuticaMeses,
      certificadoTerapia: certificadoTerapia ?? this.certificadoTerapia,
      notas: notas ?? this.notas,
      asignadoAPacienteId:
          asignadoAPacienteId == _sentinel ? this.asignadoAPacienteId : asignadoAPacienteId as String?,
    );
  }

  static const _sentinel = Object();
}

/// Regla de negocio (plan.md §5): un animal asignado a un paciente queda
/// excluido del ranking de cualquier otro paciente.
///
/// Definida UNA sola vez, acá. No reimplementar `where((a) => a.disponible)`
/// en repositorios ni en providers: si la regla cambia (por ejemplo, excluir
/// también a los que no tienen certificado) debe cambiar en un solo lugar.
extension AnimalesDisponibles on Iterable<Animal> {
  List<Animal> get disponibles => where((a) => a.disponible).toList();
}

/// Resultado de predicción por animal dentro de un ranking guardado.
///
/// Trae una copia de nombre/tipo/raza del animal tal como estaba al generar el
/// ranking: si después se edita o se borra el animal, el ranking guardado se sigue
/// pudiendo mostrar.
class MatchResult {
  final String animalId;
  final double efectividad; // 0-100
  final String categoria; // alta | media | baja | no_recomendado
  final Map<String, double> porModelo;
  final String? nombre;
  final String? tipoAnimal;
  final String? raza;

  const MatchResult({
    required this.animalId,
    required this.efectividad,
    required this.categoria,
    required this.porModelo,
    this.nombre,
    this.tipoAnimal,
    this.raza,
  });

  factory MatchResult.fromJson(Map<String, dynamic> j) => MatchResult(
        animalId: j['animal_id'] as String,
        efectividad: (j['efectividad'] as num).toDouble(),
        categoria: j['categoria'] as String,
        porModelo: ((j['por_modelo'] as Map<String, dynamic>?) ?? const {})
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
        nombre: j['nombre'] as String?,
        tipoAnimal: j['tipo_animal'] as String?,
        raza: j['raza'] as String?,
      );
}

/// Respuesta de "Más información del resultado" guardada junto al ranking.
class ExplicacionGuardada {
  final String texto;
  final Map<String, dynamic> evidencia;
  final String aviso;
  final DateTime generadoEn;

  const ExplicacionGuardada({
    required this.texto,
    required this.evidencia,
    required this.aviso,
    required this.generadoEn,
  });

  factory ExplicacionGuardada.fromJson(Map<String, dynamic> j) => ExplicacionGuardada(
        texto: j['texto'] as String,
        evidencia: (j['evidencia'] as Map).cast<String, dynamic>(),
        aviso: j['aviso'] as String? ?? '',
        generadoEn: DateTime.parse(j['generado_en'] as String).toLocal(),
      );
}

/// Último ranking generado para un paciente, tal como lo guarda la API.
class RankingGuardado {
  /// Null cuando no había animales disponibles (no se guarda un ranking vacío).
  final String? id;
  final String patientId;
  final DateTime? generadoEn;
  final List<MatchResult> resultados;

  /// El ranking guardado ya no refleja la realidad (se editó al paciente, se
  /// asignó un animal, etc.). Se sigue mostrando, con el aviso de [motivos].
  final bool obsoleto;
  final List<String> motivos;

  /// Al pedir uno nuevo salió idéntico al guardado: se conservó el anterior.
  final bool sinCambios;
  final ExplicacionGuardada? explicacion;

  const RankingGuardado({
    required this.id,
    required this.patientId,
    required this.generadoEn,
    required this.resultados,
    required this.obsoleto,
    required this.motivos,
    required this.sinCambios,
    required this.explicacion,
  });

  factory RankingGuardado.fromJson(Map<String, dynamic> j) => RankingGuardado(
        id: j['id'] as String?,
        patientId: j['patient_id'] as String,
        generadoEn: j['generado_en'] == null
            ? null
            : DateTime.parse(j['generado_en'] as String).toLocal(),
        resultados: (j['resultados'] as List)
            .map((e) => MatchResult.fromJson(e as Map<String, dynamic>))
            .toList(),
        obsoleto: j['obsoleto'] as bool? ?? false,
        motivos: ((j['motivos'] as List?) ?? const []).cast<String>(),
        sinCambios: j['sin_cambios'] as bool? ?? false,
        explicacion: j['explicacion'] == null
            ? null
            : ExplicacionGuardada.fromJson(j['explicacion'] as Map<String, dynamic>),
      );
}
