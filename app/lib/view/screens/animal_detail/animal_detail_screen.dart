import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:petmatcher/view/theme/theme.dart';
import 'package:petmatcher/view/widgets/widgets.dart';
import 'package:petmatcher/viewmodel/animal_viewmodel.dart';
import 'package:petmatcher/model/models.dart';
import 'package:petmatcher/view/widgets/catalog_ui.dart';

/// Argumentos de navegación de esta pantalla (DTO de vista, no entidad de dominio).
/// [patient] y [result] solo llegan cuando se abre desde el ranking (flujo de
/// emparejamiento). Desde "Gestionar animales" ambos son null y NO se puede asignar.
class AnimalDetailArgs {
  final MatchResult? result;
  final Patient? patient;
  const AnimalDetailArgs({this.result, this.patient});
}

/// Perfil detallado de un animal. Si se abre desde el ranking ([args.patient] != null)
/// permite asignar el animal a ese paciente. Desde "Gestionar animales" solo ver/editar.
class AnimalDetailScreen extends ConsumerStatefulWidget {
  final String animalId;
  final AnimalDetailArgs args;
  const AnimalDetailScreen({
    super.key,
    required this.animalId,
    this.args = const AnimalDetailArgs(),
  });

  @override
  ConsumerState<AnimalDetailScreen> createState() => _AnimalDetailScreenState();
}

class _AnimalDetailScreenState extends ConsumerState<AnimalDetailScreen> {
  late final ConfettiController _confetti;

  MatchResult? get result => widget.args.result;
  Patient? get patient => widget.args.patient;
  String get animalId => widget.animalId;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 1));
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(animalViewModelProvider); // reconstruir al cambiar estado
    final repo = ref.read(animalViewModelProvider.notifier);
    final animal = repo.byId(animalId);
    if (animal == null) {
      return const Scaffold(body: Center(child: Text('Animal no encontrado')));
    }
    final color = result != null ? PetColors.categoria(result!.categoria) : PetColors.teal;

    return Scaffold(
      body: Stack(
        children: [
          _buildContent(context, ref, repo, animal, color),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirection: math.pi / 2,
              emissionFrequency: 0.05,
              numberOfParticles: 20,
              maxBlastForce: 20,
              minBlastForce: 8,
              gravity: 0.25,
              colors: const [
                PetColors.coral,
                PetColors.teal,
                PetColors.amber,
                PetColors.violet,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, AnimalViewModel repo,
      Animal animal, Color color) {
    return CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: color,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(gradient: PetGradients.teal),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Hero(
                        tag: 'emoji-${animal.id}',
                        // Material transparente evita el subrayado amarillo
                        // durante el vuelo del Hero (Text sin ancestro Material).
                        child: Material(
                          type: MaterialType.transparency,
                          child: Text(CatalogUi.emoji(animal.tipoAnimal),
                              style: const TextStyle(fontSize: 84)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(animal.nombre,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (result != null) ...[
                    Row(
                      children: [
                        PercentRing(value: result!.efectividad, color: color, size: 88),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(CatalogUi.categoriaLabel(result!.categoria),
                                  style: TextStyle(
                                      color: color, fontSize: 18, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              Text('Efectividad terapéutica estimada',
                                  style: TextStyle(color: PetColors.inkSoft, fontSize: 13)),
                              const SizedBox(height: 8),
                              ...result!.porModelo.entries.map((e) => Text(
                                  '${e.key}: ${e.value.toStringAsFixed(1)}%',
                                  style: TextStyle(color: PetColors.inkSoft, fontSize: 12))),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                  _StatusChip(animal: animal),
                  if (patient != null) ...[
                    const SizedBox(height: 20),
                    _SectionTitle('Comparación con ${patient!.nombre}'),
                    _Comparacion(patient: patient!, animal: animal),
                  ],
                  const SizedBox(height: 16),
                  const _SectionTitle('Perfil'),
                  _InfoGrid(animal: animal),
                  if (animal.notas != null && animal.notas!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const _SectionTitle('Notas'),
                    Text(animal.notas!, style: const TextStyle(height: 1.4)),
                  ],
                  const SizedBox(height: 28),
                  _actions(context, ref, repo, animal),
                ],
              ),
            ),
          ),
        ],
      );
  }

  /// Botonera contextual:
  /// - Editar siempre.
  /// - Asignar SOLO en flujo de emparejamiento (patient != null) y si está disponible.
  /// - Liberar si está asignado (desde gestión).
  Widget _actions(BuildContext context, WidgetRef ref, AnimalViewModel repo, Animal animal) {
    final editar = OutlinedButton.icon(
      onPressed: () => context.push('/animal/${animal.id}/editar'),
      icon: const Icon(Icons.edit_rounded),
      label: const Text('Editar'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );

    // Flujo de emparejamiento: asignar a este paciente.
    if (patient != null && animal.disponible) {
      return Row(
        children: [
          Expanded(child: editar),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: () => _asignar(context, ref, animal, patient!),
              icon: const Icon(Icons.link_rounded),
              label: Text('Asignar a ${patient!.nombre}'),
            ),
          ),
        ],
      );
    }

    // Gestión: si está asignado, permitir liberar.
    if (animal.asignadoAPacienteId != null) {
      return Row(
        children: [
          Expanded(child: editar),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: () => repo.liberar(animal.id),
              style: FilledButton.styleFrom(backgroundColor: PetColors.inkSoft),
              icon: const Icon(Icons.link_off_rounded),
              label: const Text('Liberar'),
            ),
          ),
        ],
      );
    }

    // Gestión, animal disponible: solo editar.
    return SizedBox(width: double.infinity, child: editar);
  }

  Future<void> _asignar(
      BuildContext context, WidgetRef ref, Animal animal, Patient patient) async {
    final messenger = ScaffoldMessenger.of(context);
    // Celebra si el match es de compatibilidad alta.
    final esMatchAlto = result != null && result!.efectividad >= 80;
    try {
      await ref.read(animalViewModelProvider.notifier).asignar(animal.id, patient.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text('🎉 ${animal.nombre} asignado a ${patient.nombre}'),
          backgroundColor: PetColors.teal,
        ),
      );
      if (esMatchAlto) {
        _confetti.play();
        await Future.delayed(const Duration(milliseconds: 1300));
      }
      // Emparejamiento finalizado: volver al inicio de la app.
      if (context.mounted) context.go('/');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo asignar: $e'), backgroundColor: PetColors.coral),
      );
    }
  }
}

