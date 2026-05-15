import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class Reactive extends StatefulWidget {
  final List<dynamic> watch;
  final Widget Function() builder;

  const Reactive({super.key, required this.watch, required this.builder});

  @override
  State<Reactive> createState() => _ReactiveState();
}

class _ReactiveState extends State<Reactive> {
  @override
  void didUpdateWidget(Reactive old) {
    super.didUpdateWidget(old);
    if (!listEquals(widget.watch, old.watch)) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder();
}
