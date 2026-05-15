import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/generator.dart';

Builder livelyBuilder(BuilderOptions options) =>
    SharedPartBuilder([LivelyGenerator()], 'lively');
