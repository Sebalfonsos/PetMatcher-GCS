import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Modo de tema de la app (sigue el sistema por defecto; el usuario puede alternar).
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
