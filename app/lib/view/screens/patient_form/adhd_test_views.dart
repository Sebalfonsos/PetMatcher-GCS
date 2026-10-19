import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:petmatcher/model/adhd.dart';
import 'package:petmatcher/view/theme/theme.dart';
import 'package:petmatcher/viewmodel/adhd_viewmodel.dart';

/// Las dos formas de llenar el test ADHD-RS comparten el mismo estado
/// (`List<int?>` de 18): se puede empezar en una y seguir en la otra.

/// Carga el cuestionario de la API y delega en [builder]; maneja carga y error.
class _ConCuestionario extends ConsumerWidget {
  final Widget Function(AdhdCuestionario q) builder;
  const _ConCuestionario({required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(cuestionarioAdhdProvider);
    return q.when(
      data: builder,
      loading: () => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text('No se pudo cargar el cuestionario. ¿API activa?',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref.invalidate(cuestionarioAdhdProvider),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modo 1: "Ya tengo los resultados" — se capturan las 18 respuestas de una hoja
// ya contestada, todas visibles, más un campo para pegarlas de corrido.
// ---------------------------------------------------------------------------
class AdhdEntryView extends StatefulWidget {
  final List<int?> respuestas;
  final VoidCallback onChanged;
  const AdhdEntryView({super.key, required this.respuestas, required this.onChanged});

  @override
  State<AdhdEntryView> createState() => _AdhdEntryViewState();
}

class _AdhdEntryViewState extends State<AdhdEntryView> {
  final _pegar = TextEditingController();

  @override
  void dispose() {
    _pegar.dispose();
    super.dispose();
  }

  /// Acepta "212012…" o con espacios/comas ("2 1 2 0 …"). Solo se aplica si
  /// hay exactamente 18 valores entre 0 y 3.
  void _aplicarPegado(String txt) {
    final digitos = txt.replaceAll(RegExp(r'[\s,;.\-]'), '');
    if (digitos.length != 18 || !RegExp(r'^[0-3]{18}$').hasMatch(digitos)) return;
    setState(() {
      for (var i = 0; i < 18; i++) {
        widget.respuestas[i] = int.parse(digitos[i]);
      }
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return _ConCuestionario(builder: (q) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Copie las respuestas marcadas en el cuestionario ya aplicado '
            '(últimos 6 meses). 0 = ${q.opciones[0].etiqueta}, 3 = ${q.opciones[3].etiqueta}.',
            style: TextStyle(color: PetColors.inkSoft, height: 1.35),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _pegar,
            keyboardType: TextInputType.text,
            onChanged: _aplicarPegado,
            decoration: const InputDecoration(
              labelText: 'Pegar las 18 respuestas de corrido (opcional)',
              hintText: '2 1 3 0 2 1 2 0 3 1 2 0 3 1 2 0 3 1',
              prefixIcon: Icon(Icons.content_paste_rounded),
            ),
          ),
          const SizedBox(height: 18),
          for (final item in q.items)
            _FilaEntrada(
              item: item,
              opciones: q.opciones,
              valor: widget.respuestas[item.n - 1],
              onSelected: (v) {
                setState(() => widget.respuestas[item.n - 1] = v);
                widget.onChanged();
              },
            ),
        ],
      );
    });
  }
}

class _FilaEntrada extends StatelessWidget {
  final AdhdItem item;
  final List<AdhdOpcion> opciones;
  final int? valor;
  final ValueChanged<int> onSelected;
  const _FilaEntrada({
    required this.item,
    required this.opciones,
    required this.valor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final sinResponder = valor == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: sinResponder
                ? Colors.black.withValues(alpha: 0.06)
                : PetColors.teal.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${item.n}. ${item.texto}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final o in opciones)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: o.etiqueta,
                      child: ChoiceChip(
                        label: SizedBox(
                          width: double.infinity,
                          child: Text('${o.valor}', textAlign: TextAlign.center),
                        ),
                        showCheckmark: false,
                        selected: valor == o.valor,
                        selectedColor: PetColors.coral.withValues(alpha: 0.85),
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: valor == o.valor ? Colors.white : null,
                        ),
                        onSelected: (_) => onSelected(o.valor),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modo 2: "Aplicar el test ahora" — una pregunta por pantalla, con opciones
// grandes. Avanza solo al responder.
// ---------------------------------------------------------------------------
class AdhdGuidedView extends StatefulWidget {
  final List<int?> respuestas;
  final VoidCallback onChanged;
  const AdhdGuidedView({super.key, required this.respuestas, required this.onChanged});

  @override
  State<AdhdGuidedView> createState() => _AdhdGuidedViewState();
}

class _AdhdGuidedViewState extends State<AdhdGuidedView> {
  int _actual = 0;
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    // Si ya hay respuestas, continúa en la primera sin responder.
    final i = widget.respuestas.indexWhere((r) => r == null);
    _actual = i == -1 ? 17 : i;
  }

  @override
  void dispose() {
    _auto?.cancel();
    super.dispose();
  }

  void _responder(int valor) {
    setState(() => widget.respuestas[_actual] = valor);
    widget.onChanged();
    _auto?.cancel();
    if (_actual < 17) {
      // Pausa corta para que se vea la opción elegida antes de avanzar.
      _auto = Timer(const Duration(milliseconds: 280), () {
        if (mounted) setState(() => _actual++);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ConCuestionario(builder: (q) {
      final item = q.items[_actual];
      final respondidas = widget.respuestas.where((r) => r != null).length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q.instruccion, style: TextStyle(color: PetColors.inkSoft, height: 1.35)),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Pregunta ${item.n} de 18',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('$respondidas respondidas',
                  style: TextStyle(color: PetColors.inkSoft, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: respondidas / 18,
              minHeight: 8,
              backgroundColor: PetColors.coral.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation(PetColors.coral),
            ),
          ),
          const SizedBox(height: 22),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Container(
              key: ValueKey(_actual),
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              ),
              child: Text(item.texto,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w700, height: 1.35)),
            ),
          ),
          const SizedBox(height: 18),
          for (final o in q.opciones)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _OpcionGrande(
                opcion: o,
                seleccionada: widget.respuestas[_actual] == o.valor,
                onTap: () => _responder(o.valor),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed: _actual > 0 ? () => setState(() => _actual--) : null,
                icon: const Icon(Icons.chevron_left_rounded),
                label: const Text('Anterior'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _actual < 17 && widget.respuestas[_actual] != null
                    ? () => setState(() => _actual++)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
                label: const Text('Siguiente'),
              ),
            ],
          ),
        ],
      );
    });
  }
}

class _OpcionGrande extends StatelessWidget {
  final AdhdOpcion opcion;
  final bool seleccionada;
  final VoidCallback onTap;
  const _OpcionGrande({required this.opcion, required this.seleccionada, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = seleccionada ? PetColors.coral : PetColors.inkSoft;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: seleccionada
              ? PetColors.coral.withValues(alpha: 0.12)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: seleccionada ? PetColors.coral : Colors.black.withValues(alpha: 0.08),
              width: seleccionada ? 2 : 1),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: color.withValues(alpha: 0.15),
              child: Text('${opcion.valor}',
                  style: TextStyle(fontWeight: FontWeight.w900, color: color)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(opcion.etiqueta,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: seleccionada ? FontWeight.w800 : FontWeight.w600)),
            ),
            if (seleccionada) const Icon(Icons.check_circle_rounded, color: PetColors.coral),
          ],
        ),
      ),
    );
  }
}
