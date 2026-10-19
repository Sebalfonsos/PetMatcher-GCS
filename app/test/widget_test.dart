import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:petmatcher/main.dart';

void main() {
  testWidgets('Sin sesión la app muestra el login', (WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues({}); // sin token guardado
    await tester.pumpWidget(const ProviderScope(child: PetMatcherApp()));
    await tester.pump();
    // Deja correr las animaciones con retardo (flutter_animate) para que no
    // queden timers pendientes al terminar el test.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('PetMatcher'), findsWidgets);
  });
}
