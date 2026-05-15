import 'package:flutter/material.dart';
import 'package:lively/lively.dart';

part 'todo_page.g.dart';

class Todo {
  Todo(this.text);
  final String text;
  bool done = false;
}

@Live()
class TodoPage extends _$TodoPage {
  List<Todo> todos = [];
  bool showDone = true;

  TextEditingController? inputCtrl = TextEditingController();
  FocusNode inputFocus = FocusNode();

  void _add() {
    final text = inputCtrl!.text.trim();
    if (text.isEmpty) return;
    todos.add(Todo(text)); // LiveList.add() — auto-notifies
    inputCtrl!.clear();
    inputFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = showDone ? todos : todos.where((t) => !t.done).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Todos'),
        actions: [
          Row(
            children: [
              Text('Show done', style: theme.textTheme.bodyMedium),
              Switch(value: showDone, onChanged: (v) => showDone = v),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: inputCtrl,
                    focusNode: inputFocus,
                    decoration: const InputDecoration(
                      hintText: 'Add a todo…',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(onPressed: _add, child: const Icon(Icons.add)),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      todos.isEmpty ? 'No todos yet.' : 'All done! 🎉',
                      style: theme.textTheme.bodyLarge,
                    ),
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final todo = visible[i];
                      return ListTile(
                        leading: Checkbox(
                          value: todo.done,
                          onChanged: (v) {
                            todo.done = v ?? false;
                            notify(); // deep mutation — explicit notify
                          },
                        ),
                        title: Text(
                          todo.text,
                          style: todo.done
                              ? TextStyle(
                                  decoration: TextDecoration.lineThrough,
                                  color: theme.colorScheme.outline,
                                )
                              : null,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => todos.remove(todo), // LiveList.remove() — auto-notifies
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
