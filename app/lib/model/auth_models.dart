/// MODEL — Usuarios de la app y eventos del log de auditoría.
library;

class AppUser {
  final String id;
  final String username;
  final String nombre;
  final String rol; // 'admin' | 'terapeuta'
  final bool activo;
  final DateTime? creadoEn;
  final DateTime? ultimoLogin;

  const AppUser({
    required this.id,
    required this.username,
    required this.nombre,
    required this.rol,
    required this.activo,
    this.creadoEn,
    this.ultimoLogin,
  });

  bool get esAdmin => rol == 'admin';

  /// Nombre para mostrar: el nombre real si existe, si no el usuario.
  String get etiqueta => nombre.trim().isEmpty ? username : nombre;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        username: j['username'] as String,
        nombre: (j['nombre'] as String?) ?? '',
        rol: j['rol'] as String,
        activo: j['activo'] as bool,
        creadoEn: _fecha(j['creado_en']),
        ultimoLogin: _fecha(j['ultimo_login']),
      );
}

class AuditEvent {
  final int id;
  final DateTime ts;
  final String username;
  final String accion;
  final String? recursoTipo;
  final String? recursoId;
  final bool exito;
  final String? ip;
  final Map<String, dynamic>? detalle;

  const AuditEvent({
    required this.id,
    required this.ts,
    required this.username,
    required this.accion,
    this.recursoTipo,
    this.recursoId,
    required this.exito,
    this.ip,
    this.detalle,
  });

  factory AuditEvent.fromJson(Map<String, dynamic> j) => AuditEvent(
        id: j['id'] as int,
        ts: _fecha(j['ts'])!,
        username: (j['username'] as String?) ?? '',
        accion: j['accion'] as String,
        recursoTipo: j['recurso_tipo'] as String?,
        recursoId: j['recurso_id'] as String?,
        exito: j['exito'] as bool,
        ip: j['ip'] as String?,
        detalle: (j['detalle'] as Map?)?.cast<String, dynamic>(),
      );
}

class AuditPage {
  final int total;
  final List<AuditEvent> items;
  const AuditPage(this.total, this.items);

  factory AuditPage.fromJson(Map<String, dynamic> j) => AuditPage(
        j['total'] as int,
        (j['items'] as List)
            .map((e) => AuditEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Filtros del log. `accion` es un prefijo ("paciente.", "auth.login").
class AuditFilter {
  final String? username;
  final String? accion;
  final bool? exito;
  const AuditFilter({this.username, this.accion, this.exito});

  @override
  bool operator ==(Object other) =>
      other is AuditFilter && other.username == username && other.accion == accion && other.exito == exito;

  @override
  int get hashCode => Object.hash(username, accion, exito);
}

/// La API manda UTC; se muestra en hora local.
DateTime? _fecha(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();
