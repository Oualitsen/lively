import 'package:flutter_test/flutter_test.dart';
import 'package:lively/src/live_list.dart';
import 'package:lively/src/live_set.dart';
import 'package:lively/src/live_map.dart';

void main() {
  group('LiveList', () {
    test('add notifies', () {
      int calls = 0;
      final list = LiveList<int>(() => calls++);
      list.add(1);
      expect(calls, 1);
    });

    test('addAll notifies once', () {
      int calls = 0;
      final list = LiveList<int>(() => calls++);
      list.addAll([1, 2, 3]);
      expect(calls, 1);
    });

    test('index assignment notifies and stores value', () {
      int calls = 0;
      final list = LiveList<int>(() => calls++);
      list.add(0);
      calls = 0;
      list[0] = 42;
      expect(list[0], 42);
      expect(calls, 1);
    });

    test('remove notifies when item is present', () {
      int calls = 0;
      final list = LiveList<int>(() => calls++);
      list.add(1);
      calls = 0;
      expect(list.remove(1), isTrue);
      expect(calls, 1);
    });

    test('remove does not notify when item is absent', () {
      int calls = 0;
      final list = LiveList<int>(() => calls++);
      expect(list.remove(99), isFalse);
      expect(calls, 0);
    });

    test('removeAt notifies', () {
      int calls = 0;
      final list = LiveList<int>(() => calls++);
      list.add(1);
      calls = 0;
      list.removeAt(0);
      expect(calls, 1);
    });

    test('clear notifies and empties list', () {
      int calls = 0;
      final list = LiveList<int>(() => calls++);
      list.addAll([1, 2, 3]);
      calls = 0;
      list.clear();
      expect(list.length, 0);
      expect(calls, 1);
    });

    test('sort notifies', () {
      int calls = 0;
      final list = LiveList<int>(() => calls++);
      list.addAll([3, 1, 2]);
      calls = 0;
      list.sort();
      expect(list, [1, 2, 3]);
      expect(calls, 1);
    });

    test('wrap function is applied on add', () {
      final list = LiveList<String>(() {}, wrap: (s) => s.toUpperCase());
      list.add('hello');
      expect(list[0], 'HELLO');
    });

    test('wrap function is applied on index assignment', () {
      final list = LiveList<String>(() {}, wrap: (s) => s.toUpperCase());
      list.add('a');
      list[0] = 'hello';
      expect(list[0], 'HELLO');
    });

    test('of() copies source and applies wrap to existing items', () {
      final list = LiveList<String>.of(
        ['a', 'b'],
        () {},
        wrap: (s) => s.toUpperCase(),
      );
      expect(list, ['A', 'B']);
    });

    // When a wrap function is provided items are stored as wrapped instances.
    // remove() uses identity equality, so passing the original (pre-wrap)
    // reference silently fails to find the stored proxy.
    test('remove with wrap: original reference does not match stored proxy',
        () {
      final original = _Box('x');
      final list = LiveList<_Box>(
        () {},
        wrap: (b) => _Box('wrapped:${b.value}'),
      );
      list.add(original);
      expect(list[0].value, 'wrapped:x');
      expect(list.remove(original), isFalse);
    });

    test('remove with wrap: reference obtained from list removes correctly', () {
      int calls = 0;
      final list = LiveList<_Box>(
        () => calls++,
        wrap: (b) => _Box('wrapped:${b.value}'),
      );
      list.add(_Box('x'));
      calls = 0;
      final stored = list[0];
      expect(list.remove(stored), isTrue);
      expect(calls, 1);
    });
  });

  group('LiveSet', () {
    test('add notifies when item is new', () {
      int calls = 0;
      final set = LiveSet<int>(() => calls++);
      expect(set.add(1), isTrue);
      expect(calls, 1);
    });

    test('add does not notify for a duplicate', () {
      int calls = 0;
      final set = LiveSet<int>(() => calls++);
      set.add(1);
      calls = 0;
      expect(set.add(1), isFalse);
      expect(calls, 0);
    });

    test('addAll notifies when at least one item is new', () {
      int calls = 0;
      final set = LiveSet<int>(() => calls++);
      set.addAll([1, 2]);
      expect(calls, 1);
    });

    test('addAll does not notify when all items are duplicates', () {
      int calls = 0;
      final set = LiveSet<int>(() => calls++);
      set.addAll([1, 2]);
      calls = 0;
      set.addAll([1, 2]);
      expect(calls, 0);
    });

    test('remove notifies when item is present', () {
      int calls = 0;
      final set = LiveSet<int>(() => calls++);
      set.add(1);
      calls = 0;
      expect(set.remove(1), isTrue);
      expect(calls, 1);
    });

    test('remove does not notify when item is absent', () {
      int calls = 0;
      final set = LiveSet<int>(() => calls++);
      expect(set.remove(99), isFalse);
      expect(calls, 0);
    });

    test('clear notifies and empties set', () {
      int calls = 0;
      final set = LiveSet<int>(() => calls++);
      set.addAll([1, 2]);
      calls = 0;
      set.clear();
      expect(set.length, 0);
      expect(calls, 1);
    });

    test('of() copies source items', () {
      final set = LiveSet<int>.of([1, 2, 3], () {});
      expect(set, {1, 2, 3});
    });
  });

  group('LiveMap', () {
    test('[]= notifies', () {
      int calls = 0;
      final map = LiveMap<String, int>(() => calls++);
      map['a'] = 1;
      expect(calls, 1);
    });

    test('remove notifies when key is present', () {
      int calls = 0;
      final map = LiveMap<String, int>(() => calls++);
      map['a'] = 1;
      calls = 0;
      expect(map.remove('a'), 1);
      expect(calls, 1);
    });

    test('remove does not notify when key is absent', () {
      int calls = 0;
      final map = LiveMap<String, int>(() => calls++);
      map.remove('missing');
      expect(calls, 0);
    });

    test('clear notifies and empties map', () {
      int calls = 0;
      final map = LiveMap<String, int>(() => calls++);
      map['a'] = 1;
      calls = 0;
      map.clear();
      expect(map.length, 0);
      expect(calls, 1);
    });

    test('addAll notifies once for multiple entries', () {
      int calls = 0;
      final map = LiveMap<String, int>(() => calls++);
      map.addAll({'a': 1, 'b': 2});
      expect(calls, 1);
    });

    test('putIfAbsent notifies on insert and is silent on existing key', () {
      int calls = 0;
      final map = LiveMap<String, int>(() => calls++);
      map.putIfAbsent('a', () => 1);
      expect(calls, 1);
      calls = 0;
      map.putIfAbsent('a', () => 99);
      expect(map['a'], 1);
      expect(calls, 0);
    });

    test('wrapValue is applied on []=', () {
      final map =
          LiveMap<String, String>(() {}, wrapValue: (v) => v.toUpperCase());
      map['key'] = 'hello';
      expect(map['key'], 'HELLO');
    });

    test('of() copies source and applies wrapValue', () {
      final map = LiveMap<String, String>.of(
        {'a': 'hello'},
        () {},
        wrapValue: (v) => v.toUpperCase(),
      );
      expect(map['a'], 'HELLO');
    });

    test('remove notifies when stored value is null (nullable-value map)', () {
      int calls = 0;
      final map = LiveMap<String, int?>(() => calls++);
      map['a'] = null;
      calls = 0;
      map.remove('a');
      expect(calls, 1);
      expect(map.containsKey('a'), isFalse);
    });
  });
}

class _Box {
  final String value;
  _Box(this.value);
}
