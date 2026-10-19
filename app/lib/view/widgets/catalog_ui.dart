/// VIEW — Helpers de presentación del catálogo.
///
/// Viven en la capa de vista a propósito: son decisiones de UI (qué emoji, qué
/// texto mostrar), no dominio. El catálogo de dominio está en
/// `model/catalog.dart` y debe coincidir con `api/app/preprocessing.py`.
library;

class CatalogUi {
  /// Emoji por tipo de animal.
  static String emoji(String tipo) => switch (tipo) {
        'perro' => '🐕',
        'gato' => '🐈',
        'conejo' => '🐇',
        'caballo' => '🐴',
        _ => '🐾',
      };

  /// Etiqueta legible para las categorías de efectividad que devuelve la API.
  static String categoriaLabel(String c) => switch (c) {
        'alta' => 'Compatibilidad alta',
        'media' => 'Compatibilidad media',
        'baja' => 'Compatibilidad baja',
        _ => 'No recomendado',
      };
}
