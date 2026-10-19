import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:petmatcher/model/api_client.dart';
import 'package:petmatcher/model/models.dart';

/// VIEWMODEL — Estado del panel de pacientes.
/// Expone la lista de pacientes de la API y las mutaciones que la afectan.
class PatientsViewModel extends AsyncNotifier<List<Patient>> {
  @override
  Future<List<Patient>> build() => ref.read(apiProvider).listPatients();

  Future<void> refreshList() async {
    state = await AsyncValue.guard(() => ref.read(apiProvider).listPatients());
  }

  /// Crea el paciente y devuelve el id que asignó el backend.
  /// La vista lo necesita para navegar al ranking del paciente recién creado.
  Future<String> create(Patient p) async {
    final id = await ref.read(apiProvider).createPatient(p);
    await refreshList();
    return id;
  }

  Future<void> edit(Patient p) async {
    await ref.read(apiProvider).updatePatient(p);
    await refreshList();
  }

  Future<void> remove(String id) async {
    await ref.read(apiProvider).deletePatient(id);
    await refreshList();
  }
}

final patientsProvider =
    AsyncNotifierProvider<PatientsViewModel, List<Patient>>(PatientsViewModel.new);
