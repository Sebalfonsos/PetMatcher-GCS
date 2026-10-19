import 'package:dio/dio.dart';

/// Mensaje legible de un error de la API: el `detail` de FastAPI si lo hay.
String apiError(Object e, {String fallback = 'No se pudo completar la acción'}) {
  if (e is DioException) {
    final d = e.response?.data;
    if (d is Map && d['detail'] is String) return d['detail'] as String;
    if (e.response == null) return 'No se pudo conectar con la API. ¿Está activa?';
  }
  return fallback;
}
