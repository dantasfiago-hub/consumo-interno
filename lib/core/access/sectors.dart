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
bool sectorRequiresPrice(String? sector) =>
    sector != null && sectorKey(sector) == 'hortifruti';

String sectorLabel(String value) => sectors[sectorKey(value)] ?? value;
