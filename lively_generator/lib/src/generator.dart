import 'dart:async';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:lively/src/annotations.dart' show Live, LiveStore, Computed;
import 'package:lively_generator/src/dart_code_gen_utils.dart';
import 'package:source_gen/source_gen.dart';

class LivelyGenerator extends Generator {
  final _gen = DartCodeGenUtils();

  static final _liveChecker = TypeChecker.fromRuntime(Live);
  static final _liveStoreChecker = TypeChecker.fromRuntime(LiveStore);
  static final _computedChecker = TypeChecker.fromRuntime(Computed);

  // Tracks which _Live<ClassName> proxy classes have been emitted per source
  // file so that two widgets/stores in the same file sharing a type don't
  // produce duplicate class definitions.
  String _currentFileKey = '';
  final Map<String, Set<String>> _emittedByFile = {};

  // Tracks which files have already received the one-time file-level comment.
  final Set<String> _commentedFiles = {};

  static const _fileComment =
      '// GraphQL + Flutter? GraphLink generates a complete, typed, null-safe client\n'
      '// — queries, mutations & subscriptions — directly from your .graphql schema.\n'
      '// https://pub.dev/packages/graphlink';

  static const _disposeMap = <String, String>{
    'TextEditingController': 'dispose',
    'AnimationController': 'dispose',
    'FocusNode': 'dispose',
    'ScrollController': 'dispose',
    'PageController': 'dispose',
    'StreamController': 'close',
    'StreamSubscription': 'cancel',
    'BehaviorSubject': 'close',
  };

  @override
  Future<String?> generate(LibraryReader library, BuildStep buildStep) async {
    final key = buildStep.inputId.path;
    _currentFileKey = key;
    _emittedByFile.putIfAbsent(key, () => {});

    final storeAnnotated = library.annotatedWith(_liveStoreChecker).toList();
    final liveAnnotated = library.annotatedWith(_liveChecker).toList();

    if (storeAnnotated.isEmpty && liveAnnotated.isEmpty) return null;

    await _checkPartDirective(library, buildStep, liveAnnotated, storeAnnotated);

    final parts = <String>[];

    // Stores first so their proxy classes are in _emittedByFile before widgets
    // in the same file are processed.
    for (final el in storeAnnotated) {
      if (el.element is ClassElement) {
        parts.add(_generateStore(el.element as ClassElement));
      }
    }

    for (final el in liveAnnotated) {
      if (el.element is ClassElement) {
        parts.add(_generate(el.element as ClassElement));
      }
    }

    final code = parts.where((p) => p.isNotEmpty).join('\n');
    if (code.isEmpty) return null;
    if (_commentedFiles.add(key)) {
      return '$_fileComment\n\n$code';
    }
    return code;
  }

  Future<void> _checkPartDirective(
    LibraryReader library,
    BuildStep buildStep,
    List<AnnotatedElement> liveAnnotated,
    List<AnnotatedElement> storeAnnotated,
  ) async {
    final inputPath = buildStep.inputId.path;
    final basename = inputPath.split('/').last;
    final expectedPart = basename.replaceAll('.dart', '.g.dart');

    final unit = await buildStep.resolver.compilationUnitFor(buildStep.inputId);

    final hasPart = unit.directives
        .whereType<PartDirective>()
        .any((d) => d.uri.stringValue == expectedPart);

    if (!hasPart) {
      throw InvalidGenerationSourceError(
        "Missing part directive. Add this line near the top of your file:\n\n"
        "    part '$expectedPart';",
        element: [...liveAnnotated, ...storeAnnotated].first.element,
      );
    }

    final classDecls =
        unit.declarations.whereType<ClassDeclaration>().toList();

    for (final el in liveAnnotated) {
      if (el.element is! ClassElement) continue;
      final classEl = el.element as ClassElement;
      final className = classEl.name;
      final expectedBase = '_\$$className';
      final decl = classDecls.firstWhere(
        (d) => d.name.lexeme == className,
        orElse: () => throw StateError('Class $className not found in AST'),
      );
      final actualBase = decl.extendsClause?.superclass.name2.lexeme;
      if (actualBase != expectedBase) {
        throw InvalidGenerationSourceError(
          '@Live() class must extend $expectedBase. '
          'Change your declaration to:\n\n'
          '    class $className extends $expectedBase { ... }',
          element: classEl,
        );
      }
    }

    for (final el in storeAnnotated) {
      if (el.element is! ClassElement) continue;
      final classEl = el.element as ClassElement;
      final specName = classEl.name;
      if (!specName.startsWith('_')) continue; // name check handled in _generateStore
      final publicName = specName.substring(1);
      final expectedBase = '_\$$publicName';
      final decl = classDecls.firstWhere(
        (d) => d.name.lexeme == specName,
        orElse: () => throw StateError('Class $specName not found in AST'),
      );
      final actualBase = decl.extendsClause?.superclass.name2.lexeme;
      if (actualBase != expectedBase) {
        throw InvalidGenerationSourceError(
          '@LiveStore() class must extend $expectedBase. '
          'Change your declaration to:\n\n'
          '    class $specName extends $expectedBase { ... }',
          element: classEl,
        );
      }
    }
  }

  // ── @Live() widget generation ──────────────────────────────────────────────

  String _generate(ClassElement classEl) {
    final className = classEl.name;
    final widgetClassName = '${className}Widget';
    final implClassName = className.startsWith('_')
        ? '_\$${className.substring(1)}Impl'
        : '_${className}Impl';

    final fields =
        classEl.fields.where((f) => !f.isSynthetic && !f.isStatic).toList();

    final paramFields = <FieldElement>[];
    final paramChangeNotifierFields = <FieldElement>[];
    final lateInitChangeNotifierFields = <FieldElement>[];
    final futureFields = <FieldElement>[];
    final streamFields = <FieldElement>[];
    final disposableFields = <FieldElement>[];
    final changeNotifierFields = <FieldElement>[];
    final ownedStoreFields = <FieldElement>[];
    final proxyFields = <FieldElement>[];
    final rxListFields = <FieldElement>[];
    final rxSetFields = <FieldElement>[];
    final rxMapFields = <FieldElement>[];
    final reactiveFields = <FieldElement>[];

    for (final f in fields) {
      if (f.isLate && f.isFinal && !f.hasInitializer) {
        paramFields.add(f);
        if (_isChangeNotifier(f)) paramChangeNotifierFields.add(f);
      } else if (f.isFinal) {
        if (f.isLate && _isChangeNotifier(f)) lateInitChangeNotifierFields.add(f);
      } else if (_isDartFuture(f)) {
        futureFields.add(f);
      } else if (_isDartStream(f)) {
        streamFields.add(f);
      } else if (_isDisposable(f)) {
        disposableFields.add(f);
      } else if (_isChangeNotifier(f)) {
        if (_isOwnedLiveStore(f)) {
          ownedStoreFields.add(f);
        } else {
          changeNotifierFields.add(f);
        }
      } else if (_isProxyable(f)) {
        proxyFields.add(f);
      } else if (_isDartList(f)) {
        rxListFields.add(f);
      } else if (_isDartSet(f)) {
        rxSetFields.add(f);
      } else if (_isDartMap(f)) {
        rxMapFields.add(f);
      } else {
        reactiveFields.add(f);
        _warnIfProxyFallback(f, className);
      }
    }

    final computedGetters = classEl.accessors
        .where((a) => a.isGetter && !a.isSynthetic && _computedChecker.hasAnnotationOf(a))
        .toList();

    final proxyCode = <String>[];
    final effectiveProxyFields = <FieldElement>[];
    for (final f in proxyFields) {
      final cls = f.type.element as ClassElement;
      final code = _generateProxies(cls, {});
      if (code.isNotEmpty) proxyCode.add(code);
      if (_emittedByFile[_currentFileKey]!.contains(cls.name)) {
        effectiveProxyFields.add(f);
      }
    }

    for (final f in [...rxListFields, ...rxSetFields]) {
      final elemCls = _elemClassElement(f);
      if (elemCls != null) {
        if (_isElemProxyable(elemCls)) {
          final code = _generateProxies(elemCls, {});
          if (code.isNotEmpty) proxyCode.add(code);
        } else {
          _warnIfElemProxyFallback(f, elemCls, className);
        }
      }
    }

    for (final f in rxMapFields) {
      final keyCls = _mapKeyClassElement(f);
      if (keyCls != null) {
        if (_isElemProxyable(keyCls)) {
          if (_hasValueEquality(keyCls)) {
            final code = _generateProxies(keyCls, {});
            if (code.isNotEmpty) proxyCode.add(code);
          } else {
            log.warning(
              '[lively] $className.${f.name}: key proxy skipped — '
              '${keyCls.name} does not override == / hashCode. '
              'Wrapping identity-equality keys breaks map[originalKey] lookup; '
              'only structural operations (add/remove/clear) will trigger rebuilds.',
            );
          }
        } else {
          _warnIfElemProxyFallback(f, keyCls, className, isKey: true);
        }
      }
      final valueCls = _mapValueClassElement(f);
      if (valueCls != null) {
        if (_isElemProxyable(valueCls)) {
          final code = _generateProxies(valueCls, {});
          if (code.isNotEmpty) proxyCode.add(code);
        } else {
          _warnIfElemProxyFallback(f, valueCls, className);
        }
      }
    }

    return [
      ...proxyCode,
      _buildWidget(widgetClassName, implClassName, paramFields),
      _buildBase(className, widgetClassName, futureFields, streamFields),
      _buildImpl(
        className,
        implClassName,
        paramFields,
        paramChangeNotifierFields,
        lateInitChangeNotifierFields,
        futureFields,
        streamFields,
        reactiveFields,
        rxListFields,
        rxSetFields,
        rxMapFields,
        disposableFields,
        changeNotifierFields,
        ownedStoreFields,
        effectiveProxyFields,
        computedGetters,
      ),
    ].join('\n');
  }

