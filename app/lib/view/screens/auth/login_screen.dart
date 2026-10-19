import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:petmatcher/view/theme/theme.dart';
import 'package:petmatcher/view/widgets/widgets.dart';
import 'package:petmatcher/viewmodel/auth_viewmodel.dart';

/// Inicio de sesión. El router redirige al hub apenas hay usuario autenticado.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _ver = false;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (_enviando || _user.text.trim().isEmpty || _pass.text.isEmpty) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).login(_user.text, _pass.text);
    } catch (e) {
      if (mounted) setState(() => _error = e is String ? e : 'No se pudo iniciar sesión');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            GradientHeader(
              gradient: PetGradients.brand,
              height: 240,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('🐾', style: TextStyle(fontSize: 52))
                        .animate()
                        .scale(duration: 500.ms, curve: Curves.easeOutBack),
                    const SizedBox(height: 8),
                    Text('PetMatcher',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Iniciar sesión',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _user,
                          autofillHints: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                              labelText: 'Usuario', prefixIcon: Icon(Icons.person_rounded)),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pass,
                          obscureText: !_ver,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _entrar(),
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_rounded),
                            suffixIcon: IconButton(
                              tooltip: _ver ? 'Ocultar' : 'Mostrar',
                              icon: Icon(_ver
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded),
                              onPressed: () => setState(() => _ver = !_ver),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, style: const TextStyle(color: PetColors.coralDark)),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _enviando ? null : _entrar,
                          style: FilledButton.styleFrom(
                              backgroundColor: PetColors.coral,
                              padding: const EdgeInsets.symmetric(vertical: 16)),
                          child: _enviando
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('Entrar'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
