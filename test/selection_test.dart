import 'package:test/test.dart';
import 'package:flutter_reap/src/selection.dart';

Set<int> keeping(String input, int count) {
  final result = parseSelection(input, count);
  return (result as KeepIndexes).indexes;
}

void main() {
  test('an empty answer keeps nothing, meaning delete all', () {
    expect(keeping('', 5), isEmpty);
    expect(keeping('   ', 5), isEmpty);
  });

  test('k cancels', () {
    expect(parseSelection('k', 5), isA<CancelSelection>());
    expect(parseSelection('K', 5), isA<CancelSelection>());
  });

  test('single numbers', () {
    expect(keeping('3', 5), {3});
  });

  test('comma separated numbers', () {
    expect(keeping('1,3', 5), {1, 3});
  });

  test('ranges are inclusive', () {
    expect(keeping('2-4', 5), {2, 3, 4});
  });

  test('mixed numbers and ranges, with spaces', () {
    expect(keeping('1, 3-5', 5), {1, 3, 4, 5});
  });

  test('unparseable input cancels rather than guessing', () {
    expect(parseSelection('banana', 5), isA<CancelSelection>());
    expect(parseSelection('1,,2', 5), isA<CancelSelection>());
    expect(parseSelection('3-', 5), isA<CancelSelection>());
    expect(parseSelection('-3', 5), isA<CancelSelection>());
  });

  test('out-of-range numbers cancel', () {
    expect(parseSelection('9', 5), isA<CancelSelection>());
    expect(parseSelection('0', 5), isA<CancelSelection>());
    expect(parseSelection('1-9', 5), isA<CancelSelection>());
  });

  test('a backwards range cancels', () {
    expect(parseSelection('4-2', 5), isA<CancelSelection>());
  });

  // Additional tests for edge cases
  test('whitespace inside a range and around tokens', () {
    expect(keeping('2 - 4', 5), {2, 3, 4});
    expect(keeping(' 1 , 3 ', 5), {1, 3});
  });

  test('a duplicated index keeps that index once', () {
    expect(keeping('2,2', 5), {2});
    expect(keeping('1,2,1', 5), {1, 2});
  });

  test('a single-element range keeps exactly that index', () {
    expect(keeping('3-3', 5), {3});
  });
}