  // ── thin StatefulWidget wrapper ──────────────────────────────────────────

  String _buildWidget(
    String widgetClassName,
    String implClassName,
    List<FieldElement> paramFields,
  ) {
    final paramArgs = paramFields.map((f) {
      final isNullable = _type(f).endsWith('?');
      return isNullable ? 'this.${f.name}' : 'required this.${f.name}';
    }).toList();

    final ctorArgs = '{${[...paramArgs, 'super.key'].join(', ')}}';
    final constructor = _gen.createConstructor(
      className: 'const $widgetClassName',
      arguments: [ctorArgs],
    );

    final createState = _gen.method(
      returnType: 'State<$widgetClassName>',
      methodName: 'createState',
      arguments: [],
      statements: ['return $implClassName();'],
      override: true,
    );

    return _gen.createClass(
      className: widgetClassName,
      extendsClass: 'StatefulWidget',
      statements: [
        constructor,
        if (paramFields.isNotEmpty) ...[
          '',
          ...paramFields.map((f) => 'final ${_type(f)} ${f.name};'),
        ],
        '',
        createState,
      ],
    );
  }

  // ── abstract State base ──────────────────────────────────────────────────

  String _buildBase(
    String className,
    String widgetClassName,
    List<FieldElement> futureFields,
    List<FieldElement> streamFields,
  ) {
    final scheduleRebuild = _gen.method(
      returnType: 'void',
      methodName: '_scheduleRebuild',
      arguments: [],
      statements: [
        _gen.ifStatement(
            condition: '_dirty', ifBlockStatements: ['return;']),
        '_dirty = true;',
        'Future.microtask(() {\n   _dirty = false;\n   if (mounted) setState(() {});\n});',
      ],
    );
    final notify = _gen.method(
      returnType: 'void',
      methodName: 'notify',
      arguments: [],
      statements: ['_scheduleRebuild();'],
    );
    final initStateStub = _gen.method(
      returnType: 'void',
      methodName: 'initState',
      arguments: [],
      statements: ['super.initState();'],
      override: true,
    );
    final disposeStub = _gen.method(
      returnType: 'void',
      methodName: 'dispose',
      arguments: [],
      statements: ['super.dispose();'],
      override: true,
    );
    // Concrete stubs so the user can call buildX() from their build() method.
    // The impl overrides these with the real switch-on-AsyncValue body.
    final asyncAbstracts = <String>[];
    for (final f in [...futureFields, ...streamFields]) {
      final name = f.name;
      final t = _asyncTypeArg(f);
      final cap = _capitalize(name);
      asyncAbstracts
        ..add('')
        ..add(
          'Widget build$cap({\n'
          '  required Widget Function($t value) data,\n'
          '  Widget Function()? loading,\n'
          '  Widget Function(Object error)? error,\n'
          "}) => throw UnimplementedError('build$cap');",
        );
    }

    return _gen.createInterface(
      className: '_\$$className',
      baseInterfaceNames: ['extends State<$widgetClassName>'],
      statements: [
        'bool _dirty = false;',
        '',
        scheduleRebuild,
        '',
        '/// Trigger a rebuild manually.\n'
            '/// Use this after mutating a nested object field, e.g.:\n'
            '///   todo.done = true;\n'
            '///   notify();',
        notify,
        '',
        '@mustCallSuper',
        initStateStub,
        '',
        '@mustCallSuper',
        disposeStub,
        ...asyncAbstracts,
      ],
    );
  }

  // ── concrete widget impl ─────────────────────────────────────────────────

