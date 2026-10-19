/// MODEL — Test ADHD-RS: cuestionario y perfil resultante.
///
/// El texto de los 18 ítems y la puntuación viven en la API
/// (`api/app/adhd_rs.py`, expuestos en `/adhd-rs/*`). Acá solo hay entidades:
/// la app NO reimplementa la puntuación para no divergir del modelo ML.
library;

class AdhdOpcion {
  final int valor;
  final String etiqueta;
  const AdhdOpcion(this.valor, this.etiqueta);

  factory AdhdOpcion.fromJson(Map<String, dynamic> j) =>
      AdhdOpcion((j['valor'] as num).toInt(), j['etiqueta'] as String);
}

class AdhdItem {
  final int n; // 1..18
  final String texto;
  final String subescala; // IN | HI
  const AdhdItem(this.n, this.texto, this.subescala);

  factory AdhdItem.fromJson(Map<String, dynamic> j) =>
      AdhdItem((j['n'] as num).toInt(), j['texto'] as String, j['subescala'] as String);
}

class AdhdCuestionario {
  final String instruccion;
  final String advertencia;
  final List<AdhdOpcion> opciones;
  final List<AdhdItem> items;
  const AdhdCuestionario({
    required this.instruccion,
    required this.advertencia,
    required this.opciones,
    required this.items,
  });

  factory AdhdCuestionario.fromJson(Map<String, dynamic> j) => AdhdCuestionario(
        instruccion: j['instruccion'] as String,
        advertencia: j['advertencia'] as String,
        opciones: (j['opciones'] as List)
            .map((e) => AdhdOpcion.fromJson(e as Map<String, dynamic>))
            .toList(),
        items: (j['items'] as List)
            .map((e) => AdhdItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Perfil calculado por la API a partir de las 18 respuestas.
class PerfilAdhd {
  final int inatencion; // 0-27
  final int hiperactividad; // 0-27
  final int total; // 0-54
  final int sintomasIn; // 0-9
  final int sintomasHi; // 0-9
  final String presentacion; // combinada | inatenta | hiperactiva_impulsiva | sin_presentacion
  final int corteUsado;
  final bool cribadoPositivo;

  const PerfilAdhd({
    required this.inatencion,
    required this.hiperactividad,
    required this.total,
    required this.sintomasIn,
    required this.sintomasHi,
    required this.presentacion,
    required this.corteUsado,
    required this.cribadoPositivo,
  });

  factory PerfilAdhd.fromJson(Map<String, dynamic> j) => PerfilAdhd(
        inatencion: (j['IN'] as num).toInt(),
        hiperactividad: (j['HI'] as num).toInt(),
        total: (j['TOT'] as num).toInt(),
        sintomasIn: (j['n_sintomas_IN'] as num).toInt(),
        sintomasHi: (j['n_sintomas_HI'] as num).toInt(),
        presentacion: j['presentacion'] as String,
        corteUsado: (j['corte_usado'] as num).toInt(),
        cribadoPositivo: (j['cribado_positivo'] as num).toInt() == 1,
      );

  String get presentacionLabel => switch (presentacion) {
        'combinada' => 'Combinada',
        'inatenta' => 'Predominantemente inatenta',
        'hiperactiva_impulsiva' => 'Predominantemente hiperactiva/impulsiva',
        _ => 'Sin presentación',
      };
}
