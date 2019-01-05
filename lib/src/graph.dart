import 'dart:collection' show HashMap;

import 'package:built_collection/built_collection.dart'
    show BuiltSet, SetBuilder;
import 'package:indexed_set/indexed_set.dart';
import 'package:quiver/collection.dart' show Multimap;
import 'package:quiver/core.dart' show hash3;

import 'discover_expand.dart';
import 'grammar.dart';

///
BuiltSet<Trace> closure(BuiltSet<Trace> kernel, Grammar grammar) =>
    new BuiltSet<Trace>(discoverExpand<Trace>(kernel, (trace) sync* {
      if (trace.expected is! Nonterminal) return;
      final nonterminal = trace.expected as Nonterminal;
      for (final terminal in trace.lookahead) {
        for (final production in nonterminal.definition) {
          yield new Trace(production, terminal);
        }
      }
    }));

class Trace {
  Trace(this.production, this.follow, [this.progress = 0]) {
    RangeError.checkValueInInterval(
        progress, 0, production.pattern.length, 'progress');
  }

  final Production production;
  final Terminal follow;
  final int progress;

  GrammarSymbol get expected =>
      finished ? follow : production.pattern[progress];

  bool get finished => progress == production.pattern.length;

  GrammarSymbol get lastMatched => progress == 0
      ? throw new StateError('')
      : production.pattern[progress - 1];

  Iterable<Terminal> get lookahead sync* {
    if (finished) throw new StateError('Undefined for complete traces');

    for (final symbol in production.pattern.skip(progress + 1)) {
      if (symbol is Nonterminal) {
        yield* symbol.first;
        if (!symbol.nullable) return;
      } else {
        yield symbol as Terminal;
        return;
      }
    }
    yield follow;
  }

  Trace operator >>(int n) => n >= 0
      ? new Trace(production, follow, progress + n)
      : throw new ArgumentError.value(n, 'shift', 'Must be non-negative');

  @override
  int get hashCode => hash3(production, progress, follow);

  @override
  bool operator ==(Object other) =>
      other is Trace &&
      other.production == production &&
      other.progress == progress &&
      other.follow == follow;

  @override
  String toString() => '${production.nonterminal} $follow → '
      '${production.pattern.take(progress).join(" ")}'
      '·'
      '${production.pattern.skip(progress).join(" ")}';
}

class RootTrace implements Trace {
  final Nonterminal startSymbol;

  @override
  Production get production =>
      throw new UnsupportedError('The root trace contains no production');

  @override
  int get progress => 0;

  @override
  Terminal get follow => null;

  @override
  bool get finished => false;

  @override
  GrammarSymbol get expected => startSymbol;

  @override
  GrammarSymbol get lastMatched => null;

  @override
  Iterable<Terminal> get lookahead => startSymbol.first;

  RootTrace(this.startSymbol);

  @override
  RootTrace operator >>(int n) => null;

  @override
  String toString() => finished ? '$startSymbol·' : '·$startSymbol';
}

class Graph {
  final Grammar grammar;
  final State start;
  final Map<BuiltSet<Trace>, State> _states = new HashMap();
  int _nextId = 1;

  Iterable<State> get states => _states.values;

  factory Graph(Grammar grammar) {
    final graph = new Graph._(grammar);
    final queue = new Set<State>()..add(graph.start);

    while (queue.isNotEmpty) {
      final state = queue.first;
      queue.remove(state);
      for (final label in state.labels) {
        switch (label.action) {
          case LabelAction.advance:
            final kernel = new BuiltSet<Trace>(
                label.traces.map<Trace>((trace) => trace >> 1));
            var successor = graph.lookup(kernel);
            if (successor == null) {
              successor = graph.allocate(kernel);
              queue.add(successor);
            }
            label.successor = successor;
            break;
          case LabelAction.reduction:
            break;
          case LabelAction.conflict:
            throw new StateError(
                'conflict in state ${state.id}.${label.label}');
        }
      }
    }
    return graph;
  }

  Graph._(this.grammar)
      : start = new State._fromKernel(
            0,
            new BuiltSet<Trace>(<Trace>[new RootTrace(grammar.startSymbol)]),
            grammar,
            isStartState: true);