  String _buildImpl(
    String className,
    String implClassName,
    List<FieldElement> paramFields,
    List<FieldElement> paramChangeNotifierFields,
    List<FieldElement> lateInitChangeNotifierFields,
    List<FieldElement> futureFields,
    List<FieldElement> streamFields,
    List<FieldElement> reactiveFields,
    List<FieldElement> rxListFields,
    List<FieldElement> rxSetFields,
    List<FieldElement> rxMapFields,
    List<FieldElement> disposableFields,
    List<FieldElement> changeNotifierFields,
    List<FieldElement> ownedStoreFields,
    List<FieldElement> proxyFields,
    List<PropertyAccessorElement> computedGetters,
  ) {
    final members = <String>[];
    final dirtyMarks = computedGetters.map((a) => '_\$${a.name}Dirty = true;').toList();
    final dirtyStr = dirtyMarks.isNotEmpty ? ' ${dirtyMarks.join(' ')}' : '';

    // ── @computed backing fields, dirty flags, and getter overrides ──────────
    for (final a in computedGetters) {
      final returnType = a.returnType.getDisplayString(withNullability: true);
      members
        ..add('$returnType? _\$${a.name};')
        ..add('bool _\$${a.name}Dirty = true;')
        ..add(_gen.createMethod(
          returnType: returnType,
          methodName: 'get ${a.name}',
          arguments: null,
          statements: [
            'if (_\$${a.name}Dirty) { _\$${a.name} = super.${a.name}; _\$${a.name}Dirty = false; }',
            'return _\$${a.name}!;',
          ],
          override: true,
        ));
    }

    // ── Future<T> fields ─────────────────────────────────────────────────────
    for (final f in futureFields) {
      final name = f.name;
      final t = _asyncTypeArg(f);
      final cap = _capitalize(name);
      members
        ..add('AsyncValue<$t> _\$${name}State = const AsyncLoading();')
        ..add('int _\$${name}Gen = 0;')
        ..add(_gen.createMethod(
          returnType: 'AsyncValue<$t>',
          methodName: 'get ${name}State',
          arguments: null,
          statements: ['return _\$${name}State;'],
        ))
        ..add(_gen.createMethod(
          returnType: 'set',
          methodName: name,
          arguments: ['Future<$t> v'],
          namedArguments: false,
          statements: [
            'super.$name = v;',
            '_\$${name}State = const AsyncLoading();',
            ...dirtyMarks,
            '_scheduleRebuild();',
            'final \$gen = ++_\$${name}Gen;',
            'v.then((value) { if (mounted && _\$${name}Gen == \$gen) { _\$${name}State = AsyncData(value);$dirtyStr _scheduleRebuild(); } })'
            '.catchError((Object e, StackTrace s) { if (mounted && _\$${name}Gen == \$gen) { _\$${name}State = AsyncError(e, s);$dirtyStr _scheduleRebuild(); } });',
          ],
          override: true,
        ))
        ..add(
          '@override\n'
          'Widget build$cap({\n'
          '  required Widget Function($t value) data,\n'
          '  Widget Function()? loading,\n'
          '  Widget Function(Object error)? error,\n'
          '}) {\n'
          '  final state = _\$${name}State;\n'
          '  if (state is AsyncData<$t>) { return data(state.value); }\n'
          '  if (state is AsyncError<$t>) { return error?.call(state.error) ?? const SizedBox.shrink(); }\n'
          '  return loading?.call() ?? const CircularProgressIndicator();\n'
          '}',
        );
    }

    // ── Stream<T> fields ─────────────────────────────────────────────────────
    for (final f in streamFields) {
      final name = f.name;
      final t = _asyncTypeArg(f);
      final cap = _capitalize(name);
      members
        ..add('AsyncValue<$t> _\$${name}State = const AsyncLoading();')
        ..add('StreamSubscription<$t>? _\$${name}Sub;')
        ..add(_gen.createMethod(
          returnType: 'AsyncValue<$t>',
          methodName: 'get ${name}State',
          arguments: null,
          statements: ['return _\$${name}State;'],
        ))
        ..add(_gen.createMethod(
          returnType: 'set',
          methodName: name,
          arguments: ['Stream<$t> v'],
          namedArguments: false,
          statements: [
            'super.$name = v;',
            '_\$${name}Sub?.cancel();',
            '_\$${name}State = const AsyncLoading();',
            ...dirtyMarks,
            '_scheduleRebuild();',
            '_\$${name}Sub = v.listen(\n'
            '  (value) { if (mounted) { _\$${name}State = AsyncData(value);$dirtyStr _scheduleRebuild(); } },\n'
            '  onError: (Object e, StackTrace s) { if (mounted) { _\$${name}State = AsyncError(e, s);$dirtyStr _scheduleRebuild(); } },\n'
            ');',
          ],
          override: true,
        ))
        ..add(
          '@override\n'
          'Widget build$cap({\n'
          '  required Widget Function($t value) data,\n'
          '  Widget Function()? loading,\n'
          '  Widget Function(Object error)? error,\n'
          '}) {\n'
          '  final state = _\$${name}State;\n'
          '  if (state is AsyncData<$t>) { return data(state.value); }\n'
          '  if (state is AsyncError<$t>) { return error?.call(state.error) ?? const SizedBox.shrink(); }\n'
          '  return loading?.call() ?? const CircularProgressIndicator();\n'
          '}',
        );
    }

    for (final f in reactiveFields) {
      members.add(_gen.createMethod(
        returnType: 'set',
        methodName: f.name,
        arguments: ['${_type(f)} v'],
        namedArguments: false,
        statements: ['super.${f.name} = v;', ...dirtyMarks, '_scheduleRebuild();'],
        override: true,
      ));
    }

    for (final f in changeNotifierFields) {
      final op = _callOp(f);
      members.add(_gen.createMethod(
        returnType: 'set',
        methodName: f.name,
        arguments: ['${_type(f)} v'],
        namedArguments: false,
        statements: [
          'final _old = super.${f.name};',
          '_old${op}removeListener(_scheduleRebuild);',
          'super.${f.name} = v;',
          'v${op}addListener(_scheduleRebuild);',
          ...dirtyMarks,
          '_scheduleRebuild();',
        ],
        override: true,
      ));
    }

    // Owned @LiveStore fields: same listener re-wiring as regular CN setters.
    for (final f in ownedStoreFields) {
      final op = _callOp(f);
      members.add(_gen.createMethod(
        returnType: 'set',
        methodName: f.name,
        arguments: ['${_type(f)} v'],
        namedArguments: false,
        statements: [
          'final _old = super.${f.name};',
          '_old${op}removeListener(_scheduleRebuild);',
          'super.${f.name} = v;',
          'v${op}addListener(_scheduleRebuild);',
          ...dirtyMarks,
          '_scheduleRebuild();',
        ],
        override: true,
      ));
    }

    for (final f in proxyFields) {
      final proxyType = '_Live${(f.type.element as ClassElement).name}';
      members.add(_gen.createMethod(
        returnType: 'set',
        methodName: f.name,
        arguments: ['${_type(f)} v'],
        namedArguments: false,
        statements: [
          'super.${f.name} = $proxyType.from(v, _scheduleRebuild);',
          ...dirtyMarks,
          '_scheduleRebuild();',
        ],
        override: true,
      ));
    }

    for (final f in rxListFields) {
      final name = f.name;
      final listType = _type(f);
      final elemType = _listElemType(f);
      final wrap = _wrapArg(f);
      members
        ..add('late LiveList<$elemType> _\$$name;')
        ..add(_gen.createMethod(
          returnType: listType,
          methodName: 'get $name',
          arguments: null,
          statements: ['return _\$$name;'],
          override: true,
        ))
        ..add(_gen.createMethod(
          returnType: 'set',
          methodName: name,
          arguments: ['$listType v'],
          namedArguments: false,
          statements: [
            '_\$$name = LiveList.of(v, _scheduleRebuild$wrap);',
            ...dirtyMarks,
            '_scheduleRebuild();',
          ],
          override: true,
        ));
    }

    for (final f in rxSetFields) {
      final name = f.name;
      final setType = _type(f);
      final elemType = _setElemType(f);
      final wrap = _wrapArg(f);
      members
        ..add('late LiveSet<$elemType> _\$$name;')
        ..add(_gen.createMethod(
          returnType: setType,
          methodName: 'get $name',
          arguments: null,
          statements: ['return _\$$name;'],
          override: true,
        ))
        ..add(_gen.createMethod(
          returnType: 'set',
          methodName: name,
          arguments: ['$setType v'],
          namedArguments: false,
          statements: [
            '_\$$name = LiveSet.of(v, _scheduleRebuild$wrap);',
            ...dirtyMarks,
            '_scheduleRebuild();',
          ],
          override: true,
        ));
    }

    for (final f in rxMapFields) {
      final name = f.name;
      final mapType = _type(f);
      final keyType = _mapKeyType(f);
      final valueType = _mapValueType(f);
      final wrapKey = _wrapKeyArg(f);
      final wrapValue = _wrapValueArg(f);
      members
        ..add('late LiveMap<$keyType, $valueType> _\$$name;')
        ..add(_gen.createMethod(
          returnType: mapType,
          methodName: 'get $name',
          arguments: null,
          statements: ['return _\$$name;'],
          override: true,
        ))
        ..add(_gen.createMethod(
          returnType: 'set',
          methodName: name,
          arguments: ['$mapType v'],
          namedArguments: false,
          statements: [
            '_\$$name = LiveMap.of(v, _scheduleRebuild$wrapKey$wrapValue);',
            ...dirtyMarks,
            '_scheduleRebuild();',
          ],
          override: true,
        ));
    }

    final needsInitState = paramFields.isNotEmpty ||
        futureFields.isNotEmpty ||
        streamFields.isNotEmpty ||
        rxListFields.isNotEmpty ||
        rxSetFields.isNotEmpty ||
        rxMapFields.isNotEmpty ||
        changeNotifierFields.isNotEmpty ||
        ownedStoreFields.isNotEmpty ||
        lateInitChangeNotifierFields.isNotEmpty ||
        proxyFields.isNotEmpty;

    if (needsInitState) {
      members.add(_gen.method(
        returnType: 'void',
        methodName: 'initState',
        arguments: [],
        statements: [
          ...paramFields.map((f) => 'super.${f.name} = widget.${f.name};'),
          'super.initState();',
          ...rxListFields.map((f) {
            final wrap = _wrapArg(f);
            return '_\$${f.name} = LiveList.of(super.${f.name}, _scheduleRebuild$wrap);';
          }),
          ...rxSetFields.map((f) {
            final wrap = _wrapArg(f);
            return '_\$${f.name} = LiveSet.of(super.${f.name}, _scheduleRebuild$wrap);';
          }),
          ...rxMapFields.map((f) {
            final wrapKey = _wrapKeyArg(f);
            final wrapValue = _wrapValueArg(f);
            return '_\$${f.name} = LiveMap.of(super.${f.name}, _scheduleRebuild$wrapKey$wrapValue);';
          }),
          ...changeNotifierFields
              .map((f) => '${f.name}${_callOp(f)}addListener(_scheduleRebuild);'),
          ...ownedStoreFields
              .map((f) => '${f.name}${_callOp(f)}addListener(_scheduleRebuild);'),
          ...paramChangeNotifierFields
              .map((f) => '${f.name}${_callOp(f)}addListener(_scheduleRebuild);'),
          ...lateInitChangeNotifierFields
              .map((f) => '${f.name}${_callOp(f)}addListener(_scheduleRebuild);'),
          ...proxyFields.map((f) {
            final proxyType = '_Live${(f.type.element as ClassElement).name}';
            return 'super.${f.name} = $proxyType.from(${f.name}, _scheduleRebuild);';
          }),
          ...futureFields.map((f) {
            final name = f.name;
            return '{ final \$gen = ++_\$${name}Gen;\n'
                '  $name.then((value) { if (mounted && _\$${name}Gen == \$gen) { _\$${name}State = AsyncData(value);$dirtyStr _scheduleRebuild(); } })\n'
                '  .catchError((Object e, StackTrace s) { if (mounted && _\$${name}Gen == \$gen) { _\$${name}State = AsyncError(e, s);$dirtyStr _scheduleRebuild(); } }); }';
          }),
          ...streamFields.map((f) {
            final name = f.name;
            final t = _asyncTypeArg(f);
            return '_\$${name}Sub = $name.listen(\n'
                '  (value) { if (mounted) { _\$${name}State = AsyncData(value);$dirtyStr _scheduleRebuild(); } },\n'
                '  onError: (Object e, StackTrace s) { if (mounted) { _\$${name}State = AsyncError(e, s);$dirtyStr _scheduleRebuild(); } },\n'
                ');';
          }),
        ],
        override: true,
      ));
    }

    if (paramFields.isNotEmpty) {
      final widgetClassName = '${className}Widget';
      members.add(_gen.method(
        returnType: 'void',
        methodName: 'didUpdateWidget',
        arguments: ['$widgetClassName old'],
        statements: [
          'super.didUpdateWidget(old);',
          'bool \$changed = false;',
          ...paramFields.map((f) {
            if (paramChangeNotifierFields.contains(f)) {
              final op = _callOp(f);
              return 'if (widget.${f.name} != old.${f.name}) { '
                  'old.${f.name}${op}removeListener(_scheduleRebuild); '
                  'super.${f.name} = widget.${f.name}; '
                  '${f.name}${op}addListener(_scheduleRebuild); '
                  '\$changed = true; }';
            }
            return 'if (widget.${f.name} != old.${f.name}) { super.${f.name} = widget.${f.name}; \$changed = true; }';
          }),
          'if (\$changed) _scheduleRebuild();',
        ],
        override: true,
      ));
    }

    final needsDispose = disposableFields.isNotEmpty ||
        streamFields.isNotEmpty ||
        changeNotifierFields.isNotEmpty ||
        ownedStoreFields.isNotEmpty ||
        paramChangeNotifierFields.isNotEmpty ||
        lateInitChangeNotifierFields.isNotEmpty;

    if (needsDispose) {
      members.add(_gen.method(
        returnType: 'void',
        methodName: 'dispose',
        arguments: [],
        statements: [
          ...streamFields.map((f) => '_\$${f.name}Sub?.cancel();'),
          ...disposableFields.map((f) => '${f.name}${_callOp(f)}${_disposeMethod(f)}();'),
          ...changeNotifierFields
              .map((f) => '${f.name}${_callOp(f)}removeListener(_scheduleRebuild);'),
          // Owned @LiveStore: remove listener first, then dispose.
          ...ownedStoreFields
              .map((f) => '${f.name}${_callOp(f)}removeListener(_scheduleRebuild);'),
          ...ownedStoreFields.map((f) => '${f.name}${_callOp(f)}dispose();'),
          ...paramChangeNotifierFields
              .map((f) => '${f.name}${_callOp(f)}removeListener(_scheduleRebuild);'),
          ...lateInitChangeNotifierFields
              .map((f) => '${f.name}${_callOp(f)}removeListener(_scheduleRebuild);'),
          'super.dispose();',
        ],
        override: true,
      ));
    }

    final separated = members.expand((m) => [m, '']).toList();
    if (separated.isNotEmpty) separated.removeLast();
    return _gen.createClass(
      className: implClassName,
      extendsClass: className,
      statements: separated,
    );
  }

