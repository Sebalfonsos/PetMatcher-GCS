import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:petmatcher/model/api_client.dart';
import 'package:petmatcher/model/models.dart';

/// VIEWMODEL — Ranking de un paciente, persistido en la API.
///
/// Es `family` sobre el id del paciente: el paciente viaja por el flujo de
/// navegación, NO hay estado global de "paciente activo" (ver plan.md §6.1).
///
/// Al abrir la pantalla se pide el ranking GUARDADO; solo si el paciente nunca
/// tuvo uno se genera. Para recalcularlo hay que pedirlo explícitamente
/// ([regenerar]): así volver a entrar muestra siempre lo que ya se había hecho.
class RankingViewModel extends AsyncNotifier<RankingGuardado> {
  final String patientId;
  RankingViewModel(this.patientId);

  PetMatcherApi get _api => ref.read(apiProvider);

  @override
  Future<RankingGuardado> build() async {
    final guardado = await _api.getRanking(patientId);
    return guardado ?? await _api.createRanking(patientId);
  }

  /// Recalcula con los animales disponibles ahora. Devuelve true si el resultado
  /// salió idéntico al guardado (se conserva el anterior y su explicación).
  /// Mientras calcula se sigue viendo el ranking anterior (`isLoading` + valor).
  Future<bool> regenerar() async {
    // Asignar AsyncLoading conserva el valor anterior (isLoading + hasValue).
    state = const AsyncLoading<RankingGuardado>();
    final nuevo = await AsyncValue.guard(() => _api.createRanking(patientId));
    // Si falla, se vuelve al ranking anterior en vez de dejar la pantalla en error.
    if (nuevo.hasError && state.hasValue) {
      state = AsyncData(state.requireValue);
      throw nuevo.error!;
    }
    state = nuevo;
    return nuevo.value?.sinCambios ?? false;
  }

  /// Vuelve a leer lo guardado, sin recalcular (p. ej. al terminar de guardarse
  /// la explicación).
  Future<void> refrescar() async {
    final g = await AsyncValue.guard(() => _api.getRanking(patientId));
    if (!ref.mounted) return;
    final valor = g.value;
    if (valor != null) state = AsyncData(valor);
  }
}

final rankingProvider = AsyncNotifierProvider.autoDispose
    .family<RankingViewModel, RankingGuardado, String>(RankingViewModel.new);
