import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:petmatcher/model/models.dart';
import 'package:petmatcher/view/theme/theme.dart';
import 'package:petmatcher/view/widgets/fecha.dart';
import 'package:petmatcher/viewmodel/explain_viewmodel.dart';
import 'package:petmatcher/viewmodel/ranking_viewmodel.dart';

/// Abre la hoja de "Más información del resultado" para el ranking guardado.
///
/// Si ese ranking YA tiene una explicación guardada, solo se muestra: no se vuelve
/// a consultar al modelo. Si no la tiene, se empieza a generar (la API la guarda al
/// terminar). La explicación se genera de nuevo únicamente cuando el ranking cambia,
/// porque un ranking nuevo es un ranking sin explicación.
///
/// El disparo va acá y no en el `initState` de la hoja para que no dependa del
/// ciclo de vida del widget.
Future<void> mostrarExplicacion(
  BuildContext context,
  WidgetRef ref,
  Patient patient,
  RankingGuardado ranking,
) {
  final id = ranking.id;
  if (id != null && ranking.explicacion == null) {
    ref.read(explainProvider.notifier).generar(id, patient.id);
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ExplicacionSheet(patientId: patient.id, rankingId: id ?? ''),
  );
}

class _ExplicacionSheet extends ConsumerStatefulWidget {
  final String patientId;
  final String rankingId;
  const _ExplicacionSheet({required this.patientId, required this.rankingId});

  @override
  ConsumerState<_ExplicacionSheet> createState() => _ExplicacionSheetState();
}

class _ExplicacionSheetState extends ConsumerState<_ExplicacionSheet> {
  bool _copiado = false;

  Future<void> _copiar(String texto) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    setState(() => _copiado = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Texto copiado al portapapeles'),
        duration: Duration(seconds: 2),
      ),
    );
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copiado = false);
  }

  @override
  Widget build(BuildContext context) {
    // Lo guardado manda; mientras no exista, se muestra la generación en curso.
    final guardada = ref.watch(rankingProvider(widget.patientId)).value?.explicacion;
    final vivo = ref.watch(explainProvider);
    final enVivo = vivo.rankingId == widget.rankingId ? vivo : const ExplainState();
    final texto = guardada?.texto ?? enVivo.texto;
    final generando = guardada == null && enVivo.generando;
    final error = guardada == null ? enVivo.error : null;
    final fondo = Theme.of(context).colorScheme.surface;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: PetColors.inkSoft.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
              child: Row(
                children: [
                  const Text('🧠', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Más información del resultado',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                        if (generando || guardada != null)
                          Text(
                            generando
                                ? 'Generando…'
                                : 'Guardada el ${fechaHora(guardada!.generadoEn)}'
                                    ' · se reutiliza hasta que el ranking cambie',
                            style: TextStyle(
                                fontSize: 11.5, color: PetColors.inkSoft),
                          ),
                      ],
                    ),
                  ),
                  if (generando)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    )
                  else ...[
                    // Se habilita recién cuando el modelo terminó de escribir:
                    // copiar a mitad de la generación daría un texto truncado.
                    IconButton(
                      tooltip: _copiado ? 'Copiado' : 'Copiar texto',
                      onPressed: texto.isEmpty ? null : () => _copiar(texto),
                      icon: Icon(_copiado
                          ? Icons.check_rounded
                          : Icons.copy_all_rounded),
                      color: _copiado ? PetColors.teal : null,
                    ),
                    // Solo hay reintento si la generación FALLÓ y no quedó nada guardado.
                    // Una explicación guardada no se regenera: solo cambia con el ranking.
                    if (error != null)
                      IconButton(
                        tooltip: 'Reintentar',
                        onPressed: () => ref
                            .read(explainProvider.notifier)
                            .generar(widget.rankingId, widget.patientId),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                  ],
                ],
              ),
            ),
            const Divider(height: 18),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  if (error != null) _Aviso(mensaje: error),
                  if (texto.isEmpty && generando)
                    const _Esperando()
                  else
                    ..._renderizar(texto),
                  if (texto.isNotEmpty && !generando) ...[
                    const SizedBox(height: 22),
                    Text(
                      'Texto generado por un modelo de lenguaje a partir de la '
                      'evidencia calculada sobre el modelo de ML. Es apoyo a la '
                      'interpretación, no una indicación clínica.',
                      style: TextStyle(
                          fontSize: 11.5, color: PetColors.inkSoft, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Renderiza el markdown acotado que produce el prompt (`### título` + párrafos).
  /// No se usa un paquete de markdown: el formato lo definimos nosotros y son
  /// dos casos, no vale sumar una dependencia.
  List<Widget> _renderizar(String texto) {
    final widgets = <Widget>[];
    for (final linea in texto.split('\n')) {
      final t = linea.trim();
      if (t.isEmpty) continue;
      if (t.startsWith('#')) {
        widgets.add(Padding(
          padding: EdgeInsets.only(top: widgets.isEmpty ? 4 : 20, bottom: 6),
          child: Text(
            t.replaceAll(RegExp(r'^#+\s*'), ''),
            style: TextStyle(
                fontSize: 15.5, fontWeight: FontWeight.w800, color: PetColors.teal),
          ),
        ));
      } else {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            t.replaceAll('**', '').replaceFirst(RegExp(r'^[-*]\s*'), '· '),
            style: const TextStyle(fontSize: 14.5, height: 1.55),
          ),
        ));
      }
    }
    return widgets;
  }
}

class _Esperando extends StatelessWidget {
  const _Esperando();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 34),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Analizando el ranking…',
                style: TextStyle(color: PetColors.inkSoft, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('El texto va a ir apareciendo a medida que se genera.',
                textAlign: TextAlign.center,
                style: TextStyle(color: PetColors.inkSoft, fontSize: 12.5)),
          ],
        ),
      );
}

class _Aviso extends StatelessWidget {
  final String mensaje;
  const _Aviso({required this.mensaje});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PetColors.amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('No se pudo generar la orientación',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Verificá que el servidor de LM Studio esté levantado en el puerto '
              '1234 con un modelo cargado.',
              style: TextStyle(color: PetColors.inkSoft, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 6),
            Text(mensaje,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: PetColors.inkSoft, fontSize: 11)),
          ],
        ),
      );
}
