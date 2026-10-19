import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:petmatcher/model/models.dart';
import 'package:petmatcher/view/screens/admin/admin_audit_screen.dart';
import 'package:petmatcher/view/screens/admin/admin_users_screen.dart';
import 'package:petmatcher/view/screens/animal_detail/animal_detail_screen.dart';
import 'package:petmatcher/view/screens/animals/animal_edit_screen.dart';
import 'package:petmatcher/view/screens/animals/animals_screen.dart';
import 'package:petmatcher/view/screens/auth/login_screen.dart';
import 'package:petmatcher/view/screens/onboarding/onboarding_screen.dart';
import 'package:petmatcher/view/screens/patient_form/patient_form_screen.dart';
import 'package:petmatcher/view/screens/patients/patient_detail_screen.dart';
import 'package:petmatcher/view/screens/patients/patients_screen.dart';
import 'package:petmatcher/view/screens/ranking/ranking_screen.dart';
import 'package:petmatcher/viewmodel/auth_viewmodel.dart';

/// El router depende de la sesión: sin usuario todo lleva a /login, y /admin/* exige
/// rol admin (la API lo vuelve a exigir: esto es solo para no mostrar pantallas inútiles).
final routerProvider = Provider<GoRouter>((ref) {
  final cambios = ValueNotifier<int>(0);
  ref.listen(authProvider, (_, _) => cambios.value++);
  ref.onDispose(cambios.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: cambios,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;
      if (auth.isLoading) return loc == '/cargando' ? null : '/cargando';
      final user = auth.value;
      if (user == null) return loc == '/login' ? null : '/login';
      if (loc == '/login' || loc == '/cargando') return '/';
      if (loc.startsWith('/admin') && !user.esAdmin) return '/';
      return null;
    },
    routes: _rutas,
  );
});

final _rutas = <RouteBase>[
    GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
    GoRoute(
      path: '/cargando',
      builder: (c, s) => const Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
    GoRoute(path: '/admin/usuarios', builder: (c, s) => const AdminUsersScreen()),
    GoRoute(path: '/admin/auditoria', builder: (c, s) => const AdminAuditScreen()),
    GoRoute(path: '/', builder: (c, s) => const OnboardingScreen()),
    // Alta de paciente: al guardar vuelve al listado.
    GoRoute(path: '/paciente', builder: (c, s) => const PatientFormScreen()),
    GoRoute(path: '/pacientes', builder: (c, s) => const PatientsScreen()),
    GoRoute(
      path: '/paciente/:id/editar',
      builder: (c, s) => PatientFormScreen(existing: s.extra as Patient?),
    ),
    GoRoute(
      path: '/paciente/:id',
      builder: (c, s) => PatientDetailScreen(patientId: s.pathParameters['id']!),
    ),
    // El ranking necesita el paciente (viaja por extra, sin estado global).
    GoRoute(
      path: '/ranking',
      builder: (c, s) {
        final patient = s.extra as Patient?;
        return patient == null
            ? const OnboardingScreen()
            : RankingScreen(patient: patient);
      },
    ),
    GoRoute(path: '/animales', builder: (c, s) => const AnimalsScreen()),
    GoRoute(
      path: '/animal/nuevo/editar',
      builder: (c, s) => const AnimalEditScreen(),
    ),
    GoRoute(
      path: '/animal/:id/editar',
      builder: (c, s) => AnimalEditScreen(animalId: s.pathParameters['id']),
    ),
    GoRoute(
      path: '/animal/:id',
      builder: (c, s) => AnimalDetailScreen(
        animalId: s.pathParameters['id']!,
        args: s.extra is AnimalDetailArgs
            ? s.extra as AnimalDetailArgs
            : const AnimalDetailArgs(),
      ),
    ),
];
