import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:petmatcher/model/catalog.dart';
import 'package:petmatcher/view/theme/theme.dart';
import 'package:petmatcher/view/widgets/widgets.dart';
import 'package:petmatcher/viewmodel/animal_viewmodel.dart';
import 'package:petmatcher/model/models.dart';

/// Formulario para crear o editar un animal (13 features + nombre y notas).
class AnimalEditScreen extends ConsumerStatefulWidget {
  final String? animalId; // null = nuevo
  const AnimalEditScreen({super.key, this.animalId});

  @override
  ConsumerState<AnimalEditScreen> createState() => _AnimalEditScreenState();
}

class _AnimalEditScreenState extends ConsumerState<AnimalEditScreen> {
  late final TextEditingController _nombre;
  late final TextEditingController _notas;
  String _tipo = 'perro';
  String _sexo = 'macho';
  late final TextEditingController _edad;
  late String _raza;
  late final TextEditingController _peso;
  int _energia = 3;
  int _sociabilidad = 3;
  int _calma = 3;
  int _tolRuido = 3;
  int _tolContacto = 3;
  late String _entrenamiento;
  int _experiencia = 12;
  String _certificado = 'no';

  bool get _isNew => widget.animalId == null;

  @override
  void initState() {
    super.initState();
    final existing =
        widget.animalId == null ? null : ref.read(animalViewModelProvider.notifier).byId(widget.animalId!);
    _nombre = TextEditingController(text: existing?.nombre ?? '');
    _notas = TextEditingController(text: existing?.notas ?? '');
    if (existing != null) {
      _tipo = existing.tipoAnimal;
      _sexo = existing.sexoAnimal;
      _energia = existing.nivelEnergiaAnimal;
      _sociabilidad = existing.nivelSociabilidadAnimal;
      _calma = existing.nivelCalmaAnimal;
      _tolRuido = existing.toleranciaRuido;
      _tolContacto = existing.toleranciaContacto;
      _experiencia = existing.experienciaTerapeuticaMeses;
      _certificado = existing.certificadoTerapia;
    }
    _edad = TextEditingController(text: '${existing?.edadAnimal ?? 3}');
    _peso = TextEditingController(text: _fmtPeso(existing?.pesoKg ?? 15));
    _raza = existing?.raza ?? Catalog.razas(_tipo).first;
    _entrenamiento = existing?.tipoEntrenamiento ?? Catalog.entrenamientos(_tipo).first;
  }

  static String _fmtPeso(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// Edad válida del animal (0-40), 0 por defecto si vacío/fuera de rango.
  int get _edadValida => (int.tryParse(_edad.text) ?? 0).clamp(0, 40);

  /// Peso válido (0.1-900 kg), 0.1 por defecto si vacío/fuera de rango.
  double get _pesoValido =>
      (double.tryParse(_peso.text) ?? 0.1).clamp(0.1, 900).toDouble();

  @override
  void dispose() {
    _nombre.dispose();
    _notas.dispose();
    _edad.dispose();
    _peso.dispose();
    super.dispose();
  }

  void _onTipoChanged(String tipo) {
    setState(() {
      _tipo = tipo;
      // Reajustar raza/entrenamiento a las opciones válidas del nuevo tipo.
      if (!Catalog.razas(tipo).contains(_raza)) _raza = Catalog.razas(tipo).first;
      if (!Catalog.entrenamientos(tipo).contains(_entrenamiento)) {
        _entrenamiento = Catalog.entrenamientos(tipo).first;
      }
    });
  }

  bool _saving = false;

  Future<void> _save() async {
    final repo = ref.read(animalViewModelProvider.notifier);
    final existing = _isNew ? null : repo.byId(widget.animalId!);
    final animal = Animal(
      id: existing?.id ?? 'new',
      nombre: _nombre.text.trim().isEmpty ? 'Sin nombre' : _nombre.text.trim(),
      tipoAnimal: _tipo,
      sexoAnimal: _sexo,
      edadAnimal: _edadValida,
      raza: _raza,
      pesoKg: _pesoValido,
      nivelEnergiaAnimal: _energia,
      nivelSociabilidadAnimal: _sociabilidad,
      nivelCalmaAnimal: _calma,
      toleranciaRuido: _tolRuido,
      toleranciaContacto: _tolContacto,
      tipoEntrenamiento: _entrenamiento,
      experienciaTerapeuticaMeses: _experiencia,
      certificadoTerapia: _certificado,
      notas: _notas.text.trim(),
      asignadoAPacienteId: existing?.asignadoAPacienteId,
    );
    setState(() => _saving = true);
    try {
      if (_isNew) {
        await repo.create(animal);
      } else {
        await repo.edit(animal);
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo guardar. ¿API activa? ($e)'),
            backgroundColor: PetColors.coral,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'Cargar animal' : 'Editar animal')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nombre,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 18),
            LabeledDropdown(
                label: 'Tipo de animal',
                value: _tipo,
                options: Catalog.tipoAnimal,
                onChanged: _onTipoChanged),
            const SizedBox(height: 16),
            LabeledDropdown(
                label: 'Raza',
                value: _raza,
                options: Catalog.razas(_tipo),
                onChanged: (v) => setState(() => _raza = v)),
            const SizedBox(height: 16),
            LabeledDropdown(
                label: 'Sexo',
                value: _sexo,
                options: Catalog.sexoAnimal,
                onChanged: (v) => setState(() => _sexo = v)),
            const SizedBox(height: 18),
            TextField(
              controller: _edad,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
                const MaxIntFormatter(40),
              ],
              decoration: const InputDecoration(
                labelText: 'Edad (años)',
                hintText: '0 a 40',
                suffixText: 'años',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _peso,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d{0,1})?')),
              ],
              decoration: const InputDecoration(
                labelText: 'Peso',
                hintText: '0.1 a 900',
                suffixText: 'kg',
              ),
            ),
            const SizedBox(height: 16),
            LevelSlider(label: 'Energía', value: _energia, onChanged: (v) => setState(() => _energia = v)),
            LevelSlider(label: 'Sociabilidad', value: _sociabilidad, onChanged: (v) => setState(() => _sociabilidad = v)),
            LevelSlider(label: 'Calma', value: _calma, onChanged: (v) => setState(() => _calma = v)),
            LevelSlider(label: 'Tolerancia al ruido', value: _tolRuido, onChanged: (v) => setState(() => _tolRuido = v)),
            LevelSlider(label: 'Tolerancia al contacto', value: _tolContacto, onChanged: (v) => setState(() => _tolContacto = v)),
            const SizedBox(height: 8),
            LabeledDropdown(
                label: 'Tipo de entrenamiento',
                value: _entrenamiento,
                options: Catalog.entrenamientos(_tipo),
                onChanged: (v) => setState(() => _entrenamiento = v)),
            const SizedBox(height: 20),
            Text('Experiencia terapéutica: $_experiencia meses',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Slider(
              value: _experiencia.toDouble(),
              min: 0,
              max: 240,
              activeColor: PetColors.coral,
              label: '$_experiencia',
              onChanged: (v) => setState(() => _experiencia = v.round()),
            ),
            const SizedBox(height: 8),
            LabeledDropdown(
                label: 'Certificado de terapia',
                value: _certificado,
                options: Catalog.siNo,
                onChanged: (v) => setState(() => _certificado = v)),
            const SizedBox(height: 16),
            TextField(
              controller: _notas,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notas (opcional)'),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Icon(Icons.save_rounded),
                label: Text(_saving
                    ? 'Guardando...'
                    : (_isNew ? 'Guardar animal' : 'Guardar cambios')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
