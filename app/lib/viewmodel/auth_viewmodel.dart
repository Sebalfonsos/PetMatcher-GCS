import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:petmatcher/model/api_client.dart';
import 'package:petmatcher/model/auth_models.dart';

/// VIEWMODEL — Sesión del usuario. El estado es el usuario autenticado, o null.
///
/// El token se guarda en el almacén seguro del sistema para no pedir login en cada
/// arranque. Si el almacén no está disponible (tests, plataformas sin soporte) la
/// sesión simplemente no persiste.
class AuthViewModel extends AsyncNotifier<AppUser?> {
  static const _clave = 'petmatcher_token';
  static const _storage = FlutterSecureStorage();

  @override
  Future<AppUser?> build() async {
    final api = ref.read(apiProvider);
    api.onUnauthorized = _sesionVencida;
    String? guardado;
    try {
      guardado = await _storage.read(key: _clave);
    } catch (_) {}
    if (guardado == null) return null;
    api.token = guardado;
    try {
      return await api.me();
    } catch (_) {
      api.token = null;
      await _borrar();
      return null;
    }
  }

  /// Inicia sesión. Lanza [String] con un mensaje listo para mostrar si falla.
  Future<void> login(String username, String password) async {
    final api = ref.read(apiProvider);
    try {
      final (token, user) = await api.login(username.trim(), password);
      api.token = token;
      try {
        await _storage.write(key: _clave, value: token);
      } catch (_) {}
      state = AsyncData(user);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401) throw 'Usuario o contraseña incorrectos';
      if (code == 429) {
        throw 'Demasiados intentos. Espera unos minutos y vuelve a intentar';
      }
      throw 'No se pudo conectar con la API. ¿Está activa?';
    }
  }

  Future<void> logout() async {
    final api = ref.read(apiProvider);
    try {
      await api.logout(); // deja el evento en el log; si falla no importa
    } catch (_) {}
    await _cerrar();
  }

  void _sesionVencida() {
    if (state.value != null) _cerrar();
  }

  Future<void> _cerrar() async {
    ref.read(apiProvider).token = null;
    await _borrar();
    state = const AsyncData(null);
  }

  Future<void> _borrar() async {
    try {
      await _storage.delete(key: _clave);
    } catch (_) {}
  }
}

final authProvider = AsyncNotifierProvider<AuthViewModel, AppUser?>(AuthViewModel.new);
