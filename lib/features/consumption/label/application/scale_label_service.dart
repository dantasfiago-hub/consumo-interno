import 'package:uuid/uuid.dart';

import '../../../../core/formatting/sum_expression.dart';
import '../../../../domain/models.dart';
import '../domain/scale_label.dart';
import '../domain/scale_label_text.dart';

class ScaleLabelResolution {
  final Product product;
  final ScaleLabel label;
  final ScaleLabelText? printedText;
  final int? suggestedWeightMilli;
  final String? weightSource;

  const ScaleLabelResolution({
    required this.product,
    required this.label,
    required this.printedText,
    required this.suggestedWeightMilli,
    required this.weightSource,
  });
}

class ScaleLabelService {
  final ScaleLabelParser parser;
  final ScaleLabelTextParser textParser;

  const ScaleLabelService({
    this.parser = const ScaleLabelParser(),
    this.textParser = const ScaleLabelTextParser(),
  });

  ScaleLabel parseBarcode(String barcode) => parser.parse(barcode);

  ScaleLabelResolution resolve({
    required String barcode,
    required List<Product> products,
    required String sector,
    String? printedText,
  }) => resolveLabel(
    label: parseBarcode(barcode),
    products: products,
    sector: sector,
    printedText: printedText,
  );

  ScaleLabelResolution resolveLabel({
    required ScaleLabel label,
    required List<Product> products,
    required String sector,
    String? printedText,
  }) {
    final matches = products
        .where((product) => _sameCode(product.code, label.internalCode))
        .toList();
    final inSector = matches
        .where((product) => product.sectorIds.contains(sector))
        .toList();
    final active = inSector.where((product) => product.active).toList();
    if (active.isEmpty) {
      if (inSector.isNotEmpty) {
        throw const FormatException(
          'O produto da etiqueta está inativo neste setor.',
        );
      }
      throw const FormatException(
        'O produto da etiqueta não está cadastrado neste setor.',
      );
    }
    if (active.length > 1) {
      throw const FormatException(
        'Há mais de um produto ativo com esse código neste setor.',
      );
    }

    final reading = printedText == null || printedText.trim().isEmpty
        ? null
        : textParser.parse(printedText);
    final product = active.single;
    int? weight = label.weightMilli;
    String? source = weight == null ? null : 'código de barras';
    if (product.unit == 'KG' &&
        weight == null &&
        reading?.weightMilli != null) {
      weight = reading!.weightMilli;
      source = 'lido da etiqueta';
    }
    if (product.unit == 'KG' && weight == null) {
      final total = label.totalCents ?? reading?.totalCents;
      final price = reading?.pricePerKgCents;
      if (total != null && price != null && price > 0) {
        weight =
            ((BigInt.from(total) * BigInt.from(1000) * BigInt.two +
                        BigInt.from(price)) ~/
                    (BigInt.from(price) * BigInt.two))
                .toInt();
        source = 'calculado';
      }
    }
    return ScaleLabelResolution(
      product: product,
      label: label,
      printedText: reading,
      suggestedWeightMilli: product.unit == 'KG' ? weight : null,
      weightSource: product.unit == 'KG' ? source : null,
    );
  }

  ConsumptionItem createItem({
    required ScaleLabelResolution resolution,
    required String whole,
    required String grams,
    required String total,
    required bool requiresPrice,
    String? itemId,
  }) {
    final product = resolution.product;
    final amount = product.unit == 'KG'
        ? parseSumWeightParts(whole, grams)
        : parseSumQuantity(whole, product.unit);
    final totalCents = requiresPrice ? parseSumScaled(total, 2) : 0;
    return ConsumptionItem(
      id: itemId ?? const Uuid().v4(),
      productId: product.id,
      code: product.code,
      description: product.description,
      unit: product.unit,
      amount: amount,
      totalCents: totalCents,
    );
  }

  ConsumptionItem combine(ConsumptionItem existing, ConsumptionItem added) {
    if (existing.productId != added.productId ||
        existing.unit != added.unit ||
        existing.amount > 999999999999 - added.amount ||
        existing.totalCents > 999999999999 - added.totalCents) {
      throw const FormatException(
        'Não foi possível somar os valores deste produto.',
      );
    }
    return ConsumptionItem(
      id: existing.id,
      productId: existing.productId,
      code: existing.code,
      description: existing.description,
      unit: existing.unit,
      amount: existing.amount + added.amount,
      totalCents: existing.totalCents + added.totalCents,
    );
  }

  bool _sameCode(String left, String right) =>
      _withoutLeadingZeros(left) == _withoutLeadingZeros(right);

  String _withoutLeadingZeros(String code) {
    final stripped = code.replaceFirst(RegExp(r'^0+'), '');
    return stripped.isEmpty ? '0' : stripped;
  }
}
