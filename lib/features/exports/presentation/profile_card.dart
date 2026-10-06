import 'package:flutter/material.dart';
import '../../../app/app_state.dart';
import '../../../core/files/file_service.dart';
import '../../../core/widgets/common.dart';
import '../domain/export.dart';
import '../data/vr_master_serializer.dart';

class ExportProfileCard extends StatefulWidget {
  final AppState state;
  const ExportProfileCard({super.key, required this.state});
  @override
  State<ExportProfileCard> createState() => _ExportProfileCardState();
}

class _ExportProfileCardState extends State<ExportProfileCard> {
  late ExportProfile original;
  late String separator, decimal, encoding, lineEnding;
  late bool header, bom, fixedPrice, validated;
  late List<String> order;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _read();
  }

  void _read() {
    original = widget.state.exports.profile.forSector('hortifruti');
    separator = original.separator;
    decimal = original.decimal;
    encoding = original.encoding;
    lineEnding = original.lineEnding;
    header = original.header;
    bom = original.bom;
    fixedPrice = original.fixedPrice;
    validated = original.validated;
    order = List.of(original.order);
  }

  @override
  void didUpdateWidget(covariant ExportProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (original.version != widget.state.exports.profile.version) _read();
  }

  ExportProfile get draft => ExportProfile(
    version: original.version,
    separator: separator,
    decimal: decimal,
    encoding: encoding,
    lineEnding: lineEnding,
    header: header,
    bom: bom,
    fixedPrice: fixedPrice,
    validated: validated,
    order: order,
  );
  void change(VoidCallback update) => setState(() {
    update();
    validated = false;
  });
  @override
  Widget build(BuildContext context) {
    final editable = widget.state.canManage && !busy;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Perfil de exportação VR Master',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Cozinha e Padaria exportam somente código interno e quantidade, nesta ordem. Os quatro campos abaixo valem para Horti Fruti. Separador e demais opções valem para todos os setores; confira os layouts no VR Master.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _choice(
                  'Separador',
                  separator,
                  {
                    ';': 'Ponto e vírgula',
                    '|': 'Barra vertical',
                    '\t': 'Tabulação',
                  },
                  editable ? (v) => change(() => separator = v) : null,
                ),
                _choice('Decimal', decimal, {
                  ',': 'Vírgula',
                  '.': 'Ponto',
                }, editable ? (v) => change(() => decimal = v) : null),
                _choice(
                  'Codificação',
                  encoding,
                  {'UTF8': 'UTF-8', 'LATIN1': 'Latin-1'},
                  editable
                      ? (v) => change(() {
                          encoding = v;
                          if (v != 'UTF8') bom = false;
                        })
                      : null,
                ),
                _choice(
                  'Fim de linha',
                  lineEnding,
                  {'CRLF': 'Windows (CRLF)', 'LF': 'LF'},
                  editable ? (v) => change(() => lineEnding = v) : null,
                ),
                for (var i = 0; i < 4; i++)
                  _choice(
                    'Campo ${i + 1}',
                    order[i],
                    {
                      'code': 'Código interno',
                      'quantity': 'Quantidade',
                      'unit': 'Unidade = 1',
                      'unit_price': 'Valor unitário',
                    },
                    editable
                        ? (v) => change(() {
                            final old = order.indexOf(v);
                            final previous = order[i];
                            order[i] = v;
                            if (old >= 0) order[old] = previous;
                          })
                        : null,
                  ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Incluir cabeçalho'),
              value: header,
              onChanged: editable ? (v) => change(() => header = v!) : null,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Preço sempre com quatro casas'),
              value: fixedPrice,
              onChanged: editable ? (v) => change(() => fixedPrice = v!) : null,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Incluir BOM em UTF-8'),
              value: bom,
              onChanged: editable && encoding == 'UTF8'
                  ? (v) => change(() => bom = v!)
                  : null,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Conferi o formato e a importação na instalação do VR Master',
              ),
              value: validated,
              onChanged: editable
                  ? (v) => setState(() => validated = v!)
                  : null,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.save_outlined),
                  label: Text(busy ? 'Salvando...' : 'Salvar perfil'),
                  onPressed: !editable
                      ? null
                      : () async {
                          setState(() => busy = true);
                          try {
                            await widget.state.exports.save(draft);
                            await widget.state.load();
                            if (context.mounted) {
                              message(
                                context,
                                'Perfil salvo. Lotes antigos mantêm seu formato.',
                              );
                            }
                          } catch (e) {
                            if (context.mounted) message(context, '$e');
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Salvar exemplo fictício'),
                  onPressed: busy
                      ? null
                      : () => guarded(context, () async {
                          final sample = ExportRow(
                            code: '000125',
                            description: 'Exemplo fictício',
                            productId: 'sample',
                            measure: 'UN',
                            quantityMilli: BigInt.from(5000),
                            totalCents: BigInt.from(15357),
                          );
                          await saveBytes(
                            'EXEMPLO_FICTICIO_VR.txt',
                            serializeExport([sample], draft),
                          );
                        }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Perfil v${original.version} · ${original.validated ? 'Conferido pelo administrador' : 'Aguardando conferência'}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _choice(
    String label,
    String value,
    Map<String, String> options,
    void Function(String)? update,
  ) => SizedBox(
    width: 220,
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      isExpanded: true,
      items: options.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: update == null ? null : (v) => update(v!),
    ),
  );
}
