import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:lively_generator/builder.dart';
import 'package:test/test.dart';

void main() {
  group('LiveWidgetGenerator', () {
    // ── generated structure ────────────────────────────────────────────────

    test('generates thin widget + abstract base + impl class', () async {
      await _build(
        source: r'''
@Live()
class Counter extends _$Counter {
  int count = 0;
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          // thin StatefulWidget wrapper
          contains('class CounterWidget extends StatefulWidget'),
          contains('const CounterWidget({super.key})'),
          contains('State<CounterWidget> createState()'),
          contains('return _CounterImpl();'),
          // abstract base carries microtask state
          contains('abstract class _\$Counter extends State<CounterWidget>'),
          contains('bool _dirty = false'),
          contains('void _scheduleRebuild()'),
          contains('void notify()'),
          // concrete impl subclasses the user class
          contains('class _CounterImpl extends Counter'),
        ],
      );
    });

    // ── reactive fields ────────────────────────────────────────────────────

    test('reactive fields used in build() get setter overrides with _scheduleRebuild',
        () async {
      await _build(
        source: r'''
@Live()
class Page extends _$Page {
  String name = 'John';
  int age = 25;
  bool isLoading = false;
  @override Widget build(BuildContext context) => Text('$name $age $isLoading');
}
''',
        expect: [
          contains('set name(String v)'),
          contains('super.name = v'),
          contains('set age(int v)'),
          contains('super.age = v'),
          contains('set isLoading(bool v)'),
          contains('super.isLoading = v'),
          contains('_scheduleRebuild()'),
          // user class holds the backing state — no redundant fields in impl
          isNot(contains('String _name')),
          isNot(contains('String get name')),
          isNot(contains('int _age')),
        ],
      );
    });

    // ── final fields ───────────────────────────────────────────────────────

    test('final fields with initializer are ignored — no setter or backing field',
        () async {
      await _build(
        source: r'''
@Live()
class MyWidget extends _$MyWidget {
  final String title = 'My App';
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          isNot(contains('set title')),
          isNot(contains('_title')),
        ],
      );
    });

    // ── widget parameters (late final) ─────────────────────────────────────

    test('late final without initializer becomes required widget param', () async {
      await _build(
        source: r'''
@Live()
class MyPage extends _$MyPage {
  late final int initialValue;
  int count = 0;
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          contains('required this.initialValue'),
          contains('final int initialValue;'),
          contains('super.initialValue = widget.initialValue;'),
        ],
      );
    });

    test('nullable late final becomes optional widget param', () async {
      await _build(
        source: r'''
@Live()
class MyPage extends _$MyPage {
  late final String? title;
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          contains('this.title'),
          isNot(contains('required this.title')),
          contains('final String? title;'),
        ],
      );
    });

    test('widget params are set before super.initState()', () async {
      await _build(
        source: r'''
@Live()
class MyPage extends _$MyPage {
  late final int initialValue;
  late final String label;
  int count = 0;
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          contains('required this.initialValue'),
          contains('required this.label'),
          contains('final int initialValue;'),
          contains('final String label;'),
          contains('super.initialValue = widget.initialValue;'),
          contains('super.label = widget.label;'),
          // both assignments must appear before super.initState() in the impl
          predicate<String>((s) {
            final paramIdx = s.indexOf('super.initialValue = widget.initialValue');
            if (paramIdx == -1) return false;
            // search for super.initState() only after the param assignment so
            // the abstract base's own stub (which comes earlier in the file)
            // doesn't cause a false negative
            final superIdx = s.indexOf('super.initState()', paramIdx);
            return superIdx != -1;
          }, 'params are assigned before super.initState()'),
        ],
      );
    });

    // ── microtask batching ─────────────────────────────────────────────────

    test('microtask batching is always emitted on the base class', () async {
      await _build(
        source: r'''
@Live()
class Simple extends _$Simple {
  int x = 0;
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          contains('bool _dirty = false'),
          contains('void _scheduleRebuild()'),
          contains('Future.microtask('),
          contains('if (mounted) setState(() {})'),
        ],
      );
    });

    test('@mustCallSuper is present on base initState and dispose', () async {
      await _build(
        source: r'''
@Live()
class Simple extends _$Simple {
  int x = 0;
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          // both stubs must carry @mustCallSuper so that user overrides are
          // forced to call super.initState() / super.dispose();
          // the annotation lands on its own line immediately before @override
          contains('@mustCallSuper\n  @override\n  void initState()'),
          contains('@mustCallSuper\n  @override\n  void dispose()'),
        ],
      );
    });

    // ── notify() ──────────────────────────────────────────────────────────

    test('notify() escape hatch is always emitted on the base class', () async {
      await _build(
        source: r'''
@Live()
class Simple extends _$Simple {
  int x = 0;
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          contains('void notify()'),
        ],
      );
    });

    // ── disposable fields ──────────────────────────────────────────────────

    test('TextEditingController and FocusNode are disposed', () async {
      await _build(
        source: '''
@Live()
class FormWidget extends _\$FormWidget {
  TextEditingController nameCtrl = TextEditingController();
  FocusNode focusNode = FocusNode();
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          contains('nameCtrl.dispose()'),
          contains('focusNode.dispose()'),
          contains('super.dispose()'),
          // disposable fields are NOT made reactive
          isNot(contains('set nameCtrl')),
          isNot(contains('set focusNode')),
        ],
      );
    });

    test('ScrollController and PageController are disposed', () async {
      await _build(
        source: '''
@Live()
class ScrollPage extends _\$ScrollPage {
  ScrollController scrollCtrl = ScrollController();
  PageController pageCtrl = PageController();
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          contains('scrollCtrl.dispose()'),
          contains('pageCtrl.dispose()'),
        ],
      );
    });

    test('StreamController is closed, not disposed', () async {
      await _build(
        extraImports: "import 'dart:async';",
        source: r'''
@Live()
class StreamWidget extends _$StreamWidget {
  StreamController<int> events = StreamController<int>();
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          contains('events.close()'),
          isNot(contains('events.dispose()')),
        ],
      );
    });

    test('StreamSubscription is cancelled', () async {
      await _build(
        extraImports: "import 'dart:async';",
        source: r'''
@Live()
class SubWidget extends _$SubWidget {
  late StreamSubscription<int> sub;
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [contains('sub.cancel()')],
      );
    });

    test('nullable disposable uses ?. in dispose()', () async {
      await _build(
        source: r'''
@Live()
class MyWidget extends _$MyWidget {
  TextEditingController? ctrl;
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          contains('ctrl?.dispose()'),
          isNot(contains('ctrl.dispose()')),
        ],
      );
    });

    test('nullable ChangeNotifier uses ?. for addListener and removeListener',
        () async {
      await _build(
        source: r'''
class MyModel extends ChangeNotifier {}

@Live()
class MyWidget extends _$MyWidget {
  MyModel? model;
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          contains('model?.addListener(_scheduleRebuild)'),
          contains('model?.removeListener(_scheduleRebuild)'),
          // setter must also use ?. on _old and v
          contains('_old?.removeListener(_scheduleRebuild)'),
          contains('v?.addListener(_scheduleRebuild)'),
        ],
      );
    });

    test('dispose() is omitted from impl when there are no disposable fields',
        () async {
      await _build(
        source: r'''
@Live()
class Simple extends _$Simple {
  int x = 0;
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          // the abstract base always emits a @mustCallSuper dispose() stub —
          // only the impl should be free of it when nothing needs cleanup
          predicate<String>((s) {
            final implIdx = s.indexOf('class _SimpleImpl');
            return implIdx != -1 &&
                !s.substring(implIdx).contains('void dispose()');
          }, 'impl class has no dispose() override'),
        ],
      );
    });

    // ── ChangeNotifier ─────────────────────────────────────────────────────

    test('ChangeNotifier field is wired with addListener / removeListener',
        () async {
      await _build(
        source: r'''
class MyModel extends ChangeNotifier {
  String value = '';
}

@Live()
class MyWidget extends _$MyWidget {
  MyModel model = MyModel();
  @override Widget build(BuildContext context) => Text(model.value);
}
''',
        expect: [
          contains('model.addListener(_scheduleRebuild)'),
          contains('model.removeListener(_scheduleRebuild)'),
          // setter re-wires listener on field replacement
          contains('set model(MyModel v)'),
        ],
      );
    });

    test('late final ChangeNotifier with initializer: addListener in initState, removeListener in dispose, no setter, no param',
        () async {
      await _build(
        source: r'''
class MyModel extends ChangeNotifier {
  String value = '';
}

@Live()
class MyWidget extends _$MyWidget {
  late final MyModel model = MyModel();
  @override Widget build(BuildContext context) => Text(model.value);
}
''',
        expect: [
          // listener wired — widget reacts to store changes
          contains('model.addListener(_scheduleRebuild)'),
          contains('model.removeListener(_scheduleRebuild)'),
          // not a constructor param — has an initializer
          isNot(contains('this.model')),
          // no setter — field is final
          isNot(contains('set model(')),
          // no didUpdateWidget for this field — store is fixed at init time
          isNot(contains('widget.model')),
        ],
      );
    });

    test('late final ChangeNotifier param: addListener in initState, removeListener in dispose',
        () async {
      await _build(
        source: r'''
class MyModel extends ChangeNotifier {
  String value = '';
}

@Live()
class MyWidget extends _$MyWidget {
  late final MyModel model;
  @override Widget build(BuildContext context) => Text(model.value);
}
''',
        expect: [
          // param wiring
          contains('required this.model'),
          contains('super.model = widget.model;'),
          // listener wired after param is set
          contains('model.addListener(_scheduleRebuild)'),
          // deregistered in dispose
          contains('model.removeListener(_scheduleRebuild)'),
          // no setter override — field is final
          isNot(contains('set model(')),
        ],
      );
    });

    test('late final ChangeNotifier param: didUpdateWidget re-wires listener on store swap',
        () async {
      await _build(
        source: r'''
class MyModel extends ChangeNotifier {
  String value = '';
}

@Live()
class MyWidget extends _$MyWidget {
  late final MyModel model;
  @override Widget build(BuildContext context) => Text(model.value);
}
''',
        expect: [
          contains('void didUpdateWidget('),
          // must remove listener from old instance before assigning new one
          contains('old.model.removeListener(_scheduleRebuild)'),
          contains('super.model = widget.model'),
          // must add listener to new instance
          contains('model.addListener(_scheduleRebuild)'),
        ],
      );
    });

    // ── LiveList ───────────────────────────────────────────────────────────

    test('List<T> field is backed by LiveList with getter, setter, initState',
        () async {
      await _build(
        source: r'''
@Live()
class MyWidget extends _$MyWidget {
  List<String> items = [];
  @override Widget build(BuildContext context) => Text('${items.length}');
}
''',
        expect: [
          contains('late LiveList<String>'),
          contains('LiveList.of(super.items, _scheduleRebuild)'),
          contains('LiveList.of(v, _scheduleRebuild)'),
        ],
      );
    });

    test('List<T> with proxyable T passes a wrap function', () async {
      await _build(
        source: r'''
class Car {
  String color = 'white';
}

@Live()
class MyWidget extends _$MyWidget {
  List<Car> cars = [];
  @override Widget build(BuildContext context) => Text('${cars.length}');
}
''',
        expect: [
          contains('class _LiveCar extends Car'),
          contains('wrap: (e) => _LiveCar.from(e, _scheduleRebuild)'),
        ],
      );
    });

    // ── proxy objects ──────────────────────────────────────────────────────

    test('plain object field generates _Rx proxy subclass', () async {
      await _build(
        source: r'''
class Address {
  String street = 'Main St';
  String city = 'Springfield';
}

@Live()
class MyPage extends _$MyPage {
  Address address = Address();
  @override Widget build(BuildContext context) => Text(address.street);
}
''',
        expect: [
          contains('class _LiveAddress extends Address'),
          contains('String _street'),
          contains('String _city'),
          contains('set street(String v)'),
          contains('set city(String v)'),
          contains('_notify()'),
          contains('_LiveAddress.from('),
        ],
      );
    });

    test('proxy initState wraps the initial field value', () async {
      await _build(
        source: r'''
class Point {
  int x = 0;
  int y = 0;
}

@Live()
class MyPage extends _$MyPage {
  Point pos = Point();
  @override Widget build(BuildContext context) => Text('${pos.x},${pos.y}');
}
''',
        expect: [
          contains('super.pos = _LivePoint.from(pos, _scheduleRebuild)'),
          contains('set pos(Point v)'),
        ],
      );
    });

    test('proxy is not generated for final/sealed classes — falls back to reactive setter',
        () async {
      await _build(
        source: r'''
final class Locked {
  String value = 'x';
}

@Live()
class MyPage extends _$MyPage {
  Locked locked = Locked();
  @override Widget build(BuildContext context) => Text('$locked');
}
''',
        expect: [
          // falls back to plain reactive setter (used in build → scheduled)
          contains('set locked(Locked v)'),
          contains('_scheduleRebuild()'),
          isNot(contains('class _LiveLocked')),
        ],
      );
    });

    // ── all mutable fields are wired — no build() AST analysis ───────────

    test('all mutable fields get setter overrides — every assignment schedules a rebuild',
        () async {
      await _build(
        source: r'''
@Live()
class MyWidget extends _$MyWidget {
  int counter = 0;
  String log = '';
  @override Widget build(BuildContext context) => Column(
    children: [
      Text('$counter'),
      ElevatedButton(
        onPressed: () { counter++; log = 'tapped'; },
        child: const SizedBox(),
      ),
    ],
  );
}
''',
        expect: [
          contains('set counter(int v)'),
          contains('set log(String v)'),
          contains('_scheduleRebuild()'),
        ],
      );
    });

    test('notify() is available for manually scheduling a rebuild', () async {
      await _build(
        source: r'''
@Live()
class MyWidget extends _$MyWidget {
  int counter = 0;
  String log = '';
  @override Widget build(BuildContext context) => Text('$counter');
}
''',
        expect: [contains('void notify()')],
      );
    });

    // ── LiveSet ───────────────────────────────────────────────────────────

    test('Set<T> field is backed by LiveSet with getter, setter, initState',
        () async {
      await _build(
        source: r'''
@Live()
class MyWidget extends _$MyWidget {
  Set<String> tags = {};
  @override Widget build(BuildContext context) => Text('${tags.length}');
}
''',
        expect: [
          contains('late LiveSet<String>'),
          contains('LiveSet.of(super.tags, _scheduleRebuild)'),
          contains('LiveSet.of(v, _scheduleRebuild)'),
        ],
      );
    });

    test('Set<T> with proxyable T passes a wrap function', () async {
      await _build(
        source: r'''
class Tag {
  String label = '';
}

@Live()
class MyWidget extends _$MyWidget {
  Set<Tag> tags = {};
  @override Widget build(BuildContext context) => Text('${tags.length}');
}
''',
        expect: [
          contains('class _LiveTag extends Tag'),
          contains('wrap: (e) => _LiveTag.from(e, _scheduleRebuild)'),
        ],
      );
    });

    // ── LiveMap ───────────────────────────────────────────────────────────

    test('Map<K, V> field is backed by LiveMap with getter, setter, initState',
        () async {
      await _build(
        source: r'''
@Live()
class MyWidget extends _$MyWidget {
  Map<String, int> scores = {};
  @override Widget build(BuildContext context) => Text('${scores.length}');
}
''',
        expect: [
          contains('late LiveMap<String, int>'),
          contains('LiveMap.of(super.scores, _scheduleRebuild)'),
          contains('LiveMap.of(v, _scheduleRebuild)'),
        ],
      );
    });

    test('Map<K, V> with proxyable V passes a wrapValue function', () async {
      await _build(
        source: r'''
class Car {
  String color = 'white';
}

@Live()
class MyWidget extends _$MyWidget {
  Map<String, Car> fleet = {};
  @override Widget build(BuildContext context) => Text('${fleet.length}');
}
''',
        expect: [
          contains('class _LiveCar extends Car'),
          contains('wrapValue: (v) => _LiveCar.from(v, _scheduleRebuild)'),
        ],
      );
    });

    // ── proxy field re-wrap on assignment ─────────────────────────────────

    test('assigning a plain object to a proxy field wraps it as a new proxy',
        () async {
      await _build(
        source: r'''
class Address {
  String street = 'Main St';
}

@Live()
class MyPage extends _$MyPage {
  Address address = Address();
  @override Widget build(BuildContext context) => Text(address.street);
}
''',
        expect: [
          contains('set address(Address v)'),
          // setter must wrap the incoming value, not store it raw
          contains('_LiveAddress.from(v, _scheduleRebuild)'),
        ],
      );
    });

    // ── didUpdateWidget ───────────────────────────────────────────────────

    test('didUpdateWidget is generated when param fields exist', () async {
      await _build(
        source: r'''
@Live()
class MyPage extends _$MyPage {
  late final int value;
  int count = 0;
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          contains('void didUpdateWidget('),
          contains('widget.value != old.value'),
          contains('super.value = widget.value'),
          contains('if (_changed) _scheduleRebuild()'),
        ],
      );
    });

    test('didUpdateWidget is not generated when there are no param fields',
        () async {
      await _build(
        source: r'''
@Live()
class Simple extends _$Simple {
  int x = 0;
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          isNot(contains('didUpdateWidget')),
        ],
      );
    });

    // ── impl class naming ──────────────────────────────────────────────────

    test('impl is named _<ClassName>Impl, widget is <ClassName>Widget', () async {
      await _build(
        source: r'''
@Live()
class FancyButton extends _$FancyButton {
  bool pressed = false;
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          contains('class FancyButtonWidget extends StatefulWidget'),
          contains('abstract class _\$FancyButton extends State<FancyButtonWidget>'),
          contains('class _FancyButtonImpl extends FancyButton'),
        ],
      );
    });

    // ── mixed fields ───────────────────────────────────────────────────────

    test('all field categories are classified and wired correctly together',
        () async {
      await _build(
        extraImports: "import 'dart:async';",
        source: r'''
@Live()
class ProfilePage extends _$ProfilePage {
  late final String appName;
  String name = 'John';
  int age = 25;
  final String locale = 'en';
  TextEditingController nameCtrl = TextEditingController();
  StreamController<String> events = StreamController<String>();
  List<String> tags = [];
  @override Widget build(BuildContext context) => Text('$name $age ${tags.length}');
}
''',
        expect: [
          // param
          contains('required this.appName'),
          contains('final String appName;'),
          contains('super.appName = widget.appName;'),
          // reactive (used in build → scheduled)
          contains('set name(String v)'),
          contains('set age(int v)'),
          // final passthrough — no setter
          isNot(contains('set locale')),
          // disposable
          contains('nameCtrl.dispose()'),
          contains('events.close()'),
          // LiveList (used in build → wired)
          contains('late LiveList<String>'),
        ],
      );
    });

    // ── @computed fields ───────────────────────────────────────────────────

    test('@computed getter generates backing field, dirty flag, and override',
        () async {
      await _build(
        source: r'''
@Live()
class SearchPage extends _$SearchPage {
  String query = '';
  List<String> items = [];

  @computed
  List<String> get results =>
      items.where((i) => i.contains(query)).toList();

  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          // backing field and dirty flag
          contains('List<String>? _\$results'),
          contains('bool _\$resultsDirty = true'),
          // getter override with lazy recompute
          contains('get results'),
          contains('if (_\$resultsDirty)'),
          contains('_\$results = super.results'),
          contains('_\$resultsDirty = false'),
          contains('return _\$results!'),
        ],
      );
    });

    test('@computed dirty flag is set in all reactive setters', () async {
      await _build(
        source: r'''
@Live()
class SearchPage extends _$SearchPage {
  String query = '';
  List<String> items = [];

  @computed
  List<String> get results =>
      items.where((i) => i.contains(query)).toList();

  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          // reactive scalar setter marks dirty
          contains('set query(String v)'),
          // list setter marks dirty
          contains('set items(List<String> v)'),
          // both setters contain the dirty mark
          matches(RegExp(r'set query[\s\S]*?_\$resultsDirty = true')),
          matches(RegExp(r'set items[\s\S]*?_\$resultsDirty = true')),
        ],
      );
    });

    test('multiple @computed getters each get independent dirty flags',
        () async {
      await _build(
        source: r'''
@Live()
class FilterPage extends _$FilterPage {
  String query = '';
  int minAge = 0;

  @computed
  String get upperQuery => query.toUpperCase();

  @computed
  bool get hasFilter => query.isNotEmpty || minAge > 0;

  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          contains('String? _\$upperQuery'),
          contains('bool _\$upperQueryDirty = true'),
          contains('bool? _\$hasFilter'),
          contains('bool _\$hasFilterDirty = true'),
          // every reactive setter marks ALL computed getters dirty
          matches(RegExp(r'set query[\s\S]*?_\$upperQueryDirty = true')),
          matches(RegExp(r'set query[\s\S]*?_\$hasFilterDirty = true')),
          matches(RegExp(r'set minAge[\s\S]*?_\$upperQueryDirty = true')),
          matches(RegExp(r'set minAge[\s\S]*?_\$hasFilterDirty = true')),
        ],
      );
    });
  });

  // ── @LiveStore tests ──────────────────────────────────────────────────────

  group('LiveStoreGenerator', () {
    // ── structure ─────────────────────────────────────────────────────────

    test('generates abstract ChangeNotifier base + public concrete impl',
        () async {
      await _build(
        source: r'''
@LiveStore()
class _Counter extends _$Counter {
  int count = 0;
}
''',
        expect: [
          contains('abstract class _\$Counter extends ChangeNotifier'),
          contains('class Counter extends _Counter'),
        ],
      );
    });

    test('strips leading _ to produce the public class name', () async {
      await _build(
        source: r'''
@LiveStore()
class _UserProfileStore extends _$UserProfileStore {
  String name = '';
}
''',
        expect: [
          contains('abstract class _\$UserProfileStore extends ChangeNotifier'),
          contains('class UserProfileStore extends _UserProfileStore'),
        ],
      );
    });

    test('base has _scheduleNotify + notifyListeners + notify() escape hatch',
        () async {
      await _build(
        source: r'''
@LiveStore()
class _MyStore extends _$MyStore {
  int x = 0;
}
''',
        expect: [
          contains('void _scheduleNotify()'),
          contains('notifyListeners()'),
          contains('void notify()'),
          contains('_scheduleNotify()'),
        ],
      );
    });

    test('@mustCallSuper dispose() is on the abstract base', () async {
      await _build(
        source: r'''
@LiveStore()
class _MyStore extends _$MyStore {
  int x = 0;
}
''',
        expect: [
          contains('@mustCallSuper'),
          contains('void dispose()'),
          contains('super.dispose()'),
        ],
      );
    });

    // ── reactive scalars ──────────────────────────────────────────────────

    test('reactive scalar fields get setter overrides calling _scheduleNotify',
        () async {
      await _build(
        source: r'''
@LiveStore()
class _AppStore extends _$AppStore {
  String title = '';
  int count = 0;
  bool loading = false;
}
''',
        expect: [
          contains('set title(String v)'),
          contains('super.title = v'),
          contains('set count(int v)'),
          contains('super.count = v'),
          contains('set loading(bool v)'),
          contains('super.loading = v'),
          contains('_scheduleNotify()'),
          // no backing fields in the impl — storage stays in user class
          isNot(contains('String _title')),
          isNot(contains('int _count')),
        ],
      );
    });

    // ── final fields ──────────────────────────────────────────────────────

    test('final fields are not reactive — no setter, no backing field', () async {
      await _build(
        source: r'''
@LiveStore()
class _MyStore extends _$MyStore {
  final String appId = 'abc';
}
''',
        expect: [
          isNot(contains('set appId')),
          isNot(contains('_appId')),
        ],
      );
    });

    // ── constructor params ────────────────────────────────────────────────

    test('late final without initializer → required named constructor param',
        () async {
      await _build(
        source: r'''
@LiveStore()
class _MyStore extends _$MyStore {
  late final String apiKey;
  int count = 0;
}
''',
        expect: [
          contains('required String apiKey'),
          contains('super.apiKey = apiKey'),
          // reactive field still wired
          contains('set count(int v)'),
        ],
      );
    });

    test('nullable late final → optional constructor param', () async {
      await _build(
        source: r'''
@LiveStore()
class _MyStore extends _$MyStore {
  late final String? tag;
}
''',
        expect: [
          contains('String? tag'),
          isNot(contains('required String? tag')),
          contains('super.tag = tag'),
        ],
      );
    });

    test('constructor params are assigned before listener wiring and collection init',
        () async {
      await _build(
        source: r'''
@LiveStore()
class _MyStore extends _$MyStore {
  late final String key;
  List<int> items = [];
}
''',
        expect: [
          // param assignment comes first in the constructor body
          allOf(
            contains('super.key = key'),
            contains('LiveList.of(super.items'),
          ),
        ],
      );
    });

    // ── disposable fields ─────────────────────────────────────────────────

    test('TextEditingController is disposed in store dispose()', () async {
      await _build(
        source: r'''
@LiveStore()
class _FormStore extends _$FormStore {
  TextEditingController nameCtrl = TextEditingController();
}
''',
        expect: [
          contains('nameCtrl.dispose()'),
          isNot(contains('set nameCtrl')),
        ],
      );
    });

    // ── ChangeNotifier fields ─────────────────────────────────────────────

    test('CN field: addListener in ctor, removeListener in dispose, setter re-wires',
        () async {
      await _build(
        source: r'''
class MyModel extends ChangeNotifier {}

@LiveStore()
class _AppStore extends _$AppStore {
  MyModel model = MyModel();
}
''',
        expect: [
          contains('model.addListener(_scheduleNotify)'),
          contains('model.removeListener(_scheduleNotify)'),
          // setter re-wires on replacement
          contains('set model(MyModel v)'),
          contains('_old.removeListener(_scheduleNotify)'),
          contains('v.addListener(_scheduleNotify)'),
        ],
      );
    });

    // ── owned @LiveStore fields ───────────────────────────────────────────

    test('owned @LiveStore field: addListener + removeListener + dispose()',
        () async {
      await _build(
        source: r'''
@LiveStore()
class _CartStore extends ChangeNotifier {
  int items = 0;
}

@LiveStore()
class _AppStore extends _$AppStore {
  _CartStore cart = _CartStore();
}
''',
        expect: [
          contains('cart.addListener(_scheduleNotify)'),
          contains('cart.removeListener(_scheduleNotify)'),
          contains('cart.dispose()'),
        ],
      );
    });

    // ── reactive collections ──────────────────────────────────────────────

    test('List<T> field backed by LiveList with getter, setter, ctor init',
        () async {
      await _build(
        source: r'''
@LiveStore()
class _ListStore extends _$ListStore {
  List<String> items = [];
}
''',
        expect: [
          contains('late LiveList<String>'),
          contains('LiveList.of(super.items, _scheduleNotify)'),
          contains('List<String> get items'),
          contains('set items(List<String> v)'),
        ],
      );
    });

    test('Set<T> field backed by LiveSet with getter, setter, ctor init',
        () async {
      await _build(
        source: r'''
@LiveStore()
class _SetStore extends _$SetStore {
  Set<int> ids = {};
}
''',
        expect: [
          contains('late LiveSet<int>'),
          contains('LiveSet.of(super.ids, _scheduleNotify)'),
          contains('Set<int> get ids'),
          contains('set ids(Set<int> v)'),
        ],
      );
    });

    test('Map<K,V> field backed by LiveMap with getter, setter, ctor init',
        () async {
      await _build(
        source: r'''
@LiveStore()
class _MapStore extends _$MapStore {
  Map<String, int> scores = {};
}
''',
        expect: [
          contains('late LiveMap<String, int>'),
          contains('LiveMap.of(super.scores, _scheduleNotify)'),
          contains('Map<String, int> get scores'),
          contains('set scores(Map<String, int> v)'),
        ],
      );
    });

    // ── proxy objects ─────────────────────────────────────────────────────

    test('plain object field generates proxy and wraps in ctor', () async {
      await _build(
        source: r'''
class Address {
  String street = 'Main St';
}

@LiveStore()
class _UserStore extends _$UserStore {
  Address address = Address();
}
''',
        expect: [
          contains('class _LiveAddress extends Address'),
          contains('_LiveAddress.from(super.address, _scheduleNotify)'),
        ],
      );
    });

    // ── @Live() widget integration ────────────────────────────────────────

    test('@Live() widget: owned @LiveStore (inline init) gets auto-dispose',
        () async {
      await _build(
        source: r'''
// _CartStore has @LiveStore and extends ChangeNotifier directly for test resolution.
@LiveStore()
class _CartStore extends ChangeNotifier {
  int items = 0;
}

@Live()
class CheckoutPage extends _$CheckoutPage {
  _CartStore cart = _CartStore();
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          contains('cart.addListener(_scheduleRebuild)'),
          contains('cart.removeListener(_scheduleRebuild)'),
          contains('cart.dispose()'),
        ],
      );
    });

    test('@Live() widget: borrowed @LiveStore (late final param) — no dispose',
        () async {
      await _build(
        source: r'''
@LiveStore()
class _CartStore extends ChangeNotifier {
  int items = 0;
}

@Live()
class CheckoutPage extends _$CheckoutPage {
  late final _CartStore cart;
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          contains('cart.addListener(_scheduleRebuild)'),
          contains('cart.removeListener(_scheduleRebuild)'),
          isNot(contains('cart.dispose()')),
        ],
      );
    });

    test('@Live() widget: borrowed @LiveStore (late final with init) — no dispose',
        () async {
      await _build(
        source: r'''
@LiveStore()
class _CartStore extends ChangeNotifier {
  int items = 0;
}

_CartStore getCart() => _CartStore();

@Live()
class CheckoutPage extends _$CheckoutPage {
  late final _CartStore cart = getCart();
  @override Widget build(BuildContext context) => const SizedBox();
}
''',
        expect: [
          contains('cart.addListener(_scheduleRebuild)'),
          contains('cart.removeListener(_scheduleRebuild)'),
          isNot(contains('cart.dispose()')),
        ],
      );
    });

    // ── @computed fields ───────────────────────────────────────────────────

    test('@computed getter in @LiveStore generates backing field, dirty flag, and override',
        () async {
      await _build(
        source: r'''
@LiveStore()
class _SearchStore extends _$SearchStore {
  String query = '';
  List<String> items = [];

  @computed
  List<String> get results =>
      items.where((i) => i.contains(query)).toList();
}
''',
        expect: [
          contains('List<String>? _\$results'),
          contains('bool _\$resultsDirty = true'),
          contains('get results'),
          contains('if (_\$resultsDirty)'),
          contains('_\$results = super.results'),
          contains('_\$resultsDirty = false'),
          contains('return _\$results!'),
          // reactive setters mark dirty
          matches(RegExp(r'set query[\s\S]*?_\$resultsDirty = true')),
          matches(RegExp(r'set items[\s\S]*?_\$resultsDirty = true')),
        ],
      );
    });
  });

  // ── InheritedNotifier provider ────────────────────────────────────────────

  group('InheritedNotifier provider', () {
    test('generates a provider class for every @LiveStore', () async {
      await _build(
        source: r'''
@LiveStore()
class _Counter extends _$Counter {
  int count = 0;
}
''',
        expect: [
          contains('class CounterProvider extends InheritedNotifier<Counter>'),
          contains('required Counter store'),
          contains('super(notifier: store)'),
          contains('static Counter of(BuildContext context)'),
          contains('dependOnInheritedWidgetOfExactType<CounterProvider>()'),
          contains("assert(result != null, 'No CounterProvider found in widget tree.')"),
          contains('return result!.notifier!'),
          contains('static Counter? maybeOf(BuildContext context)'),
        ],
      );
    });

    test('provider name is <StoreName>Provider', () async {
      await _build(
        source: r'''
@LiveStore()
class _ShoppingCart extends _$ShoppingCart {
  int itemCount = 0;
}
''',
        expect: [
          contains('class ShoppingCartProvider extends InheritedNotifier<ShoppingCart>'),
          contains('static ShoppingCart of(BuildContext context)'),
          contains('static ShoppingCart? maybeOf(BuildContext context)'),
        ],
      );
    });
  });

  // ── missing extends clause ────────────────────────────────────────────────

  group('missing extends clause', () {
    test('throws a clear error for @Live() without extends _\$ClassName',
        () async {
      await _buildRaw(
        source: """
import 'package:flutter/widgets.dart';
import 'package:lively/lively.dart';

part 'example.g.dart';

@Live()
class Counter {
  int count = 0;
  @override Widget build(BuildContext context) => const SizedBox();
}
""",
        onError: (e) => expect(
          e.toString(),
          allOf(
            contains('extends _\$Counter'),
            contains('@Live() class must extend'),
          ),
        ),
      );
    });

    test('throws a clear error for @LiveStore() without extends _\$StoreName',
        () async {
      await _buildRaw(
        source: """
import 'package:lively/lively.dart';

part 'example.g.dart';

@LiveStore()
class _Counter {
  int count = 0;
}
""",
        onError: (e) => expect(
          e.toString(),
          allOf(
            contains('extends _\$Counter'),
            contains('@LiveStore() class must extend'),
          ),
        ),
      );
    });
  });

  // ── missing part directive ─────────────────────────────────────────────────

  group('missing part directive', () {
    const sourceWithoutPart = """
import 'package:flutter/widgets.dart';
import 'package:lively/lively.dart';

@Live()
class Counter extends _\$Counter {
  int count = 0;
  @override Widget build(BuildContext context) => const SizedBox();
}
""";

    test('throws a clear error for @Live() without part directive', () async {
      await _buildRaw(
        source: sourceWithoutPart,
        onError: (e) => expect(
          e.toString(),
          allOf(
            contains("part 'example.g.dart'"),
            contains('Missing part directive'),
          ),
        ),
      );
    });

    test('throws a clear error for @LiveStore() without part directive',
        () async {
      await _buildRaw(
        source: """
import 'package:lively/lively.dart';

@LiveStore()
class _Counter {
  int count = 0;
}
""",
        onError: (e) => expect(
          e.toString(),
          allOf(
            contains("part 'example.g.dart'"),
            contains('Missing part directive'),
          ),
        ),
      );
    });
  });
}

// ── test helpers ──────────────────────────────────────────────────────────────

Future<void> _build({
  required String source,
  required List<Matcher> expect,
  String extraImports = '',
}) async {
  await testBuilder(
    livelyBuilder(BuilderOptions.empty),
    {
      ..._stubs,
      'myapp|lib/example.dart': _wrap(source, extraImports),
    },
    outputs: {
      'myapp|lib/example.lively.g.part': decodedMatches(allOf(expect)),
    },
  );
}

Future<void> _buildRaw({
  required String source,
  required void Function(Object) onError,
}) async {
  try {
    await testBuilder(
      livelyBuilder(BuilderOptions.empty),
      {..._stubs, 'myapp|lib/example.dart': source},
      outputs: {},
    );
    fail('Expected an error but none was thrown');
  } catch (e) {
    onError(e);
  }
}

String _wrap(String body, [String extraImports = '']) => """
import 'package:flutter/widgets.dart';
import 'package:lively/lively.dart';
$extraImports

part 'example.g.dart';

$body
""";

// Minimal stubs so the analyzer can resolve Flutter and lively types
// without requiring a real Flutter SDK in the test environment.
const _stubs = <String, String>{
  'flutter|lib/widgets.dart': r'''
library flutter.widgets;
typedef VoidCallback = void Function();
class Widget {}
class StatefulWidget extends Widget {
  const StatefulWidget({Object? key});
}
abstract class State<T extends StatefulWidget> {
  T get widget;
  bool get mounted;
  void setState(void Function() fn) {}
  void dispose() {}
  Widget build(covariant BuildContext context);
}
class BuildContext {}
class SizedBox extends Widget { const SizedBox(); }
class Text extends Widget { const Text(String s); }
class TextEditingController {
  TextEditingController();
  void dispose() {}
}
class FocusNode {
  FocusNode();
  void dispose() {}
}
class ScrollController {
  ScrollController();
  void dispose() {}
}
class PageController {
  PageController();
  void dispose() {}
}
class AnimationController {
  AnimationController();
  void dispose() {}
}
class ChangeNotifier {
  void addListener(VoidCallback listener) {}
  void removeListener(VoidCallback listener) {}
  void notifyListeners() {}
  void dispose() {}
}
''',
  'flutter|lib/foundation.dart': r'''
library flutter.foundation;
bool listEquals<T>(List<T>? a, List<T>? b) => false;
''',
  'lively|lib/lively.dart': '''
export 'src/annotations.dart';
export 'src/reactive.dart';
export 'src/live_list.dart';
export 'src/live_set.dart';
export 'src/live_map.dart';
''',
  'lively|lib/src/annotations.dart': '''
class Live {
  const Live();
}
class LiveStore {
  const LiveStore();
}
class Computed {
  const Computed();
}
const computed = Computed();
''',
  'lively|lib/src/reactive.dart': r'''
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
class Reactive extends StatefulWidget {
  final List<dynamic Function()> watch;
  final Widget Function() builder;
  const Reactive({required this.watch, required this.builder});
  @override
  State<Reactive> createState() => throw UnimplementedError();
}
''',
  'lively|lib/src/live_list.dart': r'''
class LiveList<T> {
  LiveList(void Function() notify, {T Function(T)? wrap}) {}
  LiveList.of(Iterable<T> source, void Function() notify, {T Function(T)? wrap}) {}
}
''',
  'lively|lib/src/live_set.dart': r'''
class LiveSet<T> {
  LiveSet(void Function() notify, {T Function(T)? wrap}) {}
  LiveSet.of(Iterable<T> source, void Function() notify, {T Function(T)? wrap}) {}
}
''',
  'lively|lib/src/live_map.dart': r'''
class LiveMap<K, V> {
  LiveMap(void Function() notify,
      {K Function(K)? wrapKey, V Function(V)? wrapValue}) {}
  LiveMap.of(Map<K, V> source, void Function() notify,
      {K Function(K)? wrapKey, V Function(V)? wrapValue}) {}
}
''',
};