  // ── @LiveStore generation ─────────────────────────────────────────────────

  String _generateStore(ClassElement classEl) {
    if (!classEl.name.startsWith('_')) {
      throw InvalidGenerationSourceError(
        '@LiveStore() class names must start with _ '
        '(e.g. class _UserStore → generates class UserStore). '
        'This lets the generator emit the public concrete class under the expected name.',
        element: classEl,
      );
    }

    final specName = classEl.name;              // e.g. _UserStore
    final publicName = specName.substring(1);   // e.g. UserStore
    final baseName = '_\$$publicName';          // e.g. _$UserStore

    final fields =
        classEl.fields.where((f) => !f.isSynthetic && !f.isStatic).toList();

    final paramFields = <FieldElement>[];
    final paramCNFields = <FieldElement>[];
    final lateInitCNFields = <FieldElement>[];
    final futureFields = <FieldElement>[];
    final streamFields = <FieldElement>[];
    final disposableFields = <FieldElement>[];
    final cnFields = <FieldElement>[];
    final ownedStoreFields = <FieldElement>[];
    final proxyFields = <FieldElement>[];
    final rxListFields = <FieldElement>[];
    final rxSetFields = <FieldElement>[];
    final rxMapFields = <FieldElement>[];
    final reactiveFields = <FieldElement>[];

    for (final f in fields) {
      if (f.isLate && f.isFinal && !f.hasInitializer) {
        paramFields.add(f);
        if (_isChangeNotifier(f)) paramCNFields.add(f);
      } else if (f.isFinal) {
        if (f.isLate && _isChangeNotifier(f)) lateInitCNFields.add(f);
      } else if (_isDartFuture(f)) {
        futureFields.add(f);
      } else if (_isDartStream(f)) {
        streamFields.add(f);
      } else if (_isDisposable(f)) {
        disposableFields.add(f);
      } else if (_isChangeNotifier(f)) {
        if (_isOwnedLiveStore(f)) {
          ownedStoreFields.add(f);
        } else {
          cnFields.add(f);
        }
      } else if (_isProxyable(f)) {
        proxyFields.add(f);
      } else if (_isDartList(f)) {
        rxListFields.add(f);
      } else if (_isDartSet(f)) {
        rxSetFields.add(f);
      } else if (_isDartMap(f)) {
        rxMapFields.add(f);
      } else {
        reactiveFields.add(f);
        _warnIfProxyFallback(f, specName);
      }
    }

    final computedGetters = classEl.accessors
        .where((a) => a.isGetter && !a.isSynthetic && _computedChecker.hasAnnotationOf(a))
        .toList();

    final proxyCode = <String>[];
    final effectiveProxyFields = <FieldElement>[];
    for (final f in proxyFields) {
      final cls = f.type.element as ClassElement;
      final code = _generateProxies(cls, {});
      if (code.isNotEmpty) proxyCode.add(code);
      if (_emittedByFile[_currentFileKey]!.contains(cls.name)) {
        effectiveProxyFields.add(f);
      }
    }

    for (final f in [...rxListFields, ...rxSetFields]) {
      final elemCls = _elemClassElement(f);
      if (elemCls != null) {
        if (_isElemProxyable(elemCls)) {
          final code = _generateProxies(elemCls, {});
          if (code.isNotEmpty) proxyCode.add(code);
        } else {
          _warnIfElemProxyFallback(f, elemCls, specName);
        }
      }
    }

    for (final f in rxMapFields) {
      final keyCls = _mapKeyClassElement(f);
      if (keyCls != null) {
        if (_isElemProxyable(keyCls)) {
          if (_hasValueEquality(keyCls)) {
            final code = _generateProxies(keyCls, {});
            if (code.isNotEmpty) proxyCode.add(code);
          } else {
            log.warning(
              '[lively] $specName.${f.name}: key proxy skipped — '
              '${keyCls.name} does not override == / hashCode.',
            );
          }
        } else {
          _warnIfElemProxyFallback(f, keyCls, specName, isKey: true);
        }
      }
      final valueCls = _mapValueClassElement(f);
      if (valueCls != null) {
        if (_isElemProxyable(valueCls)) {
          final code = _generateProxies(valueCls, {});
          if (code.isNotEmpty) proxyCode.add(code);
        } else {
          _warnIfElemProxyFallback(f, valueCls, specName);
        }
      }
    }

    return [
      ...proxyCode,
      _buildStoreBase(baseName),
      _buildStoreImpl(
        publicName,
        specName,
        paramFields,
        paramCNFields,
        lateInitCNFields,
        futureFields,
        streamFields,
        reactiveFields,
        cnFields,
        ownedStoreFields,
        rxListFields,
        rxSetFields,
        rxMapFields,
        disposableFields,
        effectiveProxyFields,
        computedGetters,
      ),
      _buildStoreProvider(publicName),
    ].join('\n');
  }

