import 'dart:convert';
import 'package:flutter/material.dart';
import '../../domain/models.dart';

void message(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
Future<void> guarded(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      message(context, e.toString().replaceFirst('Bad state: ', ''));
    }
  }
}

class Photo extends StatelessWidget {
  final Product? product;
  final double size;
  const Photo(this.product, {super.key, this.size = 64});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: product?.photo == null
          ? Icon(
              Icons.inventory_2_outlined,
              size: size * .4,
              color: Theme.of(context).colorScheme.primary,
            )
          : Image.memory(
              base64Decode(product!.photo!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined),
            ),
    ),
  );
}

class UnitBadge extends StatelessWidget {
  final String unit;
  const UnitBadge(this.unit, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: unit == 'KG'
          ? Theme.of(context).colorScheme.secondaryContainer
          : Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      unit,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: unit == 'KG'
            ? Theme.of(context).colorScheme.onSecondaryContainer
            : Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    ),
  );
}

class PageTitle extends StatelessWidget {
  final String title, subtitle;
  final Widget? action;
  const PageTitle(this.title, this.subtitle, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Wrap(
      spacing: 24,
      runSpacing: 14,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (action != null) action!,
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  final String title, description;
  final Widget? action;
  const EmptyState(this.title, this.description, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 58,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(description, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}

Future<String?> reasonDialog(BuildContext context) => showTextPrompt(
  context,
  title: 'Cancelar lançamento',
  label: 'Justificativa',
  description: 'O registro será mantido no histórico como cancelado.',
  maxLength: 300,
);

Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  required String label,
  required String description,
  int maxLength = 200,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextPrompt(
    title: title,
    label: label,
    description: description,
    maxLength: maxLength,
  ),
);

class _TextPrompt extends StatefulWidget {
  final String title, label, description;
  final int maxLength;
  const _TextPrompt({
    required this.title,
    required this.label,
    required this.description,
    required this.maxLength,
  });
  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  final text = TextEditingController();
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.description),
          const SizedBox(height: 12),
          TextField(
            controller: text,
            maxLength: widget.maxLength,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: widget.label,
              helperText: 'Mínimo de 3 caracteres.',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('Voltar'),
      ),
      FilledButton(
        onPressed: text.text.trim().length < 3
            ? null
            : () => Navigator.pop(context, text.text.trim()),
        child: Text('Confirmar'),
      ),
    ],
  );
}
