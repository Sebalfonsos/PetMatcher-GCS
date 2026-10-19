import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:petmatcher/model/api_client.dart';
import 'package:petmatcher/model/auth_models.dart';

/// VIEWMODEL — Lista de usuarios (solo admin) y sus mutaciones.
class UsersViewModel extends AsyncNotifier<List<AppUser>> {
  @override
  Future<List<AppUser>> build() => ref.read(apiProvider).listUsers();

  Future<void> refreshList() async {
    state = await AsyncValue.guard(() => ref.read(apiProvider).listUsers());
  }

  Future<void> create({
    required String username,
    required String nombre,
    required String password,
    required String rol,
  }) async {
    await ref.read(apiProvider).createUser(
        username: username, nombre: nombre, password: password, rol: rol);
    await refreshList();
  }

  Future<void> edit(String id,
      {String? nombre, String? rol, bool? activo, String? password}) async {
    await ref.read(apiProvider).updateUser(id,
        nombre: nombre, rol: rol, activo: activo, password: password);
    await refreshList();
  }

  Future<void> remove(String id) async {
    await ref.read(apiProvider).deleteUser(id);
    await refreshList();
  }
}

final usersProvider =
    AsyncNotifierProvider<UsersViewModel, List<AppUser>>(UsersViewModel.new);

/// Estado del log paginado: eventos cargados hasta ahora y el total que hay en el servidor.
class AuditState {
  final List<AuditEvent> items;
  final int total;
  const AuditState(this.items, this.total);
  bool get hayMas => items.length < total;
}

/// VIEWMODEL — Log de eventos, filtrado. Una instancia por filtro (autoDispose).
class AuditViewModel extends AsyncNotifier<AuditState> {
  final AuditFilter filter;
  AuditViewModel(this.filter);

  @override
  Future<AuditState> build() async {
    final p = await ref.read(apiProvider).listAudit(filter);
    return AuditState(p.items, p.total);
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(build);
  }

  Future<void> loadMore() async {
    final actual = state.value;
    if (actual == null || !actual.hayMas) return;
    final p = await ref.read(apiProvider).listAudit(filter, offset: actual.items.length);
    state = AsyncData(AuditState([...actual.items, ...p.items], p.total));
  }
}

final auditProvider = AsyncNotifierProvider.autoDispose
    .family<AuditViewModel, AuditState, AuditFilter>(AuditViewModel.new);