  String _buildStoreProvider(String publicName) {
    final providerName = '${publicName}Provider';
    final sb = StringBuffer();
    sb.writeln('class $providerName extends InheritedNotifier<$publicName> {');
    sb.writeln('  const $providerName({');
    sb.writeln('    super.key,');
    sb.writeln('    required $publicName store,');
    sb.writeln('    required super.child,');
    sb.writeln('  }) : super(notifier: store);');
    sb.writeln();
    sb.writeln('  static $publicName of(BuildContext context) {');
    sb.writeln('    final result = context');
    sb.writeln('        .dependOnInheritedWidgetOfExactType<$providerName>();');
    sb.writeln("    assert(result != null, 'No $providerName found in widget tree.');");
    sb.writeln('    return result!.notifier!;');
    sb.writeln('  }');
    sb.writeln();
    sb.writeln('  static $publicName? maybeOf(BuildContext context) =>');
    sb.writeln('      context.dependOnInheritedWidgetOfExactType<$providerName>()?.notifier;');
    sb.writeln('}');
    return sb.toString();
  }

  // ── abstract ChangeNotifier base ─────────────────────────────────────────

  String _buildStoreBase(String baseName) {
    final scheduleNotify = _gen.method(
      returnType: 'void',
      methodName: '_scheduleNotify',
      arguments: [],
      statements: [
        _gen.ifStatement(
            condition: '_dirty', ifBlockStatements: ['return;']),
        '_dirty = true;',
        'Future.microtask(() {\n   _dirty = false;\n   notifyListeners();\n});',
      ],
    );
    final notify = _gen.method(
      returnType: 'void',
      methodName: 'notify',
      arguments: [],
      statements: ['_scheduleNotify();'],
    );
    final disposeStub = _gen.method(
      returnType: 'void',
      methodName: 'dispose',
      arguments: [],
      statements: ['super.dispose();'],
      override: true,
    );
    return _gen.createInterface(
      className: baseName,
      baseInterfaceNames: ['extends ChangeNotifier'],
      statements: [
        'bool _dirty = false;',
        '',
        scheduleNotify,
        '',
        '/// Trigger notifyListeners() manually — use after direct mutations\n'
            '/// on nested objects not tracked by a proxy.',
        notify,
        '',
        '@mustCallSuper',
        disposeStub,
      ],
    );
  }

  // ── public concrete store impl ───────────────────────────────────────────

