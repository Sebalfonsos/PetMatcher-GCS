import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:petmatcher/model/auth_models.dart';
import 'package:petmatcher/view/theme/theme.dart';
import 'package:petmatcher/view/widgets/api_error.dart';
import 'package:petmatcher/view/widgets/fecha.dart';
import 'package:petmatcher/viewmodel/admin_viewmodel.dart';

/// Registro de eventos por usuario (solo rol admin). Es de solo lectura: ni la app ni
/// la API permiten editar o borrar eventos.
class AdminAuditScreen extends ConsumerStatefulWidget {
  const AdminAuditScreen({super.key});

  @override
  ConsumerState<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

const _categorias = <(String?, String)>[
  (null, 'Todo'),
  ('auth.', 'Sesiones'),
  ('paciente.', 'Pacientes'),
  ('animal.', 'Animales'),
  ('ranking.', 'Rankings'),
  ('explicacion.', 'Explicaciones'),
  ('usuario.', 'Usuarios'),
];

class _AdminAuditScreenState extends ConsumerState<AdminAuditScreen> {
  String? _username;
  String? _categoria;
  bool _soloFallos = false;

  AuditFilter get _filtro =>
      AuditFilter(username: _username, accion: _categoria, exito: _soloFallos ? false : null);

  @override
  Widget build(BuildContext context) {
    final filtro = _filtro;
    final audit = ref.watch(auditProvider(filtro));
    final users = ref.watch(usersProvider).value ?? const <AppUser>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de eventos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(auditProvider(filtro).notifier).reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _username,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Usuario', prefixIcon: Icon(Icons.person_search_rounded)),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    for (final u in users)
                      DropdownMenuItem(value: u.username, child: Text('@${u.username}')),
                  ],
                  onChanged: (v) => setState(() => _username = v),
                ),
              ),
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('Solo fallidos'),
                selected: _soloFallos,
                onSelected: (v) => setState(() => _soloFallos = v),
              ),
            ]),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final (prefijo, etiqueta) in _categorias)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(etiqueta),
                      selected: _categoria == prefijo,
                      onSelected: (_) => setState(() => _categoria = prefijo),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(auditProvider(filtro).notifier).reload(),
              child: audit.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(children: [
                  const SizedBox(height: 100),
                  Center(child: Text(apiError(e), textAlign: TextAlign.center)),
                ]),
                data: (s) {
                  if (s.items.isEmpty) {
                    return ListView(children: [
                      const SizedBox(height: 100),
                      Center(
                          child: Text('No hay eventos con estos filtros.',
                              style: TextStyle(color: PetColors.inkSoft))),
                    ]);
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: s.items.length + 1,
                    itemBuilder: (_, i) {
                      if (i < s.items.length) return _EventTile(s.items[i]);
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(children: [
                          Text('${s.items.length} de ${s.total} eventos',
                              style: TextStyle(color: PetColors.inkSoft, fontSize: 12)),
                          if (s.hayMas)
                            TextButton(
                              onPressed: () =>
                                  ref.read(auditProvider(filtro).notifier).loadMore(),
                              child: const Text('Cargar más'),
                            ),
                        ]),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _etiquetaAccion(String a) => switch (a) {
      'auth.login' => 'Inició sesión',
      'auth.login_fallido' => 'Intento de ingreso fallido',
      'auth.bloqueado' => 'Ingreso bloqueado por intentos',
      'auth.logout' => 'Cerró sesión',
      'auth.cambiar_password' => 'Cambió su contraseña',
      'paciente.crear' => 'Creó un paciente',
      'paciente.ver' => 'Consultó un paciente',
      'paciente.editar' => 'Editó un paciente',
      'paciente.eliminar' => 'Eliminó un paciente',
      'animal.crear' => 'Creó un animal',
      'animal.editar' => 'Editó un animal',
      'animal.eliminar' => 'Eliminó un animal',
      'animal.asignar' => 'Asignó un animal',
      'animal.liberar' => 'Liberó un animal',
      'ranking.ver' => 'Consultó un ranking',
      'ranking.generar' => 'Generó un ranking',
      'explicacion.generar' => 'Generó una explicación',
      'usuario.crear' => 'Creó un usuario',
      'usuario.editar' => 'Editó un usuario',
      'usuario.eliminar' => 'Eliminó un usuario',
      _ => a,
    };

IconData _icono(String a) {
  if (a.startsWith('auth.')) return Icons.login_rounded;
  if (a.startsWith('paciente.')) return Icons.person_rounded;
  if (a.startsWith('animal.')) return Icons.pets_rounded;
  if (a.startsWith('ranking.') || a.startsWith('explicacion.')) return Icons.leaderboard_rounded;
  return Icons.manage_accounts_rounded;
}

class _EventTile extends StatelessWidget {
  final AuditEvent e;
  const _EventTile(this.e);

  String? get _detalle {
    final d = e.detalle;
    if (d == null || d.isEmpty) return null;
    return d.entries.map((x) => '${x.key}: ${x.value}').join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final color = e.exito ? PetColors.teal : PetColors.coralDark;
    final detalle = _detalle;
    final recurso = e.recursoId == null
        ? null
        : '${e.recursoTipo ?? 'recurso'} ${e.recursoId!.length > 8 ? e.recursoId!.substring(0, 8) : e.recursoId}';
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(_icono(e.accion), color: color, size: 20),
        ),
        title: Text(_etiquetaAccion(e.accion),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text([
          '${e.username.isEmpty ? '(sin usuario)' : '@${e.username}'} · ${fechaHora(e.ts)}',
          ?recurso,
          if (e.ip != null) 'IP ${e.ip}',
          ?detalle,
        ].join('\n')),
        isThreeLine: true,
        trailing: e.exito ? null : const Icon(Icons.error_outline_rounded, color: PetColors.coralDark),
      ),
    );
  }
}
