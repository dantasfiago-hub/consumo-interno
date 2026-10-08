// Standalone Dart regression suite: dart run test/sum_expression_checks.dart.
import '../lib/core/formatting/sum_expression.dart';

void main() {
  var checks = 0;
  void equals(int actual, int expected) {
    checks++;
    if (actual != expected) throw StateError('$actual != $expected');
  }

  void rejects(void Function() action) {
    checks++;
    try {
      action();
    } on FormatException {
      return;
    }
    throw StateError('Expressão inválida foi aceita');
  }

  equals(parseSumScaled('10+20+5', 0), 35);
  equals(parseSumScaled(' 10 + 20 + 5 ', 0), 35);
  equals(parseSumScaled('1,5+2.3', 2), 380);
  equals(parseSumScaled('0,1+0,2', 2), 30);
  equals(parseSumScaled('001+002', 0), 3);
  equals(parseSumScaled('0+0', 0, allowZero: true), 0);
  equals(parseSumScaled('999999999998+1', 0), 999999999999);
  equals(parseSumQuantity('10+20+5', 'UN'), 35000);
  equals(parseSumQuantity('1,5+2,3', 'KG'), 3800);
  equals(parseSumWeightParts('2+1', '200+150'), 3350);
  equals(parseSumWeightParts('', '500'), 500);
  equals(parseSumWeightParts('1', ''), 1000);
  equals(parseSumWeightParts('999999999', '999'), 999999999999);
  for (final input in [
    '',
    '10+',
    '+10',
    '10++20',
    '=10+20',
    '-1',
    '2*3',
    '1e3',
    '1 0+2',
    'NaN',
    '1,000.00',
    '0+0',
    '999999999999+1',
    '999999999999999999999999999',
  ]) {
    rejects(() => parseSumScaled(input, 2));
  }
  rejects(() => parseSumScaled('1,001+2', 2));
  rejects(() => parseSumQuantity('1,5+2', 'UN'));
  rejects(() => parseSumQuantity('1', 'INVALID'));
  rejects(() => parseSumWeightParts('1', '600+500'));
  rejects(() => parseSumWeightParts('1+', '0'));
  rejects(() => parseSumWeightParts('', ''));
  rejects(() => parseSumWeightParts('1,5', '0'));
  rejects(() => parseSumScaled(List.filled(101, '1').join('+'), 0));
  // Many exact fractional additions must not accumulate floating-point error.
  equals(parseSumScaled(List.filled(40, '0,01').join('+'), 2), 40);
  print(
    'PASS: $checks verificações de soma, precisão, limites e persistência.',
  );
}