  String _buildStoreImpl(
    String publicName,
    String specName,
    List<FieldElement> paramFields,
    List<FieldElement> paramCNFields,
    List<FieldElement> lateInitCNFields,
    List<FieldElement> futureFields,
    List<FieldElement> streamFields,
    List<FieldElement> reactiveFields,
    List<FieldElement> cnFields,
    List<FieldElement> ownedStoreFields,
    List<FieldElement> rxListFields,
    List<FieldElement> rxSetFields,
    List<FieldElement> rxMapFields,
    List<FieldElement> disposableFields,
    List<FieldElement> proxyFields,
    List<PropertyAccessorElement> computedGetters,
  ) {
    final members = <String>[];
    final dirtyMarks = computedGetters.map((a) => '_\$${a.name}Dirty = true;').toList();
    final dirtyStr = dirtyMarks.isNotEmpty ? ' ${dirtyMarks.join(' ')}' : '';

    // ── @computed backing fields, dirty flags, and getter overrides ──────────
    for (final a in computedGetters) {
      final returnType = a.returnType.getDisplayString(withNullability: true);
      members
        ..add('$returnType? _\$${a.name};')
        ..add('bool _\$${a.name}Dirty = true;')
        ..add(_gen.createMethod(
          returnType: returnType,
          methodName: 'get ${a.name}',
          arguments: null,
          statements: [
            'if (_\$${a.name}Dirty) { _\$${a.name} = super.${a.name}; _\$${a.name}Dirty = false; }',
            'return _\$${a.name}!;',
          ],
          override: true,
        ));
    }

    // ── Future<T> fields ─────────────────────────────────────────────────────
    if (futureFields.isNotEmpty || streamFields.isNotEmpty) {
      members.add('bool _\$asyncDisposed = false;');
    }

    for (final f in futureFields) {
      final name = f.name;
      final t = _asyncTypeArg(f);
      members
        ..add('AsyncValue<$t> _\$${name}State = const AsyncLoading();')
        ..add('int _\$${name}Gen = 0;')
        ..add(_gen.createMethod(
          returnType: 'AsyncValue<$t>',
          methodName: 'get ${name}State',
          arguments: null,
          statements: ['return _\$${name}State;'],
        ))
        ..add(_gen.createMethod(
          returnType: 'set',
          methodName: name,
          arguments: ['Future<$t> v'],
          namedArguments: false,
          statements: [
            'super.$name = v;',
            '_\$${name}State = const AsyncLoading();',
            ...dirtyMarks,
            '_scheduleNotify();',
            'final \$gen = ++_\$${name}Gen;',
            'v.then((value) { if (!_\$asyncDisposed && _\$${name}Gen == \$gen) { _\$${name}State = AsyncData(value);$dirtyStr _scheduleNotify(); } })'
            '.catchError((Object e, StackTrace s) { if (!_\$asyncDisposed && _\$${name}Gen == \$gen) { _\$${name}State = AsyncError(e, s);$dirtyStr _scheduleNotify(); } });',
          ],
          override: true,
        ));
    }

    // ── Stream<T> fields ─────────────────────────────────────────────────────
    for (final f in streamFields) {
      final name = f.name;
      final t = _asyncTypeArg(f);
      members
        ..add('AsyncValue<$t> _\$${name}State = const AsyncLoading();')
        ..add('StreamSubscription<$t>? _\$${name}Sub;')
        ..add(_gen.createMethod(
          returnType: 'AsyncValue<$t>',
          methodName: 'get ${name}State',
          arguments: null,
          statements: ['return _\$${name}State;'],
        ))
        ..add(_gen.createMethod(
          returnType: 'set',
          methodName: name,
          arguments: ['Stream<$t> v'],
          namedArguments: false,
          statements: [
            'super.$name = v;',
            '_\$${name}Sub?.cancel();',
            '_\$${name}State = const AsyncLoading();',
            ...dirtyMarks,
            '_scheduleNotify();',
            '_\$${name}Sub = v.listen(\n'
            '  (value) { if (!_\$asyncDisposed) { _\$${name}State = AsyncData(value);$dirtyStr _scheduleNotify(); } },\n'
            '  onError: (Object e, StackTrace s) { if (!_\$asyncDisposed) { _\$${name}State = AsyncError(e, s);$dirtyStr _scheduleNotify(); } },\n'
            ');',
          ],
          override: true,
        ));
    }

    // ── reactive scalar setters ──────────────────────────────────────────
    for (final f in reactiveFields) {
      members.add(_gen.createMethod(
        returnType: 'set',
        methodName: f.name,
        arguments: ['${_type(f)} v'],
        namedArguments: false,
        statements: ['super.${f.name} = v;', ...dirtyMarks, '_scheduleNotify();'],
        override: true,
      ));
    }

    // ── CN field setters (borrowed — re-wire listener on replacement) ────
    for (final f in cnFields) {
      final op = _callOp(f);
      members.add(_gen.createMethod(
        returnType: 'set',
        methodName: f.name,
        arguments: ['${_type(f)} v'],
        namedArguments: false,
        statements: [
          'final _old = super.${f.name};',
          '_old${op}removeListener(_scheduleNotify);',
          'super.${f.name} = v;',
          'v${op}addListener(_scheduleNotify);',
          ...dirtyMarks,
          '_scheduleNotify();',
        ],
        override: true,
      ));
    }

    // ── owned @LiveStore field setters (re-wire listener on replacement) ─
    for (final f in ownedStoreFields) {
      final op = _callOp(f);
      members.add(_gen.createMethod(
        returnType: 'set',
        methodName: f.name,
        arguments: ['${_type(f)} v'],
        namedArguments: false,
        statements: [
          'final _old = super.${f.name};',
          '_old${op}removeListener(_scheduleNotify);',
          'super.${f.name} = v;',
          'v${op}addListener(_scheduleNotify);',
          ...dirtyMarks,
          '_scheduleNotify();',
        ],
        override: true,
      ));
    }

    // ── proxy field setters ──────────────────────────────────────────────
    for (final f in proxyFields) {
      final proxyType = '_Live${(f.type.element as ClassElement).name}';
      members.add(_gen.createMethod(
        returnType: 'set',
        methodName: f.name,
        arguments: ['${_type(f)} v'],
        namedArguments: false,
        statements: [
          'super.${f.name} = $proxyType.from(v, _scheduleNotify);',
          ...dirtyMarks,
          '_scheduleNotify();',
        ],
        override: true,
      ));
    }

    // ── reactive collection backing fields + getters + setters ───────────
    for (final f in rxListFields) {
      final name = f.name;
      final listType = _type(f);
      final elemType = _listElemType(f);
      final wrap = _wrapArgForRef(f, '_scheduleNotify');
      members
        ..add('late LiveList<$elemType> _\$$name;')
        ..add(_gen.createMethod(
          returnType: listType,
          methodName: 'get $name',
          arguments: null,
          statements: ['return _\$$name;'],
          override: true,
        ))
        ..add(_gen.createMethod(
          returnType: 'set',
          methodName: name,
          arguments: ['$listType v'],
          namedArguments: false,
          statements: [
            '_\$$name = LiveList.of(v, _scheduleNotify$wrap);',
            ...dirtyMarks,
            '_scheduleNotify();',
          ],
          override: true,
        ));
    }

    for (final f in rxSetFields) {
      final name = f.name;
      final setType = _type(f);
      final elemType = _setElemType(f);
      final wrap = _wrapArgForRef(f, '_scheduleNotify');
      members
        ..add('late LiveSet<$elemType> _\$$name;')
        ..add(_gen.createMethod(
          returnType: setType,
          methodName: 'get $name',
          arguments: null,
          statements: ['return _\$$name;'],
          override: true,
        ))
        ..add(_gen.createMethod(
          returnType: 'set',
          methodName: name,
          arguments: ['$setType v'],
          namedArguments: false,
          statements: [
            '_\$$name = LiveSet.of(v, _scheduleNotify$wrap);',
            ...dirtyMarks,
            '_scheduleNotify();',
          ],
          override: true,
        ));
    }

    for (final f in rxMapFields) {
      final name = f.name;
      final mapType = _type(f);
      final keyType = _mapKeyType(f);
      final valueType = _mapValueType(f);
      final wrapKey = _wrapKeyArgForRef(f, '_scheduleNotify');
      final wrapValue = _wrapValueArgForRef(f, '_scheduleNotify');
      members
        ..add('late LiveMap<$keyType, $valueType> _\$$name;')
        ..add(_gen.createMethod(
          returnType: mapType,
          methodName: 'get $name',
          arguments: null,
          statements: ['return _\$$name;'],
          override: true,
        ))
        ..add(_gen.createMethod(
          returnType: 'set',
          methodName: name,
          arguments: ['$mapType v'],
          namedArguments: false,
          statements: [
            '_\$$name = LiveMap.of(v, _scheduleNotify$wrapKey$wrapValue);',
            ...dirtyMarks,
            '_scheduleNotify();',
          ],
          override: true,
        ));
    }

    // ── constructor ──────────────────────────────────────────────────────
    final ctorParams = paramFields.map((f) {
      final isNullable = _type(f).endsWith('?');
      return isNullable ? '${_type(f)} ${f.name}' : 'required ${_type(f)} ${f.name}';
    }).toList();

    final ctorBody = <String>[
      // Set constructor params before anything else.
      ...paramFields.map((f) => 'super.${f.name} = ${f.name};'),
      // Wire CN params (borrowed — addListener only, no dispose).
      ...paramCNFields.map((f) => '${f.name}${_callOp(f)}addListener(_scheduleNotify);'),
      // Wire late-init CN fields (triggers lazy initializer).
      ...lateInitCNFields.map((f) => '${f.name}${_callOp(f)}addListener(_scheduleNotify);'),
      // Init reactive collections from field initial values.
      ...rxListFields.map((f) {
        final wrap = _wrapArgForRef(f, '_scheduleNotify');
        return '_\$${f.name} = LiveList.of(super.${f.name}, _scheduleNotify$wrap);';
      }),
      ...rxSetFields.map((f) {
        final wrap = _wrapArgForRef(f, '_scheduleNotify');
        return '_\$${f.name} = LiveSet.of(super.${f.name}, _scheduleNotify$wrap);';
      }),
      ...rxMapFields.map((f) {
        final wrapKey = _wrapKeyArgForRef(f, '_scheduleNotify');
        final wrapValue = _wrapValueArgForRef(f, '_scheduleNotify');
        return '_\$${f.name} = LiveMap.of(super.${f.name}, _scheduleNotify$wrapKey$wrapValue);';
      }),
      // Wire borrowed CN fields.
      ...cnFields.map((f) => '${f.name}${_callOp(f)}addListener(_scheduleNotify);'),
      // Wire owned @LiveStore fields.
      ...ownedStoreFields.map((f) => '${f.name}${_callOp(f)}addListener(_scheduleNotify);'),
      // Wrap proxy fields with their reactive proxy.
      ...proxyFields.map((f) {
        final proxyType = '_Live${(f.type.element as ClassElement).name}';
        return 'super.${f.name} = $proxyType.from(super.${f.name}, _scheduleNotify);';
      }),
      // Wire Future fields.
      ...futureFields.map((f) {
        final name = f.name;
        return '{ final \$gen = ++_\$${name}Gen;\n'
            '  $name.then((value) { if (!_\$asyncDisposed && _\$${name}Gen == \$gen) { _\$${name}State = AsyncData(value);$dirtyStr _scheduleNotify(); } })\n'
            '  .catchError((Object e, StackTrace s) { if (!_\$asyncDisposed && _\$${name}Gen == \$gen) { _\$${name}State = AsyncError(e, s);$dirtyStr _scheduleNotify(); } }); }';
      }),
      // Wire Stream fields.
      ...streamFields.map((f) {
        final name = f.name;
        final t = _asyncTypeArg(f);
        return '_\$${name}Sub = $name.listen(\n'
            '  (value) { if (!_\$asyncDisposed) { _\$${name}State = AsyncData(value);$dirtyStr _scheduleNotify(); } },\n'
            '  onError: (Object e, StackTrace s) { if (!_\$asyncDisposed) { _\$${name}State = AsyncError(e, s);$dirtyStr _scheduleNotify(); } },\n'
            ');';
      }),
    ];

    final hasCtorContent = ctorParams.isNotEmpty || ctorBody.isNotEmpty;
    if (hasCtorContent) {
      final argsStr = ctorParams.isNotEmpty
          ? '{${ctorParams.join(', ')}}'
          : null;
      members.add(_gen.createConstructor(
        className: publicName,
        arguments: argsStr != null ? [argsStr] : null,
        statements: ctorBody.isNotEmpty ? ctorBody : null,
      ));
    }

    // ── dispose ──────────────────────────────────────────────────────────
    final disposeStatements = <String>[
      if (futureFields.isNotEmpty || streamFields.isNotEmpty)
        '_\$asyncDisposed = true;',
      ...streamFields.map((f) => '_\$${f.name}Sub?.cancel();'),
      ...disposableFields.map((f) => '${f.name}${_callOp(f)}${_disposeMethod(f)}();'),
      ...cnFields.map((f) => '${f.name}${_callOp(f)}removeListener(_scheduleNotify);'),
      ...paramCNFields.map((f) => '${f.name}${_callOp(f)}removeListener(_scheduleNotify);'),
      ...lateInitCNFields.map((f) => '${f.name}${_callOp(f)}removeListener(_scheduleNotify);'),
      // Owned @LiveStore: remove listener, then dispose.
      ...ownedStoreFields.map((f) => '${f.name}${_callOp(f)}removeListener(_scheduleNotify);'),
      ...ownedStoreFields.map((f) => '${f.name}${_callOp(f)}dispose();'),
    ];

    final needsDispose = disposeStatements.isNotEmpty;
    if (needsDispose) {
      members.add(_gen.method(
        returnType: 'void',
        methodName: 'dispose',
        arguments: [],
        statements: [...disposeStatements, 'super.dispose();'],
        override: true,
      ));
    }

    final separated = members.expand((m) => [m, '']).toList();
    if (separated.isNotEmpty) separated.removeLast();
    return _gen.createClass(
      className: publicName,
      extendsClass: specName,
      statements: separated,
    );
  }

