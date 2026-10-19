import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:petmatcher/view/theme/theme.dart';
import 'package:petmatcher/view/widgets/widgets.dart';
import 'package:petmatcher/viewmodel/animal_viewmodel.dart';
import 'package:petmatcher/model/models.dart';
import 'package:petmatcher/viewmodel/ranking_viewmodel.dart';
import 'package:petmatcher/view/widgets/catalog_ui.dart';
import 'package:petmatcher/view/widgets/fecha.dart';
import 'package:petmatcher/view/screens/animal_detail/animal_detail_screen.dart';
import 'package:petmatcher/view/screens/ranking/explicacion_sheet.dart';

/// Ranking de animales ordenados por efectividad terapéutica para [patient].
/// Muestra el ranking GUARDADO (si ya se hizo uno) y permite generar uno nuevo.
/// La asignación se hace desde aquí (tocando un animal → detalle con el paciente).
class RankingScreen extends ConsumerWidget {
  final Patient patient;
  const RankingScreen({super.key, required this.patient});

  Future<void> _regenerar(BuildContext context, WidgetRef ref) async {
    final msg = ScaffoldMessenger.of(context);
    try {
      final igual = await ref.read(rankingProvider(patient.id).notifier).regenerar();
      msg.showSnackBar(SnackBar(
        content: Text(igual
            ? 'El ranking no cambió: se conserva el anterior y su explicación.'
            : 'Ranking actualizado.'),
      ));
    } catch (e) {
      msg.showSnackBar(SnackBar(
        content: Text('No se pudo generar el ranking. ¿API activa? ($e)'),
        backgroundColor: PetColors.coral,
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranking = ref.watch(rankingProvider(patient.id));
    final recalculando = ranking.isLoading && ranking.hasValue;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ranking de compatibilidad'),
        actions: [
          IconButton(
            tooltip: 'Generar un ranking nuevo',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: recalculando ? null : () => _regenerar(context, ref),
          ),
        ],
        bottom: recalculando
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: ranking.when(
        skipLoadingOnReload: true,
        loading: () => const _Loading(),
        error: (e, _) => _ErrorView(
          onRetry: () => ref.invalidate(rankingProvider(patient.id)),
          message: e.toString(),
        ),
        data: (rk) {
          if (rk.resultados.isEmpty) {
            return const _EmptyView();
          }
          final results = rk.resultados;
          final animals = ref.read(animalViewModelProvider.notifier);
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            // +1 encabezado, +1 botón de explicación al final del ranking.
            itemCount: results.length + 2,
            itemBuilder: (context, i) {
              if (i == 0) {
                return _Encabezado(
                  patient: patient,
                  ranking: rk,
                  recalculando: recalculando,
                  onRegenerar: () => _regenerar(context, ref),
                );
              }
              if (i == results.length + 1) {
                return _BotonExplicacion(patient: patient, ranking: rk);
              }
              final r = results[i - 1];
              final animal = animals.byId(r.animalId);
              // Animación solo la primera vez que se arma la lista: al reentrar a un
              // ranking guardado se muestra de una, sin repetir la entrada.
              return _RankCard(rank: i, result: r, animal: animal, patient: patient)
                  .animate()
                  .fadeIn(delay: (60 * i).ms)
                  .slideX(begin: 0.12, curve: Curves.easeOut);
            },
          );
        },
      ),
    );
  }
}

/// Cabecera: a quién corresponde, cuándo se generó y, si ya no refleja la realidad,
/// por qué y cómo actualizarlo.
class _Encabezado extends StatelessWidget {
  final Patient patient;
  final RankingGuardado ranking;
  final bool recalculando;
  final VoidCallback onRegenerar;
  const _Encabezado({
    required this.patient,
    required this.ranking,
    required this.recalculando,
    required this.onRegenerar,
  });

  @override
  Widget build(BuildContext context) {
    final cuando = ranking.generadoEn;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paciente: ${patient.nombre} · ${ranking.resultados.length} animales evaluados',
            style: TextStyle(color: PetColors.inkSoft, fontWeight: FontWeight.w600),
          ),
          if (cuando != null) ...[
            const SizedBox(height: 2),
            Text('Generado el ${fechaHora(cuando)} (${hace(cuando)})',
                style: TextStyle(color: PetColors.inkSoft, fontSize: 12.5)),
          ],
          if (ranking.obsoleto) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: PetColors.amber.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Este ranking puede estar desactualizado',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  for (final m in ranking.motivos)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text('· $m',
                          style: TextStyle(
                              color: PetColors.inkSoft, fontSize: 13, height: 1.3)),
                    ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: recalculando ? null : onRegenerar,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Generar ranking nuevo'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RankCard extends StatelessWidget {
  final int rank;
  final MatchResult result;

