import 'dart:collection';

Set<T> discoverExpand<T>(
    dynamic /*T|Iterable<T>*/ start, Iterable<T> Function(T) successors) {
  final result = new Set<T>();
  final queue = new Queue<T>();

  if (start is T) {
    result.add(start);
    queue.add(start);
  } else if (start is Iterable<T>) {
    result.addAll(start);
    queue.addAll(start);
  } else {
    throw new ArgumentError.value(
        start, 'start', 'must be of type `T` or `Iterable<T>`');
  }

  while (queue.isNotEmpty) {
    for (final successor in successors(queue.removeFirst())) {
      if (result.add(successor)) queue.add(successor);
    }
  }
  return result;
}