  // ── proxy class generation (recursive) ───────────────────────────────────

  String _generateProxies(ClassElement cls, Set<String> inProgress) {
    final emitted = _emittedByFile[_currentFileKey]!;
    if (emitted.contains(cls.name)) return '';
    if (inProgress.contains(cls.name)) return ''; // cycle
    if (!_hasDefaultConstructor(cls)) return '';

    final inProg = {...inProgress, cls.name};
    final mutableFields = cls.fields
        .where((f) =>
            !f.isSynthetic &&
            !f.isStatic &&
            !f.isFinal &&
            !f.name.startsWith('_'))
        .toList();

    final nestedCode = <String>[];
    final backingFields = <String>[];
    final gettersSetters = <String>[];
    final ctorParts = <String>[];

    for (final f in mutableFields) {
      final t = _type(f);
      if (_isDartList(f)) {
        final elemType = _listElemType(f);
        final elemCls = _elemClassElement(f);
        if (elemCls != null && _isElemProxyable(elemCls)) {
          final code = _generateProxies(elemCls, inProg);
          if (code.isNotEmpty) nestedCode.add(code);
        }
        final wrapCtor   = _wrapArgForRef(f, 'notify');
        final wrapSetter = _wrapArgForRef(f, '_notify');
        backingFields.add('LiveList<$elemType> _${f.name};');
        gettersSetters
          ..add('@override $t get ${f.name} => _${f.name};')
          ..add('@override set ${f.name}($t v) { _${f.name} = LiveList.of(v, _notify$wrapSetter); _notify(); }');
        ctorParts.add('_${f.name} = LiveList.of(src.${f.name}, notify$wrapCtor)');
      } else if (_isDartSet(f)) {
        final elemType = _setElemType(f);
        final elemCls = _elemClassElement(f);
        if (elemCls != null && _isElemProxyable(elemCls)) {
          final code = _generateProxies(elemCls, inProg);
          if (code.isNotEmpty) nestedCode.add(code);
        }
        final wrapCtor   = _wrapArgForRef(f, 'notify');
        final wrapSetter = _wrapArgForRef(f, '_notify');
        backingFields.add('LiveSet<$elemType> _${f.name};');
        gettersSetters
          ..add('@override $t get ${f.name} => _${f.name};')
          ..add('@override set ${f.name}($t v) { _${f.name} = LiveSet.of(v, _notify$wrapSetter); _notify(); }');
        ctorParts.add('_${f.name} = LiveSet.of(src.${f.name}, notify$wrapCtor)');
      } else if (_isDartMap(f)) {
        final keyType = _mapKeyType(f);
        final valueType = _mapValueType(f);
        final keyCls = _mapKeyClassElement(f);
        final valueCls = _mapValueClassElement(f);
        if (keyCls != null && _isElemProxyable(keyCls) && _hasValueEquality(keyCls)) {
          final code = _generateProxies(keyCls, inProg);
          if (code.isNotEmpty) nestedCode.add(code);
        }
        if (valueCls != null && _isElemProxyable(valueCls)) {
          final code = _generateProxies(valueCls, inProg);
          if (code.isNotEmpty) nestedCode.add(code);
        }
        final wrapKeyCtor    = _wrapKeyArgForRef(f, 'notify');
        final wrapKeySetter  = _wrapKeyArgForRef(f, '_notify');
        final wrapValueCtor  = _wrapValueArgForRef(f, 'notify');
        final wrapValueSetter = _wrapValueArgForRef(f, '_notify');
        backingFields.add('LiveMap<$keyType, $valueType> _${f.name};');
        gettersSetters
          ..add('@override $t get ${f.name} => _${f.name};')
          ..add('@override set ${f.name}($t v) { _${f.name} = LiveMap.of(v, _notify$wrapKeySetter$wrapValueSetter); _notify(); }');
        ctorParts.add('_${f.name} = LiveMap.of(src.${f.name}, notify$wrapKeyCtor$wrapValueCtor)');
      } else if (_isPrimitive(f)) {
        backingFields.add('$t _${f.name};');
        gettersSetters
          ..add('@override $t get ${f.name} => _${f.name};')
          ..add('@override set ${f.name}($t v) { _${f.name} = v; _notify(); }');
        ctorParts.add('_${f.name} = src.${f.name}');
      } else if (_isProxyable(f)) {
        final nested = f.type.element as ClassElement;
        final code = _generateProxies(nested, inProg);
        if (code.isNotEmpty) nestedCode.add(code);
        final pt = '_Live${nested.name}';
        backingFields.add('$pt _${f.name};');
        gettersSetters
          ..add('@override $pt get ${f.name} => _${f.name};')
          ..add('@override set ${f.name}($t v) { _${f.name} = $pt.from(v, _notify); _notify(); }');
        ctorParts.add('_${f.name} = $pt.from(src.${f.name}, notify)');
      }
    }

    emitted.add(cls.name);

    final proxyName = '_Live${cls.name}';
    final allCtorParts = ['_notify = notify', ...ctorParts];
    final ctorInit = allCtorParts.join(',\n      ');

    final sb = StringBuffer();
    for (final c in nestedCode) {
      sb.writeln(c);
    }
    sb.writeln('class $proxyName extends ${cls.name} {');
    sb.writeln('  final VoidCallback _notify;');
    if (backingFields.isNotEmpty) {
      sb.writeln('  ${backingFields.join('\n  ')}');
    }
    sb.writeln();
    sb.writeln('  $proxyName.from(${cls.name} src, VoidCallback notify)');
    sb.writeln('      : $ctorInit;');
    if (gettersSetters.isNotEmpty) {
      sb.writeln();
      sb.writeln('  ${gettersSetters.join('\n  ')}');
    }
    sb.writeln('}');

    return sb.toString();
  }

  // ── proxy-fallback warnings ──────────────────────────────────────────────

  void _warnIfProxyFallback(FieldElement f, String widgetClass) {
    if (_isPrimitive(f)) return;
    if (_isDisposable(f)) return;
    if (_isChangeNotifier(f)) return;
    if (_isDartList(f) || _isDartSet(f) || _isDartMap(f)) return;
    final element = f.type.element;
    if (element is! ClassElement) return;

    final String reason;
    if (element.isFinal) {
      reason = '${element.name} is final and cannot be subclassed';
    } else if (element.isSealed) {
      reason = '${element.name} is sealed and cannot be subclassed';
    } else if (!_hasDefaultConstructor(element)) {
      reason = '${element.name} has no no-arg or all-optional constructor';
    } else {
      return;
    }
    log.warning(
      '[lively] $widgetClass.${f.name}: proxy skipped — $reason. '
      'Nested field mutations will NOT trigger rebuilds; '
      'only reassigning ${f.name} itself will.',
    );
  }