  /// Null si el animal ya no existe: el ranking guardado se muestra igual con los
  /// datos que se copiaron al generarlo, pero no se puede abrir su detalle.
  final Animal? animal;
  final Patient patient;
  const _RankCard({
    required this.rank,
    required this.result,
    required this.animal,
    required this.patient,
  });

  @override
  Widget build(BuildContext context) {
    final color = PetColors.categoria(result.categoria);
    final nombre = result.nombre ?? animal?.nombre ?? 'Animal';
    final tipo = result.tipoAnimal ?? animal?.tipoAnimal ?? '';
    final raza = result.raza ?? animal?.raza ?? '';
    // Ya asignado a alguien después de generar el ranking (o eliminado).
    final noDisponible = animal == null || !animal!.disponible;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            if (animal == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Este animal ya no existe.')),
              );
              return;
            }
            context.push('/animal/${animal!.id}',
                extra: AnimalDetailArgs(result: result, patient: patient));
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.topLeft,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(CatalogUi.emoji(tipo),
                            style: const TextStyle(fontSize: 30)),
                      ),
                    ),
                    if (rank <= 3)
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: rank == 1
                              ? PetColors.amber
                              : (rank == 2 ? Colors.blueGrey : Colors.brown),
                          shape: BoxShape.circle,
                        ),
                        child: Text('$rank',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nombre,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('${_cap(raza)} · ${_cap(tipo)}',
                          style: TextStyle(color: PetColors.inkSoft, fontSize: 13)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _Etiqueta(CatalogUi.categoriaLabel(result.categoria), color),
                          if (noDisponible)
                            _Etiqueta(animal == null ? 'Ya no existe' : 'Ya asignado',
                                PetColors.inkSoft),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                PercentRing(value: result.efectividad, color: color, size: 68),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  final Color color;
  const _Etiqueta(this.texto, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(texto,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🐾', style: TextStyle(fontSize: 48))
              .animate(onPlay: (c) => c.repeat())
              .scaleXY(end: 1.2, duration: 700.ms)
              .then()
              .scaleXY(end: 0.83, duration: 700.ms),
          const SizedBox(height: 16),
          Text('Calculando compatibilidades...',
              style: TextStyle(color: PetColors.inkSoft, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('😿', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            const Text('No hay animales disponibles',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Todos están asignados o aún no has cargado ninguno.',
                textAlign: TextAlign.center,
                style: TextStyle(color: PetColors.inkSoft)),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final String message;
  const _ErrorView({required this.onRetry, required this.message});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔌', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            const Text('No se pudo conectar con la API',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Verifica que el servicio FastAPI esté corriendo (docker compose up).',
                textAlign: TextAlign.center, style: TextStyle(color: PetColors.inkSoft)),
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

/// Botón que abre la orientación del LLM sobre el ranking guardado.
/// Se muestra al final de la lista, después del último animal.
class _BotonExplicacion extends ConsumerWidget {
  final Patient patient;
  final RankingGuardado ranking;
  const _BotonExplicacion({required this.patient, required this.ranking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guardada = ranking.explicacion;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        children: [
          FilledButton.icon(
            onPressed: ranking.id == null
                ? null
                : () => mostrarExplicacion(context, ref, patient, ranking),
            icon: const Text('🧠', style: TextStyle(fontSize: 18)),
            label: Text(guardada == null
                ? 'Más información del resultado'
                : 'Ver la explicación guardada'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: PetColors.teal,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              textStyle:
                  const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            guardada == null
                ? 'Explica por qué el modelo eligió este orden para ${patient.nombre}.'
                : 'Generada el ${fechaHora(guardada.generadoEn)}. Se genera de nuevo '
                    'solo si el ranking cambia.',
            textAlign: TextAlign.center,
            style: TextStyle(color: PetColors.inkSoft, fontSize: 12.5),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 250.ms);
  }
}
