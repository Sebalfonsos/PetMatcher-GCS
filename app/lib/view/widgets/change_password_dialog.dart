import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:petmatcher/model/api_client.dart';

/// Diálogo para que cualquier usuario cambie su propia contraseña.
Future<void> showChangePasswordDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ChangePasswordDialog(ref: ref),
  );
}

class _ChangePasswordDialog extends StatefulWidget {
  final WidgetRef ref;
  const _ChangePasswordDialog({required this.ref});

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _actual = TextEditingController();
  final _nueva = TextEditingController();
  final _repite = TextEditingController();
  String? _error;
  bool _enviando = false;

  @override
  void dispose() {
    _actual.dispose();
    _nueva.dispose();
    _repite.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_nueva.text.length < 10) {
      setState(() => _error = 'La nueva contraseña debe tener al menos 10 caracteres');
      return;
    }
    if (_nueva.text != _repite.text) {
      setState(() => _error = 'Las contraseñas nuevas no coinciden');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await widget.ref.read(apiProvider).changePassword(_actual.text, _nueva.text);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(
          content: Text('Contraseña actualizada. Las demás sesiones se cerraron.')));
    } on DioException catch (e) {
      final d = e.response?.data;
      setState(() => _error = d is Map && d['detail'] is String
          ? d['detail'] as String
          : 'No se pudo cambiar la contraseña');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar contraseña'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _actual,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña actual')),
          const SizedBox(height: 8),
          TextField(
              controller: _nueva,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Nueva contraseña', helperText: 'Mínimo 10 caracteres')),
          const SizedBox(height: 8),
          TextField(
              controller: _repite,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repite la nueva')),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _enviando ? null : _guardar, child: const Text('Guardar')),
      ],
    );
  }
}
