import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:petmatcher/model/catalog.dart';
import 'package:petmatcher/view/screens/patient_form/adhd_test_views.dart';
import 'package:petmatcher/view/theme/theme.dart';
import 'package:petmatcher/view/widgets/adhd_perfil_card.dart';
import 'package:petmatcher/view/widgets/widgets.dart';
import 'package:petmatcher/model/models.dart';
import 'package:petmatcher/viewmodel/adhd_viewmodel.dart';
import 'package:petmatcher/viewmodel/patients_viewmodel.dart';

/// Cómo se llena el test ADHD-RS del paciente.
enum _ModoTest {
  /// El test ya se aplicó antes: se capturan las 18 respuestas.
  resultados,

  /// Se aplica el test ahora, una pregunta por pantalla.
  aplicar,
}

/// Formulario por pasos del paciente:
///   1. Datos básicos (nombre, edad, sexo, entorno, preferencia, experiencia).
///   2. Test ADHD-RS: ingresar resultados ya obtenidos O aplicarlo en la app.
///   3. Resultado del test (lo puntúa la API) y guardado.
///
/// - [existing] != null → modo edición (guarda y vuelve).
class PatientFormScreen extends ConsumerStatefulWidget {
  final Patient? existing;
  const PatientFormScreen({super.key, this.existing});

  @override
  ConsumerState<PatientFormScreen> createState() => _PatientFormScreenState();
}

class _PatientFormScreenState extends ConsumerState<PatientFormScreen> {
  static const _pasos = 3;
  int _step = 0;
  _ModoTest _modo = _ModoTest.resultados;

  late final TextEditingController _nombre;
  late final TextEditingController _edad;
  String _sexo = 'femenino';
  String _entorno = 'estable';
  String _preferencia = 'perro';
  String _experiencia = 'no';

  /// Las 18 respuestas (null = sin responder). Compartido por ambos modos.
  final List<int?> _resp = List<int?>.filled(18, null);

  bool get _isEdit => widget.existing != null;
  bool get _testCompleto => !_resp.contains(null);

  /// Clave "212012…" para consultar el perfil a la API.
  String get _clave => _resp.map((r) => r ?? 0).join();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nombre = TextEditingController(text: e?.nombre ?? '');
    _edad = TextEditingController(text: '${e?.edadPaciente ?? 30}');
    if (e != null) {
      _sexo = e.sexoPaciente;
      _entorno = e.entornoFamiliar;
      _preferencia = e.preferenciaAnimal;
      _experiencia = e.experienciaPreviaConAnimales;
      final r = e.respuestasAdhd;
      if (r != null && r.length == 18) {
        for (var i = 0; i < 18; i++) {
          _resp[i] = r[i];
        }
      }
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _edad.dispose();
    super.dispose();
  }

  /// Edad válida (17-99): el ADHD-RS aplica a adultos.
  int get _edadValida =>
      (int.tryParse(_edad.text) ?? Catalog.edadMinimaPaciente)
          .clamp(Catalog.edadMinimaPaciente, 99);

  bool _saving = false;

