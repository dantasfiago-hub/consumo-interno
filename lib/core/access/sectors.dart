const sectors = {
  'hortifruti': 'Horti Fruti',
  'cozinha': 'Cozinha',
  'padaria': 'Padaria',
};
String? sectorKey(String value) =>
    switch (value.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '')) {
      'hortifruti' => 'hortifruti',
      'cozinha' => 'cozinha',
      'padaria' => 'padaria',
      _ => null,
    };
/// Only Horti Fruti records a price. Cozinha and Padaria record quantity only,
/// so their items may have a total of zero. An unknown sector keeps the strict
/// rule.
bool sectorRequiresPrice(String? sector) {
  final key = sector == null ? null : sectorKey(sector);
  return key != 'cozinha' && key != 'padaria';
}

String sectorLabel(String value) => sectors[sectorKey(value)] ?? value;
