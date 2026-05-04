import 'dart:async';
import 'dart:collection';

/// A sequential async task serializer. Enqueued actions are executed one at a
/// time in FIFO order, preventing concurrent mutations of shared state.
class TaskQueue {
  final Queue<_Task> _tasks = Queue();
  bool _isProcessing = false;

  Future<T> enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tasks.add(_Task<T>(action, completer));
    _process();
    return completer.future;
  }

  Future<void> _process() async {
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      while (_tasks.isNotEmpty) {
        final task = _tasks.removeFirst();
        try {
          task.completer.complete(await task.action());
        } catch (e, st) {
          task.completer.completeError(e, st);
        }
      }
    } finally {
      _isProcessing = false;
    }
  }
}

class _Task<T> {
  final Future<T> Function() action;
  final Completer<T> completer;
  _Task(this.action, this.completer);
}
