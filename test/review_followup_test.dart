import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:consumo_interno/core/access/admin_guard.dart';
import 'package:consumo_interno/core/formatting/search.dart';
import 'package:consumo_interno/core/widgets/common.dart';
import 'package:consumo_interno/features/consumption/domain/consumption.dart';
import 'package:consumo_interno/features/exports/domain/export.dart';

void main() {
  final salt = base64Encode(List.generate(16, (i) => i));

  test('PBKDF2 respeita o número de iterações informado (vetores do hashlib)', () {
    expect(
      deriveAdminPassword({
        'password': 'a',
        'salt': salt,
        'iterations': '1000',
      }),
      '8ET/fPusEzigul2/gBiNtfAq4czE3vHQAozMQSoupg8=',
    );
    expect(
      deriveAdminPassword({
        'password': 'a',
        'salt': salt,
        'iterations': '310000',
      }),
      'V8fI+/WkWh5pRgLOncTK5pNg4CsWz/6An3RiamVIhsA=',
    );
  });

  test('Registro antigo sem iterações continua usando 120 mil', () {
    expect(
      deriveAdminPassword({'password': 'a', 'salt': salt}),
      'gNQMfiwu11bDbW/6lJnBR/CP2ZKdylDo67RFaA/ovhs=',
    );
  });

  test('Busca ignora acentos e maiúsculas', () {
    expect(normalizeSearch('Maçã Verde'), 'maca verde');
    expect(normalizeSearch('PÃO DE QUEIJO'), 'pao de queijo');
    expect(normalizeSearch('maca'), 'maca');
    expect(
      normalizeSearch('1001 Maçã').contains(normalizeSearch('MACA')),
      true,
    );
  });

  test('Mensagens de erro não exibem prefixos técnicos', () {
    expect(friendlyError(StateError('Produto indisponível.')), 'Produto indisponível.');
    expect(friendlyError(const FormatException('Valor inválido.')), 'Valor inválido.');
    expect(friendlyError(Exception('Falhou')), 'Falhou');
    expect(friendlyError(TimeoutException('x')), contains('Tempo esgotado'));
  });

  Consumption sample(String sector, int total) => Consumption(
    id: 'c1',
    date: '2026-10-05',
    createdAt: '2026-10-05T12:00:00Z',
    operatorName: sector,
    sector: sector,
    note: '',
    items: [
      ConsumptionItem(
        id: 'i1',
        productId: 'p1',
        code: '000125',
        description: 'Produto',
        unit: 'UN',
        amount: 3000,
        totalCents: total,
      ),
    ],
  );

  test('Cozinha e Padaria aceitam item sem valor; Horti Fruti exige valor', () {
    validateConsumption(sample('cozinha', 0));
    validateConsumption(sample('padaria', 0));
    validateConsumption(sample('cozinha', 250));
    validateConsumption(sample('hortifruti', 250));
    expect(
      () => validateConsumption(sample('hortifruti', 0)),
      throwsFormatException,
    );
    expect(
      () => validateConsumption(sample('padaria', -1)),
      throwsFormatException,
    );
  });

  test('Preço unitário é zero quando não há valor e continua exigindo quantidade', () {
    expect(unitPrice4(BigInt.zero, BigInt.from(3000)), BigInt.zero);
    expect(() => unitPrice4(BigInt.zero, BigInt.zero), throwsFormatException);
    expect(() => unitPrice4(BigInt.from(-1), BigInt.one), throwsFormatException);
  });
}
