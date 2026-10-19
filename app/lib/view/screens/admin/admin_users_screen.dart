import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:petmatcher/model/auth_models.dart';
import 'package:petmatcher/view/theme/theme.dart';
import 'package:petmatcher/view/widgets/api_error.dart';
import 'package:petmatcher/view/widgets/fecha.dart';
import 'package:petmatcher/viewmodel/admin_viewmodel.dart';
import 'package:petmatcher/viewmodel/auth_viewmodel.dart';

/// Administración de usuarios (solo rol admin; el router y la API lo exigen).
class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersProvider);
    final yo = ref.watch(authProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirForm(context, ref),
        backgroundColor: PetColors.coral,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Nuevo usuario'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(usersProvider.notifier).refreshList(),
        child: users.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            const SizedBox(height: 120),
            Center(child: Text(apiError(e), textAlign: TextAlign.center)),
          ]),
          data: (list) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final u = list[i];
              final esYo = u.id == yo?.id;
              return Card(
                child: ListTile(
                  onTap: () => _abrirForm(context, ref, existente: u),
                  leading: CircleAvatar(
                    backgroundColor:
                        (u.esAdmin ? PetColors.violet : PetColors.teal).withValues(alpha: 0.15),
                    child: Icon(
                        u.esAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                        color: u.esAdmin ? PetColors.violet : PetColors.teal),
                  ),
                  title: Text('${u.etiqueta}${esYo ? '  (tú)' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    '@${u.username} · ${u.esAdmin ? 'Administrador' : 'Terapeuta'}'
                    '${u.activo ? '' : ' · DESACTIVADO'}\n'
                    '${u.ultimoLogin == null ? 'Nunca ingresó' : 'Último ingreso: ${fechaHora(u.ultimoLogin!)}'}',
                  ),
                  isThreeLine: true,
                  trailing: esYo
                      ? null
                      : IconButton(
                          tooltip: 'Eliminar',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _eliminar(context, ref, u),
                        ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _eliminar(BuildContext context, WidgetRef ref, AppUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text(
            '¿Eliminar a @${u.username}? Su historial en el registro de eventos se conserva. '
            'Si solo quieres impedir que ingrese, mejor desactívalo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(usersProvider.notifier).remove(u.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  Future<void> _abrirForm(BuildContext context, WidgetRef ref, {AppUser? existente}) {
    return showDialog<void>(
      context: context,
      builder: (_) => _UserFormDialog(ref: ref, existente: existente),
    );
  }
}

class _UserFormDialog extends StatefulWidget {
  final WidgetRef ref;
  final AppUser? existente;
  const _UserFormDialog({required this.ref, this.existente});

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  late final _username = TextEditingController(text: widget.existente?.username ?? '');
  late final _nombre = TextEditingController(text: widget.existente?.nombre ?? '');
  final _password = TextEditingController();
  late String _rol = widget.existente?.rol ?? 'terapeuta';
  late bool _activo = widget.existente?.activo ?? true;
  String? _error;
  bool _enviando = false;

  bool get _editando => widget.existente != null;

  @override
  void dispose() {
    _username.dispose();
    _nombre.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final pass = _password.text;
    if (!_editando && _username.text.trim().length < 3) {
      setState(() => _error = 'El usuario debe tener al menos 3 caracteres');
      return;
    }
    if ((!_editando || pass.isNotEmpty) && pass.length < 10) {
      setState(() => _error = 'La contraseña debe tener al menos 10 caracteres');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    final vm = widget.ref.read(usersProvider.notifier);
    try {
      if (_editando) {
        final u = widget.existente!;
        await vm.edit(
          u.id,
          nombre: _nombre.text.trim(),
          rol: _rol,
          activo: _activo,
          password: pass.isEmpty ? null : pass,
        );
      } else {
        await vm.create(
            username: _username.text.trim().toLowerCase(),
            nombre: _nombre.text.trim(),
            password: pass,
            rol: _rol);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editando ? 'Editar @${widget.existente!.username}' : 'Nuevo usuario'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!_editando) ...[
              TextField(
                  controller: _username,
                  decoration: const InputDecoration(
                      labelText: 'Usuario', helperText: 'Letras, números, . _ -')),
              const SizedBox(height: 8),
            ],
            TextField(
                controller: _nombre,
                decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _editando ? 'Nueva contraseña (opcional)' : 'Contraseña',
                helperText: _editando
                    ? 'Déjala vacía para no cambiarla. Al restablecerla se cierran sus sesiones.'
                    : 'Mínimo 10 caracteres',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _rol,
              decoration: const InputDecoration(labelText: 'Rol'),
              items: const [
                DropdownMenuItem(value: 'terapeuta', child: Text('Terapeuta')),
                DropdownMenuItem(value: 'admin', child: Text('Administrador')),
              ],
              onChanged: (v) => setState(() => _rol = v ?? _rol),
            ),
            if (_editando)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activo'),
                subtitle: const Text('Si se desactiva, no puede ingresar y su sesión se cierra'),
                value: _activo,
                onChanged: (v) => setState(() => _activo = v),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _enviando ? null : _guardar, child: const Text('Guardar')),
      ],
    );
  }
}
