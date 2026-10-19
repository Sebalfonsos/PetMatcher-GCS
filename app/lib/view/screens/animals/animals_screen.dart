import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:petmatcher/view/theme/theme.dart';
import 'package:petmatcher/viewmodel/animal_viewmodel.dart';
import 'package:petmatcher/model/models.dart';
import 'package:petmatcher/view/widgets/catalog_ui.dart';

/// Listado y gestión de animales (crear, editar, ver estado).
class AnimalsScreen extends ConsumerWidget {
  const AnimalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animals = ref.watch(animalViewModelProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Animales')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/animal/nuevo/editar'),
        backgroundColor: PetColors.coral,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Cargar animal'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(animalViewModelProvider.future),
        child: animals.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('No se pudo cargar.\n¿API activa? (docker compose up)\n\n$e',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: PetColors.inkSoft)),
                ),
              ),
            ],
          ),
          data: (list) => list.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: 140),
                    Center(
                      child: Text('Aún no hay animales.\nToca "Cargar animal".',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: PetColors.inkSoft)),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final a = list[i];
                    return _AnimalTile(animal: a)
                        .animate()
                        .fadeIn(delay: (50 * i).ms)
                        .slideY(begin: 0.1);
                  },
                ),
        ),
      ),
    );
  }
}

class _AnimalTile extends StatelessWidget {
  final Animal animal;
  const _AnimalTile({required this.animal});

  @override
  Widget build(BuildContext context) {
    final color = animal.disponible ? PetColors.teal : PetColors.coral;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          onTap: () => context.push('/animal/${animal.id}'),
          leading: Hero(
            tag: 'emoji-${animal.id}',
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Material(
                  type: MaterialType.transparency,
                  child: Text(CatalogUi.emoji(animal.tipoAnimal),
                      style: const TextStyle(fontSize: 28)),
                ),
              ),
            ),
          ),
          title: Text(animal.nombre,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          subtitle: Text('${_cap(animal.raza)} · ${_cap(animal.tipoAnimal)}',
              style: TextStyle(color: PetColors.inkSoft)),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(animal.disponible ? 'Disponible' : 'Asignado',
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
