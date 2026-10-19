import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:petmatcher/model/adhd.dart';
import 'package:petmatcher/model/auth_models.dart';
import 'package:petmatcher/model/models.dart';

/// Base URL de la API. En web/desktop apunta a localhost; en emulador Android
/// se usa 10.0.2.2 para alcanzar el host. Override con --dart-define=API_BASE_URL=...
String _defaultBaseUrl() {
  const fromEnv = String.fromEnvironment('API_BASE_URL');
  if (fromEnv.isNotEmpty) return fromEnv;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }
  return 'http://localhost:8000';
}

class PetMatcherApi {
  final Dio _dio;

  /// Token de sesión (JWT). Lo fija el AuthViewModel; se manda en cada petición.
  String? token;

  /// Se llama cuando la API responde 401 a una petición autenticada (sesión vencida,
  /// usuario desactivado o contraseña cambiada). El AuthViewModel cierra la sesión.
  void Function()? onUnauthorized;

  PetMatcherApi([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: _defaultBaseUrl(),
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) {
        if (token != null) o.headers['Authorization'] = 'Bearer $token';
        h.next(o);
      },
      onError: (e, h) {
        // El 401 del propio login es "credenciales incorrectas", no sesión vencida.
        if (e.response?.statusCode == 401 && e.requestOptions.path != '/auth/login') {
          onUnauthorized?.call();
        }
        h.next(e);
      },
    ));
  }

  // ---------- Sesión ----------

  /// Devuelve (token, usuario). Lanza DioException con 401/429 si falla.
  Future<(String, AppUser)> login(String username, String password) async {
    final r = await _dio.post('/auth/login',
        data: {'username': username, 'password': password});
    final d = r.data as Map<String, dynamic>;
    return (d['access_token'] as String, AppUser.fromJson(d['user'] as Map<String, dynamic>));
  }

  Future<AppUser> me() async {
    final r = await _dio.get('/auth/me');
    return AppUser.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> logout() => _dio.post('/auth/logout');

  Future<void> changePassword(String actual, String nueva) =>
      _dio.post('/auth/password', data: {'actual': actual, 'nueva': nueva});

  // ---------- Administración (rol admin) ----------

  Future<List<AppUser>> listUsers() async {
    final r = await _dio.get('/admin/users');
    return (r.data as List).map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AppUser> createUser(
      {required String username, required String nombre, required String password, required String rol}) async {
    final r = await _dio.post('/admin/users',
        data: {'username': username, 'nombre': nombre, 'password': password, 'rol': rol});
    return AppUser.fromJson(r.data as Map<String, dynamic>);
  }

  /// Solo se mandan los campos que no son null.
  Future<AppUser> updateUser(String id,
      {String? nombre, String? rol, bool? activo, String? password}) async {
    final r = await _dio.put('/admin/users/$id', data: {
      'nombre': ?nombre,
      'rol': ?rol,
      'activo': ?activo,
      'password': ?password,
    });
    return AppUser.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> deleteUser(String id) => _dio.delete('/admin/users/$id');

  Future<AuditPage> listAudit(AuditFilter f, {int offset = 0, int limit = 50}) async {
    final r = await _dio.get('/admin/audit', queryParameters: {
      'username': ?f.username,
      'accion': ?f.accion,
      'exito': ?f.exito,
      'offset': offset,
      'limit': limit,
    });
    return AuditPage.fromJson(r.data as Map<String, dynamic>);
  }

  Future<bool> health() async {
    try {
      final r = await _dio.get('/health');
      return r.data['models_loaded'] == true;
    } catch (_) {
      return false;
    }
  }

  // ---------- Animales ----------

  Future<List<Animal>> listAnimals() async {
    final r = await _dio.get('/animals');
    return (r.data as List).map((e) => Animal.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Animal> createAnimal(Animal a) async {
    final r = await _dio.post('/animals', data: a.toApiBody());
    return Animal.fromJson(r.data as Map<String, dynamic>);
  }

  Future<Animal> updateAnimal(Animal a) async {
    final r = await _dio.put('/animals/${a.id}', data: a.toApiBody());
    return Animal.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> deleteAnimal(String id) => _dio.delete('/animals/$id');

  Future<Animal> assignAnimal(String animalId, String patientId) async {
    final r = await _dio.post('/animals/$animalId/assign', data: {'patient_id': patientId});
    return Animal.fromJson(r.data as Map<String, dynamic>);
  }

  Future<Animal> releaseAnimal(String animalId) async {
    final r = await _dio.post('/animals/$animalId/release');
    return Animal.fromJson(r.data as Map<String, dynamic>);
  }

  // ---------- Test ADHD-RS ----------

  Future<AdhdCuestionario> getCuestionarioAdhd() async {
    final r = await _dio.get('/adhd-rs/cuestionario');
    return AdhdCuestionario.fromJson(r.data as Map<String, dynamic>);
  }

  /// Puntúa las 18 respuestas (0-3) en la API: única fuente de la puntuación.
  Future<PerfilAdhd> scoreAdhd(List<int> respuestas) async {
    final r = await _dio.post('/adhd-rs/score', data: {'respuestas_adhd': respuestas});
    return PerfilAdhd.fromJson(r.data as Map<String, dynamic>);
  }

  // ---------- Pacientes ----------

  /// Crea el paciente en la BD y devuelve su id asignado por el backend.
  Future<String> createPatient(Patient p) async {
    final r = await _dio.post('/patients', data: {'nombre': p.nombre, ...p.toFeatures()});
    return r.data['id'] as String;
  }

  Future<List<Patient>> listPatients() async {
    final r = await _dio.get('/patients');
    return (r.data as List).map((e) => Patient.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Patient> updatePatient(Patient p) async {
    final r = await _dio.put('/patients/${p.id}', data: {'nombre': p.nombre, ...p.toFeatures()});
    return Patient.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> deletePatient(String id) => _dio.delete('/patients/$id');

  // ---------- Rankings y explicaciones guardados ----------

  /// Ranking guardado del paciente (con su explicación), o null si nunca se hizo.
  Future<RankingGuardado?> getRanking(String patientId) async {
    final r = await _dio.get('/patients/$patientId/ranking');
    if (r.data == null) return null;
    return RankingGuardado.fromJson(r.data as Map<String, dynamic>);
  }

  /// Genera el ranking ahora (con los animales disponibles) y lo guarda. Si sale
  /// idéntico al guardado, la API conserva el anterior y responde `sin_cambios`.
  Future<RankingGuardado> createRanking(String patientId) async {
    final r = await _dio.post('/patients/$patientId/ranking');
    return RankingGuardado.fromJson(r.data as Map<String, dynamic>);
  }

  /// Orientación del LLM sobre el ranking guardado, emitida a medida que se genera.
  /// La API la guarda al terminar; responde 409 si ese ranking ya tiene una.
  ///
  /// NDJSON (un objeto JSON por línea):
  ///   {"tipo":"evidencia","datos":{...}}  una vez, inmediata
  ///   {"tipo":"texto","delta":"..."}      muchas
  ///   {"tipo":"error","detalle":"..."}    si el LLM no está o falla
  ///   {"tipo":"fin","aviso":"..."}        una vez
  Stream<Map<String, dynamic>> explainRankingStream(String rankingId) async* {
    final r = await _dio.post<ResponseBody>(
      '/rankings/$rankingId/explicacion/stream',
      options: Options(
        responseType: ResponseType.stream,
        // La generación completa puede pasar el minuto.
        receiveTimeout: const Duration(minutes: 5),
      ),
    );

    // Los chunks TCP no respetan los límites de línea: se acumula en un buffer y
    // se emite solo cuando hay una línea completa. Y se decodifica en UTF-8
    // explícito, para no romper tildes y ñ.
    var buffer = '';
    await for (final chunk in r.data!.stream) {
      buffer += utf8.decode(chunk, allowMalformed: true);
      var corte = buffer.indexOf('\n');
      while (corte >= 0) {
        final linea = buffer.substring(0, corte).trim();
        buffer = buffer.substring(corte + 1);
        if (linea.isNotEmpty) {
          yield jsonDecode(linea) as Map<String, dynamic>;
        }
        corte = buffer.indexOf('\n');
      }
    }
    final resto = buffer.trim();
    if (resto.isNotEmpty) {
      yield jsonDecode(resto) as Map<String, dynamic>;
    }
  }
}

final apiProvider = Provider<PetMatcherApi>((ref) => PetMatcherApi());