class _StatusChip extends StatelessWidget {
  final Animal animal;
  const _StatusChip({required this.animal});
  @override
  Widget build(BuildContext context) {
    final disponible = animal.disponible;
    final color = disponible ? PetColors.teal : PetColors.coral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(disponible ? Icons.check_circle_rounded : Icons.lock_rounded,
              size: 18, color: color),
          const SizedBox(width: 6),
          Text(disponible ? 'Disponible' : 'Asignado',
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  final Animal animal;
  const _InfoGrid({required this.animal});
  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      ('Tipo', animal.tipoAnimal),
      ('Sexo', animal.sexoAnimal),
      ('Edad', '${animal.edadAnimal} años'),
      ('Peso', '${animal.pesoKg} kg'),
      ('Energía', '${animal.nivelEnergiaAnimal}/5'),
      ('Sociabilidad', '${animal.nivelSociabilidadAnimal}/5'),
      ('Calma', '${animal.nivelCalmaAnimal}/5'),
      ('Tol. ruido', '${animal.toleranciaRuido}/5'),
      ('Tol. contacto', '${animal.toleranciaContacto}/5'),
      ('Entrenamiento', animal.tipoEntrenamiento),
      ('Exp. (meses)', '${animal.experienciaTerapeuticaMeses}'),
      ('Certificado', animal.certificadoTerapia),
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

/// Compara, dimensión por dimensión, el perfil del paciente con el del animal.
///
/// Muestra los valores enfrentados y NO calcula un puntaje de encaje: ese juicio
/// lo produce el modelo (y lo narra el LLM en "Más información del resultado").
/// Replicar acá una fórmula propia sería duplicar lógica de dominio en la vista y
/// arriesgarse a contradecir al modelo.
class _Comparacion extends StatelessWidget {
  final Patient patient;
  final Animal animal;
  const _Comparacion({required this.patient, required this.animal});

  @override
  Widget build(BuildContext context) {
    // Reglas de compatibilidad del modelo: HI ↔ calma y contacto, IN ↔ sociabilidad,
    // presentación combinada ↔ tolerancia al ruido. El paciente (0-27) se lleva a la
    // escala 1-5 solo para dibujar la barra; el valor real va en la etiqueta.
    final p = patient.perfilAdhd;
    int nivel(int v) => (v / 27 * 4).round() + 1;
    final dims = <(String, String, int, String, int)>[
      if (p != null) ...[
        ('Hiperactividad ↔ calma', 'HI ${p.hiperactividad}/27', nivel(p.hiperactividad),
            'Calma', animal.nivelCalmaAnimal),
        ('Hiperactividad ↔ contacto', 'HI ${p.hiperactividad}/27', nivel(p.hiperactividad),
            'Tol. contacto', animal.toleranciaContacto),
        ('Inatención ↔ sociabilidad', 'IN ${p.inatencion}/27', nivel(p.inatencion),
            'Sociabilidad', animal.nivelSociabilidadAnimal),
        (
          'Presentación combinada ↔ ruido',
          p.presentacion == 'combinada' ? 'Combinada' : 'No combinada',
          p.presentacion == 'combinada' ? 5 : 1,
          'Tol. ruido',
          animal.toleranciaRuido
        ),
      ],
    ];
    final coincidePref = patient.preferenciaAnimal == animal.tipoAnimal;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              _Leyenda(color: PetColors.coral, texto: 'Paciente'),
              const SizedBox(width: 14),
              _Leyenda(color: PetColors.teal, texto: 'Animal'),
            ],
          ),
        ),
        ...dims.map((d) => _FilaComparacion(
              dimension: d.$1,
              etiquetaPaciente: d.$2,
              valorPaciente: d.$3,
              etiquetaAnimal: d.$4,
              valorAnimal: d.$5,
            )),
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: (coincidePref ? PetColors.teal : PetColors.inkSoft)
                .withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(coincidePref ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                  size: 19, color: coincidePref ? PetColors.teal : PetColors.inkSoft),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  coincidePref
                      ? 'Coincide con el animal de preferencia (${patient.preferenciaAnimal})'
                      : 'Prefiere ${patient.preferenciaAnimal}; este es ${animal.tipoAnimal}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Leyenda extends StatelessWidget {
  final Color color;
  final String texto;
  const _Leyenda({required this.color, required this.texto});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(texto, style: TextStyle(fontSize: 12, color: PetColors.inkSoft)),
        ],
      );
}

