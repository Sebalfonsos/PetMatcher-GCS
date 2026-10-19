import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:petmatcher/model/api_client.dart';
import 'package:petmatcher/model/models.dart';

/// VIEWMODEL — Estado de la colección de animales, respaldado por la API
/// (FastAPI + PostgreSQL). El estado es la lista cargada; las mutaciones
/// llaman a la API y refrescan.
class AnimalViewModel extends AsyncNotifier<List<Animal>> {
  PetMatcherApi get _api => ref.read(apiProvider);

  @override
  Future<List<Animal>> build() => _api.listAnimals();

  List<Animal> get _items => state.value ?? const [];

  /// Ver la extensión [AnimalesDisponibles] en model/models.dart: la regla vive ahí.
  List<Animal> get disponibles => _items.disponibles;

  Animal? byId(String id) {
    for (final a in _items) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<void> _refresh() async {
    state = await AsyncValue.guard(() => _api.listAnimals());
  }

  Future<void> create(Animal animal) async {
    await _api.createAnimal(animal);
    await _refresh();
  }

  Future<void> edit(Animal animal) async {
    await _api.updateAnimal(animal);
    await _refresh();
  }

  Future<void> remove(String id) async {
    await _api.deleteAnimal(id);
    await _refresh();
  }

  Future<void> asignar(String animalId, String pacienteId) async {
    await _api.assignAnimal(animalId, pacienteId);
    await _refresh();
  }

  Future<void> liberar(String animalId) async {
    await _api.releaseAnimal(animalId);
    await _refresh();
  }
}

final animalViewModelProvider =
    AsyncNotifierProvider<AnimalViewModel, List<Animal>>(AnimalViewModel.new);
