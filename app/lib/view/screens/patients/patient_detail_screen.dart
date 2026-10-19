import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:petmatcher/view/theme/theme.dart';
import 'package:petmatcher/viewmodel/animal_viewmodel.dart';
import 'package:petmatcher/model/models.dart';
import 'package:petmatcher/viewmodel/patients_viewmodel.dart';
import 'package:petmatcher/view/widgets/adhd_perfil_card.dart';
import 'package:petmatcher/view/widgets/catalog_ui.dart';

/// Ver el perfil completo de un paciente, con opción de editar, seleccionarlo
/// para emparejar y ver su animal asignado.
class PatientDetailScreen extends ConsumerWidget {
  final String patientId;
  const PatientDetailScreen({super.key, required this.patientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patients = ref.watch(patientsProvider);
    Patient? patient;
    for (final p in patients.value ?? const <Patient>[]) {
      if (p.id == patientId) {
        patient = p;
        break;
      }
    }

    if (patient == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: patients.isLoading
              ? const CircularProgressIndicator()
              : const Text('Paciente no encontrado'),
        ),
      );
    }

    final animals = ref.watch(animalViewModelProvider).value ?? const <Animal>[];
    Animal? asignado;
    for (final a in animals) {
      if (a.asignadoAPacienteId == patient.id) {
        asignado = a;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paciente'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Editar',
            onPressed: () => context.push('/paciente/${patient!.id}/editar', extra: patient),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: PetColors.violet.withValues(alpha: 0.15),
                  child: Text(
                    patient.nombre.isNotEmpty ? patient.nombre[0].toUpperCase() : '?',
                    style: const TextStyle(
                        fontSize: 34, fontWeight: FontWeight.w900, color: PetColors.violet),
                  ),
                ),
                const SizedBox(height: 12),
                Text(patient.nombre,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (asignado != null) ...[
            _SectionTitle('Animal asignado'),
            Card(
              child: ListTile(
                leading: Text(CatalogUi.emoji(asignado.tipoAnimal),
                    style: const TextStyle(fontSize: 30)),
                title: Text(asignado.nombre,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${_cap(asignado.raza)} · ${_cap(asignado.tipoAnimal)}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/animal/${asignado!.id}'),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _SectionTitle('Datos básicos'),
          _InfoGrid(patient: patient),
          const SizedBox(height: 22),
          _SectionTitle('Test ADHD-RS'),
          if (patient.perfilAdhd != null)
            AdhdPerfilCard(perfil: patient.perfilAdhd!)
          else
            _SinTest(onCompletar: () =>
                context.push('/paciente/${patient!.id}/editar', extra: patient)),
          const SizedBox(height: 28),
          // Solo se puede emparejar con test completo y sin animal asignado.
          if (!patient.tieneTest)
            const SizedBox.shrink()
          else if (asignado == null)
            FilledButton.icon(
              onPressed: () => context.push('/ranking', extra: patient),
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Emparejar (ver ranking)'),
            )
          else
            Text('Este paciente ya tiene un animal asignado.',
                style: TextStyle(color: PetColors.inkSoft)),
        ],
      ),
    );
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _InfoGrid extends StatelessWidget {
  final Patient patient;
  const _InfoGrid({required this.patient});

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      ('Edad', '${patient.edadPaciente} años'),
      ('Sexo', patient.sexoPaciente),
      ('Entorno familiar', patient.entornoFamiliar),
      ('Animal preferido', patient.preferenciaAnimal),
      ('Exp. con animales', patient.experienciaPreviaConAnimales),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items
          .map((e) => Container(
                width: (MediaQuery.of(context).size.width - 50) / 2,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.$1, style: TextStyle(color: PetColors.inkSoft, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(_cap(e.$2),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ],
                ),
              ))
          .toList(),
    );
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      );
}

/// Paciente anterior al test ADHD-RS: sin respuestas no hay perfil ni ranking.
class _SinTest extends StatelessWidget {
  final VoidCallback onCompletar;
  const _SinTest({required this.onCompletar});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: PetColors.amber.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Este paciente aún no tiene el test ADHD-RS.',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('El perfil conductual sale del test; sin él no se puede emparejar.',
                style: TextStyle(color: PetColors.inkSoft, fontSize: 13)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onCompletar,
              icon: const Icon(Icons.quiz_rounded),
              label: const Text('Completar el test'),
            ),
          ],
        ),
      );
}
