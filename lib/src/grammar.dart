import 'dart:collection' show Queue;
import 'dart:math' show max;
import 'package:built_value/built_value.dart';
// import 'package:collection/collection.dart';
import 'package:quiver/collection.dart';
import 'package:verbose_regexp/verbose_regexp.dart';
import 'discover_expand.dart';

/// An immutable grammar.
class Grammar implements Built<Grammar, GrammarBuilder> {
  factory Grammar.build(void Function(GrammarBuilder) updates) =>
      (new GrammarBuilder()..update(updates)).build();

  Grammar._();

  List<Nonterminal> _nonterminals;
  List<Terminal> _terminals;
  Nonterminal _startSymbol;

  List<Nonterminal> get nonterminals => _nonterminals;
  List<Terminal> get terminals => _terminals;
  Nonterminal get startSymbol => _startSymbol;

  @override
  Grammar rebuild(void Function(GrammarBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GrammarBuilder toBuilder() => new GrammarBuilder()..replace(this);

  @override
  String toString() {
    final padding =
        nonterminals.map((nonterminal) => nonterminal.name.length).reduce(max);
    final buffer = new StringBuffer();
    for (final nonterminal in nonterminals) {
      var firstLine = true;
      void writeLeftHandSide() {
        if (firstLine) {
          buffer
            ..write(nonterminal)
            ..write(nonterminal == startSymbol ? '*' : ' ')
            ..write(' ' * (padding - nonterminal.name.length));
          firstLine = false;
        } else {
          buffer.write(' ' * (padding + 1));
        }
        buffer.write(' -> ');
      }

      for (final production in nonterminal.definition) {
        writeLeftHandSide();
        buffer
          ..writeAll(production.pattern, ' ')
          ..writeln();
      }
      if (nonterminal.nullable) {
        writeLeftHandSide();
        buffer..writeln(Terminal.emptyWord);
      }
    }
    return buffer.toString();
  }
}

/// Type union over [Nonterminal] and [Terminal]. Each grammar symbol has a name
/// and a reference to its grammar.
abstract class GrammarSymbol {
  GrammarSymbol(this.grammar, this.name);

  final Grammar grammar;
  final String name;

  @override
  String toString() => name;
}

class Terminal extends GrammarSymbol {
  static const Terminal emptyWord = const _MetaTerminal('ε');
  static const Terminal endOfInput = const _MetaTerminal('\$');
  static const Terminal lexingError = const _MetaTerminal('↯');

  Terminal._(Grammar grammar, String name)
      : assert(GrammarBuilder.isTerminal(name)),
        super(grammar, name);
}

class _MetaTerminal implements Terminal {
  const _MetaTerminal(this.name);

  @override
  final String name;
  @override
  Grammar get grammar => throw new UnimplementedError(
      'The meta terminals ${Terminal.emptyWord}, ${Terminal.endOfInput} '
      "and ${Terminal.lexingError} don't belong to a grammar");
}

class Nonterminal extends GrammarSymbol {
  Nonterminal._(Grammar grammar, String name)
      : assert(GrammarBuilder.isNonterminal(name)),
        super(grammar, name);

  List<Production> _definition;
  bool _nullable;
  List<Terminal> _first;

  List<Production> get definition => _definition;
  bool get nullable => _nullable;
  List<Terminal> get first => _first;
}

class Production {
  Production._(this.nonterminal, Iterable<GrammarSymbol> pattern)
      : pattern = new List.unmodifiable(pattern);
  final Nonterminal nonterminal;
  final List<GrammarSymbol> pattern;

  @override
  String toString() => '$nonterminal -> ${pattern.join(" ")}';
}

///
class GrammarBuilder implements Builder<Grammar, GrammarBuilder> {
  static final RegExp _nonterminalPattern = new RegExp(verbose(r'''
      ^
      [A-Za-z$][A-Za-z0-9_$]*
      (
        \.
        [A-Za-z$][A-Za-z0-9_$]*
      )*
      $
      '''));

  static final RegExp _terminalPattern = new RegExp(r"^'(\\.|[^'\\])+'$");

  static bool isNonterminal(String name) => _nonterminalPattern.hasMatch(name);
  static bool isTerminal(String name) => _terminalPattern.hasMatch(name);

  ///
  static String escapeTerminal(String name) {
    final escaped = name.replaceAllMapped(
        new RegExp(r"\\|'"), (Match m) => '\\${m.group(0)}');
    return "'$escaped'";
  }

  ///
  final SetMultimap<String, List<String>> _productions =
      new SetMultimap<String, List<String>>(
          /*equals: const ListEquality()*/);

  String _startSymbol;

  /// As [Grammar.startSymbol].
  String get startSymbol => _startSymbol;

  set startSymbol(String symbol) => symbol == null || isNonterminal(symbol)
      ? _startSymbol = symbol
      : throw new ArgumentError('Invalid nonterminal name');

  /// Adds a production from [nonterminal] to [pattern].
  void add(String nonterminal, Iterable<String> pattern) {
    if (!isNonterminal(nonterminal))
      throw new ArgumentError.value(
          nonterminal, 'nonterminal', 'Invalid nonterminal name');

    final patternList = new List<String>.unmodifiable(pattern);
    for (var i = 0; i < patternList.length; i++) {
      if (!isNonterminal(patternList[i]) && !isTerminal(patternList[i]))
        throw new ArgumentError.value(
            patternList[i], 'pattern[$i]', 'Invalid symbol name');
    }

    _productions.add(nonterminal, patternList);
  }

  /// Removes the production from [nonterminal] to [pattern]. If [pattern] is
  /// omitted, removes all productions for [nonterminal]. Removes the
  /// nonterminal from the builder if it no longer has a pattern.
  void remove(String nonterminal, [List<String> pattern]) => pattern != null
      ? _productions.remove(nonterminal, pattern)
      : _productions.removeAll(nonterminal);

  /// Removes all productions and sets [startSymbol] to `null`.
  void clear() {
    _productions.clear();
    startSymbol = null;
  }

  /// Builds a [Grammar] with the current contents of this builder.
  ///
  /// If [removeUnreachableProductions] is `true`, removes all productions that
  /// can't be reached from [startSymbol], and all grammar symbols that are only
  /// used in these productions. If the argument is `false` and such productions
  /// exist, throws an [UnreachableNonterminalsException]. This means that a
  /// [Grammar] can never contain unreachable symbols.
  ///
  /// Throws a [StateError] if [startSymbol] is `null`.
  @override
  Grammar build({bool removeUnreachableProductions: false}) {
    if (startSymbol == null)
      throw new StateError('`startSymbol` must not be null');

    final grammar = new Grammar._();
    final nonterminals = <String, Nonterminal>{};
    final terminals = <String, Terminal>{};
    final symbols = <String, GrammarSymbol>{};
    grammar._startSymbol =
        nonterminals[startSymbol] = new Nonterminal._(grammar, startSymbol);

    // Discover all grammar symbols that can be reached from the start symbol.
    discoverExpand<Nonterminal>(grammar.startSymbol, (nonterminal) sync* {
      for (final symbol in _productions[nonterminal.name].expand((p) => p)) {
        if (symbols.containsKey(symbol)) continue;
        if (isNonterminal(symbol)) {
          yield symbols[symbol] =
              nonterminals[symbol] = new Nonterminal._(grammar, symbol);
        } else {
          symbols[symbol] = terminals[symbol] = new Terminal._(grammar, symbol);
        }
      }
    });

    // Abort if [_productions] contains unreachable nonterminals.
    if (nonterminals.length < _productions.length &&
        !removeUnreachableProductions) {
      throw new UnreachableNonterminalsException(_productions.keys
          .where((nonterminal) => !nonterminals.containsKey(nonterminal)));
    }

    // Initialize [Nonterminal._definition] and [Nonterminal._nullable].
    for (final nonterminal in nonterminals.values) {
      nonterminal
        .._definition = new List.from(
            _productions[nonterminal.name].map<Production>((pattern) =>
                new Production._(
                    nonterminal, pattern.map((symbol) => symbols[symbol]))),
            growable: false)
        .._nullable = nonterminal.definition
            .any((production) => production.pattern.isEmpty);
    }

    // Resolve transitively nullable nonterminals.
    // `references` maps a nonterminal to the set of productions that can
    // potentially still become nullable, and where the nonterminal occurs in
    // the pattern.
    final references = new Multimap<Nonterminal, Production>();
    for (final production in nonterminals.values.expand((n) => n.definition)) {
      if (production.nonterminal.nullable ||
          production.pattern.any((symbol) => symbol is Terminal)) continue;
      for (final nonterminal in production.pattern) {
        references.add(nonterminal as Nonterminal, production);
      }
    }
    // `queue` contains all nonterminals that are nullable and that can
    // potentially promote other productions to become nullable.
    final queue = new Queue<Nonterminal>.from(
        nonterminals.values.where((nonterminal) => nonterminal.nullable));
    while (queue.isNotEmpty) {
      final nonterminal = queue.removeFirst();
      for (final production in references[nonterminal]) {
        if (production.nonterminal.nullable) {
          references.remove(nonterminal, production);
          continue;
        }
        if (production.pattern.every((n) => (n as Nonterminal).nullable)) {
          queue.add(production.nonterminal.._nullable = true);
        }
      }
    }

    return grammar
      .._nonterminals = new List.unmodifiable(nonterminals.values)
      .._terminals = new List.unmodifiable(terminals.values);
  }

  @override
  void replace(Grammar grammar) {
    _productions.clear();
    for (final nonterminal in grammar.nonterminals) {
      for (final production in nonterminal.definition) {
        add(nonterminal.name, production.pattern.map((symbol) => symbol.name));
      }
    }
    startSymbol = grammar.startSymbol.name;
  }

  @override
  void update(void Function(GrammarBuilder) updates) => updates(this);
}

///
class UnreachableNonterminalsException extends Error {
  final List<String> nonterminals;

  UnreachableNonterminalsException(Iterable<String> nonterminals)
      : nonterminals = new List.unmodifiable(nonterminals);
}
