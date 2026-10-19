import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:petmatcher/viewmodel/auth_viewmodel.dart';
import 'package:petmatcher/viewmodel/theme_viewmodel.dart';
import 'package:petmatcher/view/widgets/change_password_dialog.dart';
import 'package:petmatcher/view/theme/theme.dart';
import 'package:petmatcher/view/widgets/widgets.dart';

/// Pantalla de inicio / hub de navegación.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final user = ref.watch(authProvider).value;
    final isDark = mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GradientHeader(
              gradient: PetGradients.brand,
              height: 260,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (user != null)
                          Flexible(
                            child: Text('${user.etiqueta} · ${user.esAdmin ? 'Admin' : 'Terapeuta'}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.w700)),
                          ),
                        const Spacer(),
                        IconButton(
                          tooltip: isDark ? 'Modo claro' : 'Modo oscuro',
                          onPressed: () => ref.read(themeModeProvider.notifier).state =
                              isDark ? ThemeMode.light : ThemeMode.dark,
                          icon: Icon(
                            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cambiar contraseña',
                          onPressed: () => showChangePasswordDialog(context, ref),
                          icon: const Icon(Icons.key_rounded, color: Colors.white),
                        ),
                        IconButton(
                          tooltip: 'Cerrar sesión',
                          onPressed: () => ref.read(authProvider.notifier).logout(),
                          icon: const Icon(Icons.logout_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                    const Text('🐾', style: TextStyle(fontSize: 52))
                        .animate()
                        .scale(duration: 500.ms, curve: Curves.easeOutBack),
                    const SizedBox(height: 8),
                    Text('PetMatcher',
                            style: Theme.of(context)
                                .textTheme
                                .displaySmall
                                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w900))
                        .animate()
                        .fadeIn(delay: 150.ms)
                        .slideX(begin: -0.2),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _ActionCard(
                    emoji: '🧑‍⚕️',
                    color: PetColors.violet,
                    title: 'Gestionar pacientes',
                    subtitle: 'Crear pacientes, aplicar el test y emparejarlos con su mejor animal',
                    onTap: () => context.push('/pacientes'),
                  ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.2),
                  const SizedBox(height: 14),
                  _ActionCard(
                    emoji: '🐕',
                    color: PetColors.teal,
                    title: 'Gestionar animales',
                    subtitle: 'Cargar, editar y ver el estado de cada animal',
                    onTap: () => context.push('/animales'),
                  ).animate().fadeIn(delay: 620.ms).slideY(begin: 0.2),
                  if (user?.esAdmin ?? false) ...[
                    const SizedBox(height: 14),
                    _ActionCard(
                      emoji: '👥',
                      color: PetColors.amber,
                      title: 'Usuarios',
                      subtitle: 'Crear, editar, desactivar y eliminar usuarios',
                      onTap: () => context.push('/admin/usuarios'),
                    ).animate().fadeIn(delay: 740.ms).slideY(begin: 0.2),
                    const SizedBox(height: 14),
                    _ActionCard(
                      emoji: '📜',
                      color: PetColors.coral,
                      title: 'Registro de eventos',
                      subtitle: 'Qué hizo cada usuario y cuándo',
                      onTap: () => context.push('/admin/auditoria'),
                    ).animate().fadeIn(delay: 860.ms).slideY(begin: 0.2),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String emoji;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionCard({
    required this.emoji,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(child: Text(emoji, style: const TextStyle(fontSize: 30))),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(color: PetColors.inkSoft, fontSize: 13, height: 1.2)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
