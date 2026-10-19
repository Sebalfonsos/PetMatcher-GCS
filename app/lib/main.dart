import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:petmatcher/viewmodel/theme_viewmodel.dart';
import 'package:petmatcher/view/router.dart';
import 'package:petmatcher/view/theme/theme.dart';

void main() {
  runApp(const ProviderScope(child: PetMatcherApp()));
}

class PetMatcherApp extends ConsumerWidget {
  const PetMatcherApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'PetMatcher',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