  Future<void> _finish() async {
    final data = Patient(
      id: widget.existing?.id ?? const Uuid().v4(),
      nombre: _nombre.text.trim().isEmpty ? 'Paciente' : _nombre.text.trim(),
      edadPaciente: _edadValida,
      sexoPaciente: _sexo,
      entornoFamiliar: _entorno,
      preferenciaAnimal: _preferencia,
      experienciaPreviaConAnimales: _experiencia,
      respuestasAdhd: _resp.map((r) => r!).toList(),
    );
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await ref.read(patientsProvider.notifier).edit(data);
        if (mounted) context.pop();
      } else {
        await ref.read(patientsProvider.notifier).create(data);
        if (mounted) context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo guardar el paciente. ¿API activa? ($e)'),
            backgroundColor: PetColors.coral,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _puedeAvanzar => switch (_step) {
        0 => true,
        1 => _testCompleto,
        _ => true,
      };

  String get _etiquetaSiguiente => switch (_step) {
        0 => 'Continuar al test',
        1 => _testCompleto ? 'Ver resultado' : 'Faltan respuestas',
        _ => _isEdit ? 'Guardar cambios' : 'Guardar paciente',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Editar paciente' : 'Perfil del paciente')),
      body: Column(
        children: [
          _ProgressBar(step: _step, total: _pasos),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: switch (_step) {
                0 => _stepDatos(),
                1 => _stepTest(),
                _ => _stepResultado(),
              },
            ),
          ),
          _NavBar(
            step: _step,
            saving: _saving,
            enabled: _puedeAvanzar,
            nextLabel: _etiquetaSiguiente,
            onBack: () => setState(() => _step--),
            onNext: () {
              if (_saving || !_puedeAvanzar) return;
              if (_step < _pasos - 1) {
                setState(() => _step++);
              } else {
                _finish();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _stepDatos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Datos básicos'),
        TextField(
          controller: _nombre,
          decoration: const InputDecoration(labelText: 'Nombre del paciente'),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _edad,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
            _RangeFormatter(min: Catalog.edadMinimaPaciente, max: 99),
          ],
          decoration: InputDecoration(
            labelText: 'Edad (años)',
            hintText: '${Catalog.edadMinimaPaciente} a 99',
            helperText: 'El test ADHD-RS aplica a adultos (17 años o más)',
            suffixText: 'años',
          ),
        ),
        const SizedBox(height: 16),
        LabeledDropdown(
          label: 'Sexo',
          value: _sexo,
          options: Catalog.sexoPaciente,
          onChanged: (v) => setState(() => _sexo = v),
        ),
        const SizedBox(height: 16),
        LabeledDropdown(
          label: 'Entorno familiar',
          value: _entorno,
          options: Catalog.entornoFamiliar,
          onChanged: (v) => setState(() => _entorno = v),
        ),
        const SizedBox(height: 16),
        LabeledDropdown(
          label: 'Animal de preferencia',
          value: _preferencia,
          options: Catalog.preferenciaAnimal,
          onChanged: (v) => setState(() => _preferencia = v),
        ),
        const SizedBox(height: 16),
        LabeledDropdown(
          label: 'Experiencia previa con animales',
          value: _experiencia,
          options: Catalog.siNo,
          onChanged: (v) => setState(() => _experiencia = v),
        ),
      ],
    );
  }

  Widget _stepTest() {
    final respondidas = _resp.where((r) => r != null).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Test ADHD-RS'),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<_ModoTest>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: _ModoTest.resultados,
                icon: Icon(Icons.edit_note_rounded),
                label: Text('Ya tengo los resultados'),
              ),
              ButtonSegment(
                value: _ModoTest.aplicar,
                icon: Icon(Icons.quiz_rounded),
                label: Text('Aplicar el test'),
              ),
            ],
            selected: {_modo},
            onSelectionChanged: (s) => setState(() => _modo = s.first),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Las respuestas se conservan al cambiar de modo. Respondidas: $respondidas/18',
          style: TextStyle(fontSize: 12, color: PetColors.inkSoft),
        ),
        const SizedBox(height: 18),
        // La clave del modo reinicia el estado interno al cambiar de vista.
        if (_modo == _ModoTest.resultados)
          AdhdEntryView(
            key: const ValueKey('entrada'),
            respuestas: _resp,
            onChanged: () => setState(() {}),
          )
        else
          AdhdGuidedView(
            key: const ValueKey('guiado'),
            respuestas: _resp,
            onChanged: () => setState(() {}),
          ),
      ],
    );
  }

  Widget _stepResultado() {
    final perfil = ref.watch(perfilAdhdProvider(_clave));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Resultado del test'),
        perfil.when(
          data: (p) => AdhdPerfilCard(perfil: p),
          loading: () => const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Column(
            children: [
              const Text('No se pudo calcular el perfil. ¿API activa?'),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => ref.invalidate(perfilAdhdProvider(_clave)),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Este perfil es lo que usa el modelo para emparejar. Para corregir una '
          'respuesta, vuelva atrás.',
          style: TextStyle(fontSize: 12, color: PetColors.inkSoft),
        ),
      ],
    );
  }
}

/// Impide que el valor escrito supere [max]. El mínimo se garantiza al enviar
/// (ver _edadValida), permitiendo el campo vacío mientras se edita.
class _RangeFormatter extends TextInputFormatter {
  final int min;
  final int max;
  const _RangeFormatter({required this.min, required this.max});

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final value = int.tryParse(newValue.text);
    if (value == null || value > max) return oldValue;
    return newValue;
  }
}

class _ProgressBar extends StatelessWidget {
  final int step;
  final int total;
  const _ProgressBar({required this.step, required this.total});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _seg(step >= i)),
          ],
        ],
      ),
    );
  }

  Widget _seg(bool active) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 6,
        decoration: BoxDecoration(
          color: active ? PetColors.coral : PetColors.coral.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(3),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      );
}

class _NavBar extends StatelessWidget {
  final int step;
  final bool saving;
  final bool enabled;
  final String nextLabel;
  final VoidCallback onBack;
  final VoidCallback onNext;
  const _NavBar({
    required this.step,
    required this.saving,
    required this.enabled,
    required this.nextLabel,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            if (step > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: saving ? null : onBack,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  child: const Text('Atrás'),
                ),
              ),
            if (step > 0) const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: (saving || !enabled) ? null : onNext,
                child: saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : Text(nextLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
