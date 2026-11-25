import 'package:flutter/material.dart';

import '../../../../core/widgets/common.dart';
import '../../../../infrastructure/local/database.dart';
import '../domain/scale_label.dart';

class ScaleLabelFormatSettings extends StatefulWidget {
  final LocalDatabase database;

  const ScaleLabelFormatSettings({super.key, required this.database});

  @override
  State<ScaleLabelFormatSettings> createState() =>
      _ScaleLabelFormatSettingsState();
}

class _ScaleLabelFormatSettingsState extends State<ScaleLabelFormatSettings> {
  final prefix = TextEditingController(text: '2');
  final codeLength = TextEditingController(text: '6');
  final fieldLength = TextEditingController(text: '5');
  ScaleLabelNumericField numericField = ScaleLabelNumericField.totalCents;
  bool busy = false;
  String feedback = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stored = await widget.database.setting('scale_label_format');
    if (!mounted || stored == null) return;
    try {
      final format = ScaleLabelFormat.decode(stored);
      prefix.text = format.prefix;
      codeLength.text = format.internalCodeLength.toString();
      fieldLength.text = format.numericFieldLength.toString();
      setState(() => numericField = format.numericField);
    } catch (exception) {
      setState(() => feedback = friendlyError(exception));
    }
  }

  @override
  void dispose() {
    prefix.dispose();
    codeLength.dispose();
    fieldLength.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      busy = true;
      feedback = '';
    });
    try {
      final format = ScaleLabelFormat(
        prefix: prefix.text.trim(),
        internalCodeLength: int.parse(codeLength.text.trim()),
        numericFieldLength: int.parse(fieldLength.text.trim()),
        numericField: numericField,
      );
      format.validate();
      await widget.database.setSetting('scale_label_format', format.encode());
      if (mounted) setState(() => feedback = 'Formato salvo neste aparelho.');
    } catch (exception) {
      if (mounted) setState(() => feedback = friendlyError(exception));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Formato da etiqueta de balança',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Configuração local deste aparelho. O EAN-13 contém 12 dígitos de dados e um dígito verificador.',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 130,
                child: TextField(
                  controller: prefix,
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Prefixo',
                    counterText: '',
                  ),
                ),
              ),
              SizedBox(
                width: 170,
                child: TextField(
                  controller: codeLength,
                  maxLength: 2,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Dígitos do código',
                    counterText: '',
                  ),
                ),
              ),
              SizedBox(
                width: 170,
                child: TextField(
                  controller: fieldLength,
                  maxLength: 2,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Dígitos do campo',
                    counterText: '',
                  ),
                ),
              ),
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<ScaleLabelNumericField>(
                  initialValue: numericField,
                  decoration: const InputDecoration(
                    labelText: 'Conteúdo do campo',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: ScaleLabelNumericField.totalCents,
                      child: Text('Valor total (centavos)'),
                    ),
                    DropdownMenuItem(
                      value: ScaleLabelNumericField.weightGrams,
                      child: Text('Peso (gramas)'),
                    ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => numericField = value);
                          }
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: busy ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(busy ? 'Salvando...' : 'Salvar formato'),
              ),
              if (feedback.isNotEmpty) Text(feedback),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Padrão: prefixo 2 · código 6 · valor total 5 dígitos.'),
        ],
      ),
    ),
  );
}
