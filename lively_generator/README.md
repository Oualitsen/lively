# lively_generator

Code generator for the [lively](https://pub.dev/packages/lively) package.

This package is a `dev_dependency`. It is not imported directly — `build_runner`
discovers it automatically via `build.yaml`.

## Setup

```yaml
# pubspec.yaml
dependencies:
  lively: ^1.1.0

dev_dependencies:
  lively_generator: ^1.1.0
  build_runner: ^2.0.0
```

Then run:

```sh
dart run build_runner build
```

For usage, examples, and full documentation see the
[lively README](https://pub.dev/packages/lively).
