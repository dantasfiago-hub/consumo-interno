import 'package:flutter/material.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/common.dart';

class AppearanceCard extends StatelessWidget {
  final ThemeController controller;
  const AppearanceCard({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Aparência', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Escolha o tema deste dispositivo. Automático acompanha o sistema.',
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Tema'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ThemeMode>(
                  key: const ValueKey('theme-selector'),
                  value: controller.mode,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('Automático'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text('Claro'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text('Escuro'),
                    ),
                  ],
                  onChanged: controller.saving
                      ? null
                      : (value) {
                          if (value != null) {
                            guarded(context, () => controller.setMode(value));
                          }
                        },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
