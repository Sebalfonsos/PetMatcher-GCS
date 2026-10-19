import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:petmatcher/view/theme/theme.dart';

/// Impide que el valor numérico escrito supere [max]. El mínimo se garantiza al
/// enviar el formulario (permite el campo vacío mientras se edita).
class MaxIntFormatter extends TextInputFormatter {
  final int max;
  const MaxIntFormatter(this.max);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final value = int.tryParse(newValue.text);
    if (value == null || value > max) return oldValue;
    return newValue;
  }
}

/// Indicador circular de porcentaje con animación de barrido.
class PercentRing extends StatelessWidget {
  final double value; // 0-100
  final Color color;
  final double size;
  const PercentRing({super.key, required this.value, required this.color, this.size = 76});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 100)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: v / 100,
                strokeWidth: 8,
                backgroundColor: color.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation(color),
                strokeCap: StrokeCap.round,
              ),
            ),
            Text('${v.round()}%',
                style: TextStyle(
                    fontSize: size * 0.26, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }
}

/// Slider de nivel 1-5 con etiqueta.
class LevelSlider extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const LevelSlider({super.key, required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              decoration: BoxDecoration(
                color: PetColors.coral.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$value',
                  style: const TextStyle(color: PetColors.coral, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: 1,
          max: 5,
          divisions: 4,
          activeColor: PetColors.coral,
          label: '$value',
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }
}

/// Dropdown estilizado con etiqueta.
class LabeledDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 4),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        DropdownButtonFormField<String>(
          initialValue: options.contains(value) ? value : options.first,
          isExpanded: true,
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(_cap(o))))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Tarjeta con gradiente reutilizable.
class GradientHeader extends StatelessWidget {
  final Widget child;
  final Gradient gradient;
  final double height;
  const GradientHeader({super.key, required this.child, required this.gradient, this.height = 200});

  @override
  Widget build(BuildContext context) {
    // minHeight (no altura fija) para que el contenido nunca desborde.
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: height),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
      ),
      child: SafeArea(child: child),
    );
  }
}
