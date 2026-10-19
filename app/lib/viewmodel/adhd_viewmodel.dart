import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:petmatcher/model/adhd.dart';
import 'package:petmatcher/model/api_client.dart';

/// VIEWMODEL — Cuestionario ADHD-RS (texto servido por la API).
final cuestionarioAdhdProvider = FutureProvider<AdhdCuestionario>(
    (ref) => ref.read(apiProvider).getCuestionarioAdhd());

/// Perfil calculado por la API para un conjunto de respuestas. La clave es el
/// string de 18 dígitos ("212012…") para que el family cachee por contenido.
final perfilAdhdProvider = FutureProvider.autoDispose.family<PerfilAdhd, String>(
  (ref, clave) => ref
      .read(apiProvider)
      .scoreAdhd(clave.split('').map(int.parse).toList()),
);
