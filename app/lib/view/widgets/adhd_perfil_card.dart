import 'package:flutter/material.dart';

import 'package:petmatcher/model/adhd.dart';
import 'package:petmatcher/view/theme/theme.dart';

/// Tarjeta con el perfil que arroja el ADHD-RS (IN, HI, total, síntomas,
/// presentación y cribado). Reutilizada en el resultado del test y en el detalle
/// del paciente.
class AdhdPerfilCard extends StatelessWidget {
  final PerfilAdhd perfil;
  const AdhdPerfilCard({super.key, required this.perfil});

  @override
  Widget build(BuildContext context) {
    final cribadoColor = perfil.cribadoPositivo ? PetColors.coral : PetColors.teal;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(perfil.presentacionLabel, PetColors.violet),
              _Chip(
                perfil.cribadoPositivo
                    ? 'Cribado positivo (≥ ${perfil.corteUsado})'
                    : 'Cribado negativo (< ${perfil.corteUsado})',
                cribadoColor,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Barra(
              etiqueta: 'Inatención (IN)',
              valor: perfil.inatencion,
              max: 27,
              sintomas: perfil.sintomasIn,
              color: PetColors.amber),
          const SizedBox(height: 14),
          _Barra(
              etiqueta: 'Hiperactividad/impulsividad (HI)',
              valor: perfil.hiperactividad,
              max: 27,
              sintomas: perfil.sintomasHi,
              color: PetColors.coral),
          const SizedBox(height: 14),
          _Barra(
              etiqueta: 'Total (TOT)',
              valor: perfil.total,
              max: 54,
              color: PetColors.violet),
          const SizedBox(height: 14),
          Text(
            'Un ítem con 2 o 3 cuenta como síntoma; 5 o más síntomas en un dominio '
            'cumplen el umbral DSM-5 en adultos. Es un resultado de cribado, no un diagnóstico.',
            style: TextStyle(fontSize: 12, color: PetColors.inkSoft, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
      );
}

class _Barra extends StatelessWidget {
  final String etiqueta;
  final int valor;
  final int max;
  final int? sintomas;
  final Color color;
  const _Barra({
    required this.etiqueta,
    required this.valor,
    required this.max,
    required this.color,
    this.sintomas,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(etiqueta,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
            Text('$valor / $max',
                style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: valor / max),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 9,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        if (sintomas != null) ...[
          const SizedBox(height: 4),
          Text('$sintomas de 9 síntomas presentes',
              style: TextStyle(fontSize: 12, color: PetColors.inkSoft)),
        ],
      ],
    );
  }
}