  State lookup(BuiltSet<Trace> kernel) => _states[kernel];

  State allocate(BuiltSet<Trace> kernel) => _states.containsKey(kernel)
      ? throw new StateError(
          'A state with this kernel already exists in this graph')
      : _states[kernel] = new State._fromKernel(_nextId++, kernel, grammar);

  /*
  // refine these based on actual need
  void connect(State from, State to) {}
  void remove(State state);
  State replace(State old);
  State merge(Iterable<State> states);
  */
}

class State {
  /// Used as the [IndexedSet.index] of [branches] and [continuations].
  static S _labelIndex<S extends GrammarSymbol>(Stage<S> label) => label.label;

  final int id;
  final BuiltSet<Trace> kernel;
  final GrammarSymbol guard;
  final IndexedSet<Terminal, Stage<Terminal>> branches;
  final IndexedSet<Nonterminal, Stage<Nonterminal>> continuations;

  Iterable<Stage> get labels sync* {
    yield* branches;
    yield* continuations;
  }

  bool get isStartState => id == 0;

  factory State._fromKernel(int id, BuiltSet<Trace> kernel, Grammar grammar,
      {bool isStartState: false}) {
    GrammarSymbol guard;
    if (!isStartState) {
      guard = kernel.first.lastMatched;
      assert(
          kernel.every((trace) => trace.lastMatched == guard),
          'Not every trace in the kernel has the same last matched symbol. '
          'This can only happen if there is a bug in the graph construction '
          'implementation.');
    }

    final primary = new IndexedSet<Terminal, Stage<Terminal>>(_labelIndex);
    final subsequent =
        new IndexedSet<Nonterminal, Stage<Nonterminal>>(_labelIndex);

    new Multimap<GrammarSymbol, Trace>.fromIterable(closure(kernel, grammar),
        key: (dynamic trace) => (trace as Trace).expected)
      ..forEachKey((symbol, traces) {
        if (symbol is Terminal) {
          primary.add(
              new Stage<Terminal>._fromTraces(new BuiltSet<Trace>(traces)));
        } else {
          subsequent.add(
              new Stage<Nonterminal>._fromTraces(new BuiltSet<Trace>(traces)));
        }
      });

    return new State._internal(id, kernel, guard, primary, subsequent);
  }

  State._internal(
      this.id,
      this.kernel,
      this.guard,
      IndexedSet<Terminal, Stage<Terminal>> primary,
      IndexedSet<Nonterminal, Stage<Nonterminal>> subsequent)
      : branches =
            new UnmodifiableIndexedSetView<Terminal, Stage<Terminal>>(primary),
        continuations =
            new UnmodifiableIndexedSetView<Nonterminal, Stage<Nonterminal>>(
                subsequent);
}

enum LabelAction { advance, reduction, conflict }

class Stage<S extends GrammarSymbol> {
  final BuiltSet<Trace> traces;
  final S label;
  final LabelAction action;
  final BuiltSet<Nonterminal> continuations;
  final BuiltSet<Nonterminal> results;
  final bool silentReturn;
  State successor;

  factory Stage._fromTraces(BuiltSet<Trace> traces) {
    final continuations = new SetBuilder<Nonterminal>();
    final results = new SetBuilder<Nonterminal>();
    var silentReturn = false;
    LabelAction action;
    for (final trace in traces) {
      if (trace is RootTrace) continue;

      // resolve continuations and results
      switch (trace.progress) {
        case 0:
          continuations.add(trace.production.nonterminal);
          break;
        case 1:
          results.add(trace.production.nonterminal);
          break;
        default:
          silentReturn = true;
          break;
      }

      // resolve action
      final newAction =
          trace.finished ? LabelAction.reduction : LabelAction.advance;
      action ??= newAction;
      if (action != newAction) action = LabelAction.conflict;
    }
    return new Stage._internal(
        traces, action, continuations.build(), results.build(), silentReturn);
  }

  Stage._internal(this.traces, this.action, this.continuations, this.results,
      this.silentReturn)
      : label = traces.first.expected as S;
}
