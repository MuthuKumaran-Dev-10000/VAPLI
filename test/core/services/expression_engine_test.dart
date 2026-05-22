import 'package:flutter_test/flutter_test.dart';
import 'package:lubrication_indicator/core/services/expression_engine.dart';

void main() {
  group('ExpressionEngine.evaluate', () {
    test('evaluates basic token expression with numeric param ids', () {
      final value = ExpressionEngine.evaluate(
        r'${1779440412221}+${1779440441154}',
        variables: {
          '1779440412221': 10,
          '1779440441154': 5,
        },
      );
      expect(value, 15);
    });

    test('evaluates mixed precedence and parentheses', () {
      final value = ExpressionEngine.evaluate(
        r'(${111}*${222})-${333}',
        variables: {
          '111': 8,
          '222': 3,
          '333': 5,
        },
      );
      expect(value, 19);
    });

    test('evaluates side tokens for dual text ids', () {
      final value = ExpressionEngine.evaluate(
        r'${abc:left}-${abc:right}+${x1}',
        variables: {
          'abc:left': 9,
          'abc:right': 2,
          'x1': 1,
        },
      );
      expect(value, 8);
    });

    test('supports unary minus and decimal values', () {
      final value = ExpressionEngine.evaluate(
        r'-${a}+(${b}*2.5)',
        variables: {
          'a': 4,
          'b': 2,
        },
      );
      expect(value, 1);
    });

    test('throws on missing variable', () {
      expect(
        () => ExpressionEngine.evaluate(
          r'${a}+${b}',
          variables: {'a': 1},
        ),
        throwsA(isA<ExpressionEngineException>()),
      );
    });

    test('throws on division by zero', () {
      expect(
        () => ExpressionEngine.evaluate(
          r'${a}/${b}',
          variables: {'a': 10, 'b': 0},
        ),
        throwsA(isA<ExpressionEngineException>()),
      );
    });

    test('throws on invalid token sequence', () {
      expect(
        () => ExpressionEngine.evaluate(
          r'${a}+@',
          variables: {'a': 1},
        ),
        throwsA(isA<ExpressionEngineException>()),
      );
    });

    test('handles long numeric ids without treating ids as numbers', () {
      final value = ExpressionEngine.evaluate(
        r'(${1779440412221}*${1779440441154})-${1779440651161}',
        variables: {
          '1779440412221': 20,
          '1779440441154': 4,
          '1779440651161': 5,
        },
      );
      expect(value, 75);
    });
  });

  group('ExpressionEngine.extractIds', () {
    test('extracts unique ids from repeated expression', () {
      final ids = ExpressionEngine.extractIds(
        r'${a}+${b}-${a}+${c:right}',
      );
      expect(ids.length, 3);
      expect(ids.contains('a'), true);
      expect(ids.contains('b'), true);
      expect(ids.contains('c:right'), true);
    });
  });
}

