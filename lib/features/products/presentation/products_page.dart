import 'package:flutter/material.dart';

import '../../../core/access/sectors.dart';
import '../../../app/app_state.dart';
import '../../../domain/models.dart';
import '../../../infrastructure/local/database.dart';
import '../data/photo_service.dart';
import '../../../core/widgets/common.dart';

class ProductsPage extends StatefulWidget {
  final AppState state;
  const ProductsPage({super.key, required this.state});
  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  String search = '', unit = '';
  bool showInactive = false, onlyFavorites = false;
  @override
  Widget build(BuildContext context) {
    if (!widget.state.canManage) {
      return const Center(child: Text('Acesso exclusivo do administrador.'));
    }
    final products = widget.state.products
        .where(
          (p) =>
              (showInactive || p.active) &&
              (!onlyFavorites || widget.state.favorites.contains(p.id)) &&
              '${p.code} ${p.description}'.toLowerCase().contains(
                search.toLowerCase(),
              ) &&
              (unit.isEmpty || p.unit == unit),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageTitle(
            'Produtos',
            'Encontre pelo nome, código ou foto.',
            action: widget.state.canManage
                ? FilledButton.icon(
                    onPressed: () => showProductEditor(context, widget.state),
                    icon: Icon(Icons.add),
                    label: Text('Cadastrar produto'),
                  )
                : null,
          ),
          TextField(
            onChanged: (v) => setState(() => search = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar código ou descrição',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final u in ['', 'UN', 'KG'])
                ChoiceChip(
                  label: Text(u.isEmpty ? 'Todos' : u),
                  selected: unit == u,
                  onSelected: (_) => setState(() => unit = u),
                ),
              FilterChip(
                label: const Text('Favoritos'),
                selected: onlyFavorites,
                onSelected: (v) => setState(() => onlyFavorites = v),
              ),
              FilterChip(
                label: Text('Incluir inativos'),
                selected: showInactive,
                onSelected: (v) => setState(() => showInactive = v),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: products.isEmpty
                ? const EmptyState(
                    'Nenhum produto encontrado',
                    'Cadastre os produtos e adicione fotos para facilitar a identificação.',
                  )
                : LayoutBuilder(
                    builder: (context, c) => GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: (c.maxWidth / 230).floor().clamp(1, 5),
                        mainAxisExtent: 260,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final p = products[index];
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => showProductEditor(
                              context,
                              widget.state,
                              product: p,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Stack(
                                      children: [
                                        Center(child: Photo(p, size: 120)),
                                        Align(
                                          alignment: Alignment.topRight,
                                          child: IconButton(
                                            tooltip:
                                                widget.state.favorites.contains(
                                                  p.id,
                                                )
                                                ? 'Remover favorito'
                                                : 'Favoritar produto',
                                            icon: Icon(
                                              widget.state.favorites.contains(
                                                    p.id,
                                                  )
                                                  ? Icons.star
                                                  : Icons.star_border,
                                            ),
                                            onPressed: () => guarded(
                                              context,
                                              () => widget.state.toggleFavorite(
                                                p.id,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          p.code,
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      UnitBadge(p.unit),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    p.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (!p.active)
                                    Text(
                                      'Inativo',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

Future<void> showProductEditor(
  BuildContext context,
  AppState state, {
  Product? product,
}) => showDialog<void>(
  context: context,
  builder: (_) => ProductEditor(state: state, product: product),
);

class ProductEditor extends StatefulWidget {
  final AppState state;
  final Product? product;
  const ProductEditor({super.key, required this.state, this.product});
  @override
  State<ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<ProductEditor> {
  late final code = TextEditingController(text: widget.product?.code ?? '');
  late final description = TextEditingController(
    text: widget.product?.description ?? '',
  );
  late String unit = widget.product?.unit ?? 'UN';
  late Set<String> assignedSectors = {...?widget.product?.sectorIds};
  late String? photo = widget.product?.photo;
  late bool active = widget.product?.active ?? true;
  bool busy = false;
  String error = '';
  @override
  void dispose() {
    code.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget.state.canManage;
    return AlertDialog(
      title: Text(widget.product == null ? 'Cadastrar produto' : 'Produto'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Photo(
                Product(
                  id: '',
                  code: '',
                  description: '',
                  unit: unit,
                  photo: photo,
                ),
                size: 120,
              ),
              if (editable)
                Wrap(
                  children: [
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              setState(() => busy = true);
                              try {
                                final result = await choosePhoto();
                                if (mounted && result != null) {
                                  setState(() {
                                    photo = result;
                                    error = '';
                                  });
                                }
                              } catch (e) {
                                if (mounted) {
                                  setState(() => error = e.toString());
                                }
                              } finally {
                                if (mounted) setState(() => busy = false);
                              }
                            },
                      icon: Icon(Icons.add_photo_alternate_outlined),
                      label: Text('Selecionar foto'),
                    ),
                    if (photo != null)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => photo = null),
                        child: Text('Remover'),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              TextField(
                controller: code,
                enabled: editable,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Código interno'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                enabled: editable,
                maxLength: 150,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: unit,
                decoration: const InputDecoration(labelText: 'Unidade'),
                items: const [
                  DropdownMenuItem(value: 'UN', child: Text('UN — Unidade')),
                  DropdownMenuItem(value: 'KG', child: Text('KG — Quilograma')),
                ],
                onChanged: editable ? (v) => setState(() => unit = v!) : null,
              ),
              const Text('Setores com acesso a este produto'),
              for (final entry in sectors.entries)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value),
                  value: assignedSectors.contains(entry.key),
                  onChanged: editable
                      ? (v) => setState(() {
                          if (v!) {
                            assignedSectors.add(entry.key);
                          } else {
                            assignedSectors.remove(entry.key);
                          }
                        })
                      : null,
                ),
              if (assignedSectors.isEmpty)
                const Text(
                  'Sem setor: o produto fica invisível para os funcionários.',
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Produto ativo'),
                value: active,
                onChanged: editable ? (v) => setState(() => active = v) : null,
              ),
              if (error.isNotEmpty)
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: Text('Fechar'),
        ),
        if (editable)
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      await widget.state.saveProduct(
                        Product(
                          id: widget.product?.id ?? uuid.v4(),
                          code: code.text.trim(),
                          description: description.text.trim(),
                          unit: unit,
                          sectorIds: assignedSectors.toList()..sort(),
                          photo: photo,
                          photoHash: photo == widget.product?.photo
                              ? widget.product?.photoHash
                              : null,
                          active: active,
                          version: (widget.product?.version ?? 0) + 1,
                        ),
                        expectedVersion: widget.product?.version ?? 0,
                      );
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (mounted) {
                        setState(() {
                          error = e.toString().contains('UNIQUE')
                              ? 'Já existe um produto com esse código.'
                              : e.toString();
                          busy = false;
                        });
                      }
                    }
                  },
            child: Text(busy ? 'Salvando...' : 'Salvar produto'),
          ),
      ],
    );
  }
}