/// Una dimensión: dos barras 1-5 enfrentadas, paciente arriba y animal abajo.
class _FilaComparacion extends StatelessWidget {
  final String dimension;
  final String etiquetaPaciente;
  final int valorPaciente;
  final String etiquetaAnimal;
  final int valorAnimal;

  const _FilaComparacion({
    required this.dimension,
    required this.etiquetaPaciente,
    required this.valorPaciente,
    required this.etiquetaAnimal,
    required this.valorAnimal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dimension,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _Barra(etiqueta: etiquetaPaciente, valor: valorPaciente, color: PetColors.coral),
          const SizedBox(height: 7),
          _Barra(etiqueta: etiquetaAnimal, valor: valorAnimal, color: PetColors.teal),
        ],
      ),
    );
  }
}

class _Barra extends StatelessWidget {
  final String etiqueta;
  final int valor;
  final Color color;
  const _Barra({required this.etiqueta, required this.valor, required this.color});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(
            width: 108,
            child: Text(etiqueta,
                style: TextStyle(fontSize: 11.5, color: PetColors.inkSoft)),
          ),
          Expanded(
            child: Row(
              children: List.generate(
                5,
                (i) => Expanded(
                  child: Container(
                    height: 8,
                    margin: EdgeInsets.only(right: i == 4 ? 0 : 4),
                    decoration: BoxDecoration(
                      color: i < valor ? color : color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 16,
            child: Text('$valor',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800, color: color)),
          ),
        ],
      );
}
