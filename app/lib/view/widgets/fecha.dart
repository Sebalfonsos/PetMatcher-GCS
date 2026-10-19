/// VIEW — Formato de fechas para mostrar cuándo se generó algo guardado.
library;

String _dos(int n) => n.toString().padLeft(2, '0');

/// "03/10/2026 16:20"
String fechaHora(DateTime d) =>
    '${_dos(d.day)}/${_dos(d.month)}/${d.year} ${_dos(d.hour)}:${_dos(d.minute)}';

/// "hace 5 min", "hace 2 h", "hace 3 días" (relativo a ahora).
String hace(DateTime d) {
  final dif = DateTime.now().difference(d);
  if (dif.inMinutes < 1) return 'hace instantes';
  if (dif.inMinutes < 60) return 'hace ${dif.inMinutes} min';
  if (dif.inHours < 24) return 'hace ${dif.inHours} h';
  final dias = dif.inDays;
  return dias == 1 ? 'hace 1 día' : 'hace $dias días';
}