  void _warnIfElemProxyFallback(
    FieldElement f,
    ClassElement elemCls,
    String widgetClass, {
    bool isKey = false,
  }) {
    if (elemCls.library.isDartCore) return;
    final String reason;
    if (elemCls.isFinal) {
      reason = '${elemCls.name} is final and cannot be subclassed';
    } else if (elemCls.isSealed) {
      reason = '${elemCls.name} is sealed and cannot be subclassed';
    } else if (!_hasDefaultConstructor(elemCls)) {
      reason = '${elemCls.name} has no no-arg or all-optional constructor';
    } else {
      return;
    }
    final role = isKey ? 'key' : 'element';
    log.warning(
      '[lively] $widgetClass.${f.name}: $role proxy skipped — $reason. '
      'Item-level field mutations will NOT trigger rebuilds; '
      'only structural operations (add/remove/clear) will.',
    );
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  String _type(FieldElement f) =>
      f.type.getDisplayString(withNullability: true);

  bool _isDartList(FieldElement f) => f.type.element?.name == 'List';

  bool _isDartSet(FieldElement f) => f.type.element?.name == 'Set';

  bool _isDartMap(FieldElement f) => f.type.element?.name == 'Map';

  bool _isDartFuture(FieldElement f) => f.type.element?.name == 'Future';

  bool _isDartStream(FieldElement f) => f.type.element?.name == 'Stream';

  String _asyncTypeArg(FieldElement f) {
    final type = f.type;
    if (type is! InterfaceType || type.typeArguments.isEmpty) return 'dynamic';
    return type.typeArguments.first.getDisplayString(withNullability: true);
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _listElemType(FieldElement f) {
    final full = _type(f);
    final match = RegExp(r'^List<(.+)>$').firstMatch(full);
    return match?.group(1) ?? 'dynamic';
  }

  String _setElemType(FieldElement f) {
    final full = _type(f);
    final match = RegExp(r'^Set<(.+)>$').firstMatch(full);
    return match?.group(1) ?? 'dynamic';
  }

  ClassElement? _elemClassElement(FieldElement f) {
    final type = f.type;
    if (type is! InterfaceType) return null;
    final args = type.typeArguments;
    if (args.isEmpty) return null;
    final elem = args.first.element;
    return elem is ClassElement ? elem : null;
  }

  String _mapKeyType(FieldElement f) {
    final type = f.type;
    if (type is! InterfaceType || type.typeArguments.length < 2) return 'dynamic';
    return type.typeArguments[0].getDisplayString(withNullability: true);
  }

  String _mapValueType(FieldElement f) {
    final type = f.type;
    if (type is! InterfaceType || type.typeArguments.length < 2) return 'dynamic';
    return type.typeArguments[1].getDisplayString(withNullability: true);
  }

  ClassElement? _mapKeyClassElement(FieldElement f) {
    final type = f.type;
    if (type is! InterfaceType || type.typeArguments.length < 2) return null;
    final elem = type.typeArguments[0].element;
    return elem is ClassElement ? elem : null;
  }

  ClassElement? _mapValueClassElement(FieldElement f) {
    final type = f.type;
    if (type is! InterfaceType || type.typeArguments.length < 2) return null;
    final elem = type.typeArguments[1].element;
    return elem is ClassElement ? elem : null;
  }

  bool _hasValueEquality(ClassElement cls) {
    if (cls.library.isDartCore) return true;
    return cls.methods.any((m) => m.name == '==') ||
        cls.accessors.any((a) => a.isGetter && a.name == 'hashCode');
  }

  bool _isElemProxyable(ClassElement cls) {
    if (cls.library.isDartCore) return false;
    if (cls.isAbstract || cls.isFinal || cls.isSealed) return false;
    return _hasDefaultConstructor(cls);
  }

  String _wrapArg(FieldElement f) => _wrapArgForRef(f, '_scheduleRebuild');

  String _wrapArgForRef(FieldElement f, String notifyRef) {
    final elemCls = _elemClassElement(f);
    if (elemCls == null) return '';
    final emitted = _emittedByFile[_currentFileKey] ?? {};
    if (!emitted.contains(elemCls.name)) return '';
    return ', wrap: (e) => _Live${elemCls.name}.from(e, $notifyRef)';
  }

  String _wrapKeyArg(FieldElement f) => _wrapKeyArgForRef(f, '_scheduleRebuild');
  String _wrapValueArg(FieldElement f) => _wrapValueArgForRef(f, '_scheduleRebuild');

  String _wrapKeyArgForRef(FieldElement f, String notifyRef) {
    final keyCls = _mapKeyClassElement(f);
    if (keyCls == null) return '';
    final emitted = _emittedByFile[_currentFileKey] ?? {};
    if (!emitted.contains(keyCls.name)) return '';
    if (!_hasValueEquality(keyCls)) return '';
    return ', wrapKey: (k) => _Live${keyCls.name}.from(k, $notifyRef)';
  }

  String _wrapValueArgForRef(FieldElement f, String notifyRef) {
    final valueCls = _mapValueClassElement(f);
    if (valueCls == null) return '';
    final emitted = _emittedByFile[_currentFileKey] ?? {};
    if (!emitted.contains(valueCls.name)) return '';
    return ', wrapValue: (v) => _Live${valueCls.name}.from(v, $notifyRef)';
  }

  bool _isDisposable(FieldElement f) =>
      _disposeMap.containsKey(f.type.element?.name);

  String _disposeMethod(FieldElement f) =>
      _disposeMap[f.type.element?.name] ?? 'dispose';

  /// Returns `?.` for nullable field types, `.` for non-nullable.
  /// Nullable disposables/listeners must use null-safe calls in dispose().
  String _callOp(FieldElement f) => _type(f).endsWith('?') ? '?.' : '.';

  bool _isChangeNotifier(FieldElement f) {
    final element = f.type.element;
    if (element is! ClassElement) return false;
    if (element.name == 'ChangeNotifier') return true;
    // @LiveStore classes always extend ChangeNotifier (via their generated base),
    // even if the supertype chain is unresolvable in the current build step.
    if (_liveStoreChecker.hasAnnotationOf(element)) return true;
    final superEl = element.supertype?.element;
    if (superEl is ClassElement && _liveStoreChecker.hasAnnotationOf(superEl)) {
      return true;
    }
    return element.allSupertypes
        .any((t) => t.element.name == 'ChangeNotifier');
  }

  /// True when [f] is a non-final, inline-initialized field whose type is
  /// a @LiveStore class (or a direct subtype of one). These fields are
  /// owned by the enclosing widget/store and should be disposed.
  bool _isOwnedLiveStore(FieldElement f) {
    if (f.isFinal) return false;
    if (!f.hasInitializer) return false;
    final element = f.type.element;
    if (element is! ClassElement) return false;
    if (_liveStoreChecker.hasAnnotationOf(element)) return true;
    // The generated public class (e.g. UserStore) extends the user's spec class
    // (e.g. _UserStore) which carries the @LiveStore annotation.
    final superEl = element.supertype?.element;
    if (superEl is ClassElement && _liveStoreChecker.hasAnnotationOf(superEl)) {
      return true;
    }
    return false;
  }

  bool _isPrimitive(FieldElement f) {
    final lib = f.type.element?.library;
    return lib != null && lib.isDartCore;
  }

  bool _isProxyable(FieldElement f) {
    if (_isPrimitive(f)) return false;
    if (_isDisposable(f)) return false;
    if (_isChangeNotifier(f)) return false;
    if (_isDartList(f)) return false;
    if (_isDartSet(f)) return false;
    if (_isDartMap(f)) return false;
    final element = f.type.element;
    if (element is! ClassElement) return false;
    if (element.isAbstract || element.isFinal || element.isSealed) return false;
    return _hasDefaultConstructor(element);
  }

  bool _hasDefaultConstructor(ClassElement cls) {
    final ctor = cls.unnamedConstructor;
    if (ctor == null) return false;
    if (ctor.isSynthetic) return true;
    return ctor.parameters.every((p) => !p.isRequired);
  }
}
