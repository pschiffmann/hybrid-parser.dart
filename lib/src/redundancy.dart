import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:quiver/core.dart';

import 'grammar.dart';
import 'graph.dart';

const eq = ListEquality();

void mergeStates(Graph graph) {
  final queue = Queue.of(graph.states);
  final visited = HashMap<int, List<State>>();
  while (queue.isNotEmpty) {
    final state = queue.removeFirst();
    final hashCode = hashState(state);
    for (final candidate in visited[hashCode]) {}
  }
}

class MergeInformation {
  factory MergeInformation(State state) {
    final successors = <int>[];
    final reductions = <Production>[];
    for (final stage in const Iterable<Stage>.empty()
        .followedBy(state.branches)
        .followedBy(state.continuations)) {
      if (stage.successor != state) {
        successors.add(stage.successor.id);
      }
    }
    for (final branch in state.branches) {
      if (branch.action == LabelAction.reduction) {
        reductions.add(branch.traces.single.production);
      }
    }
    return MergeInformation._(successors, reductions);
  }

  MergeInformation._(this.successors, this.reductions);

  /// The [State.id]s of the successor states in ascending order, excluding the
  /// state itself, if it has a transition on itself.
  final List<int> successors;

  /// The applicable reductions of this state in ascending order.
  final List<Production> reductions;

  @override
  int get hashCode => hash2(eq.hash(successors), eq.hash(reductions));

  @override
  bool operator ==(Object other) =>
      other is MergeInformation &&
      eq.equals(successors, other.successors) &&
      eq.equals(reductions, other.reductions);
}
