class ScaleLabelText {
  final int? weightMilli;
  final int? pricePerKgCents;
  final int? totalCents;
  final bool? isConsistent;

  const ScaleLabelText({
    this.weightMilli,
    this.pricePerKgCents,
    this.totalCents,
    this.isConsistent,
  });
}

class ScaleLabelTextParser {
  const ScaleLabelTextParser();

  ScaleLabelText parse(String text) {
    final lines = text.split(RegExp(r'[\r\n]+'));
    final weightLines = lines
        .where(
          (line) =>
              !RegExp(r'\(\s*T\s*\)', caseSensitive: false).hasMatch(line),
        )
        .toList();
    final liquidWeightLines = weightLines
        .where(
          (line) =>
              RegExp(r'\(\s*(?:L|1)\s*\)', caseSensitive: false).hasMatch(line),
        )
        .toList();
    final weightMilli =
        _findWeight(liquidWeightLines) ?? _findWeight(weightLines);
    final price = _findMoney(
      lines,
      RegExp(r'PRE[CÇ]O\s*/?\s*KG', caseSensitive: false),
    );
    final total = _findMoney(
      lines,
      RegExp(r'TOTAL\s*(?:R\s*\$)?\s*:?', caseSensitive: false),
    );

    bool? consistent;
    if (weightMilli != null && price != null && total != null) {
      final calculated =
          (BigInt.from(weightMilli) * BigInt.from(price) + BigInt.from(500)) ~/
          BigInt.from(1000);
      consistent = (calculated - BigInt.from(total)).abs() <= BigInt.one;
    }

    return ScaleLabelText(
      weightMilli: weightMilli,
      pricePerKgCents: price,
      totalCents: total,
      isConsistent: consistent,
    );
  }

  int? _findWeight(Iterable<String> lines) {
    final pattern = RegExp(
      r'(\d{1,6})\s*[,.]\s*(\d{1,3})\s*KG\b',
      caseSensitive: false,
    );
    for (final line in lines) {
      final match = pattern.firstMatch(line);
      if (match == null) continue;
      final whole = int.parse(match.group(1)!);
      final fraction = int.parse(match.group(2)!.padRight(3, '0'));
      return whole * 1000 + fraction;
    }
    return null;
  }

  int? _findMoney(Iterable<String> lines, RegExp label) {
    final amount = RegExp(r'(\d{1,6})\s*[,.]\s*(\d{2})');
    for (final line in lines) {
      if (!label.hasMatch(line)) continue;
      final match = amount.firstMatch(line);
      if (match == null) continue;
      return int.parse(match.group(1)!) * 100 + int.parse(match.group(2)!);
    }
    return null;
  }
}
