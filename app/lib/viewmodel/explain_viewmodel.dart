import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:petmatcher/model/api_client.dart';
import 'package:petmatcher/viewmodel/ranking_viewmodel.dart';

/// Estado de una generación EN CURSO de la orientación del LLM.
///
/// La orientación terminada no vive acá: la API la guarda junto al ranking y llega
/// en `RankingGuardado.explicacion`. Este estado solo cubre el rato en que se está
/// escribiendo (o falló).
class ExplainState {
  /// Texto acumulado hasta ahora. Crece mientras el modelo escribe.
  final String texto;
  final bool generando;
  final String? error;

  /// Ranking al que corresponde. Un ranking nuevo tiene otro id, así que un texto
  /// viejo nunca se confunde con el del ranking actual.
  final String? rankingId;

  const ExplainState({
    this.texto = '',
    this.generando = false,
    this.error,
    this.rankingId,
  });

  ExplainState copyWith({String? texto, bool? generando, String? error}) => ExplainState(
        texto: texto ?? this.texto,
        generando: generando ?? this.generando,
        error: error ?? this.error,
        rankingId: rankingId,
      );
}

/// VIEWMODEL — consume `/rankings/{id}/explicacion/stream` y acumula el texto.
///
/// NO es `.autoDispose` a propósito: la generación tiene que sobrevivir a que se
/// cierre la hoja (puede tardar un minuto). Al terminar, la API ya la guardó y se
/// relee el ranking para que la hoja pase a mostrar la versión guardada.
class ExplainViewModel extends Notifier<ExplainState> {
  @override
  ExplainState build() => const ExplainState();

  /// Genera la orientación del ranking [rankingId]. La API responde 409 si ese
  /// ranking ya tiene una guardada (solo se regenera cuando el ranking cambia).
  Future<void> generar(String rankingId, String patientId) async {
    if (state.generando) return;
    state = ExplainState(generando: true, rankingId: rankingId);

    String? error;
    try {
      final stream = ref.read(apiProvider).explainRankingStream(rankingId);
      await for (final msg in stream) {
        if (!ref.mounted) return;
        switch (msg['tipo']) {
          case 'texto':
            state = state.copyWith(texto: state.texto + (msg['delta'] as String));
          case 'error':
            error = msg['detalle'] as String?;
        }
      }
    } catch (e) {
      error = e.toString();
    }
    if (!ref.mounted) return;

    // Sin error, la API ya guardó el texto: se relee el ranking y la hoja pasa a
    // mostrar la versión guardada. El texto en vivo se conserva hasta que llegue.
    if (error == null) {
      await ref.read(rankingProvider(patientId).notifier).refrescar();
    }
    if (!ref.mounted) return;
    state = ExplainState(
        texto: state.texto, rankingId: rankingId, error: error, generando: false);
  }
}

final explainProvider =
    NotifierProvider<ExplainViewModel, ExplainState>(ExplainViewModel.new);
