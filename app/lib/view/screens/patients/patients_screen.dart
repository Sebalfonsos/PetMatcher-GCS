import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:petmatcher/view/theme/theme.dart';
import 'package:petmatcher/viewmodel/animal_viewmodel.dart';
import 'package:petmatcher/model/models.dart';
import 'package:petmatcher/viewmodel/patients_viewmodel.dart';

/// Panel de pacientes: crear, ver, editar, borrar y emparejar. El emparejamiento
/// arranca desde acá (menú del paciente o botón "Emparejar" de su detalle) y el
/// paciente viaja al ranking por navegación, sin estado global.
class PatientsScreen extends ConsumerWidget {
  const PatientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patients = ref.watch(patientsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pacientes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/paciente'),
        backgroundColor: PetColors.coral,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Nuevo paciente'),
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(patientsProvider.notifier).refreshList(),
              child: patients.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('No se pudo cargar.\n¿API activa?\n\n$e',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: PetColors.inkSoft)),
                    ),
                  ),
                ]),
                data: (all) {
                  final list = all;
                  if (list.isEmpty) {
                    return ListView(children: [
                      const SizedBox(height: 140),
                      Center(
                        child: Text(
                          'Aún no hay pacientes.\nToca "Nuevo paciente".',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: PetColors.inkSoft),
                        ),
                      ),
                    ]);
                  }
                  return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final p = list[i];
                          return _PatientTile(patient: p).animate().fadeIn(delay: (50 * i).ms).slideY(begin: 0.1);
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

class _PatientTile extends ConsumerWidget {
  final Patient patient;
  const _PatientTile({required this.patient});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Animal asignado a este paciente (si los animales ya están cargados).
    final animals = ref.watch(animalViewModelProvider).value ?? const <Animal>[];
    Animal? asignado;
    for (final a in animals) {
      if (a.asignadoAPacienteId == patient.id) {
        asignado = a;
        break;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => context.push('/paciente/${patient.id}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: PetColors.coral.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(patient.nombre.isNotEmpty ? patient.nombre[0].toUpperCase() : '?',
                        style: const TextStyle(
                            color: PetColors.coral, fontSize: 24, fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(patient.nombre,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                          '${patient.edadPaciente} años · ${patient.sexoPaciente}'
                          '${patient.perfilAdhd != null ? ' · ${patient.perfilAdhd!.presentacionLabel}' : ''}',
                          style: TextStyle(color: PetColors.inkSoft, fontSize: 13)),
                      if (!patient.tieneTest)
                        const Text('Sin test ADHD-RS — toque para completarlo',
                            style: TextStyle(
                                color: PetColors.amber,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      if (asignado != null) ...[
                        const SizedBox(height: 4),
                        Text('🐾 ${asignado.nombre}',
                            style: const TextStyle(
                                color: PetColors.teal,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'ver') {
                      context.push('/paciente/${patient.id}');
                    } else if (v == 'emparejar') {
                      context.push('/ranking', extra: patient);
                    } else if (v == 'delete') {
                      _confirmDelete(context, ref);
                    }
                  },
                  itemBuilder: (_) => [
                    // Solo con test completo y sin animal asignado (§6.1 del plan).
                    if (patient.tieneTest && asignado == null)
                      const PopupMenuItem(value: 'emparejar', child: Text('Emparejar')),
                    const PopupMenuItem(value: 'ver', child: Text('Ver / editar')),
                    const PopupMenuItem(value: 'delete', child: Text('Eliminar paciente')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar paciente'),
        content: Text('¿Eliminar a ${patient.nombre}? Se liberarán sus animales asignados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PetColors.coral),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(patientsProvider.notifier).remove(patient.id);
    ref.invalidate(animalViewModelProvider); // refresca estado de animales liberados
  }
}
