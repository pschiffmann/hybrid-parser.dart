import 'package:hybrid_parser/hybrid_parser.dart';

void main(List<String> args) {
  final grammar = parse('''
    Z -> E
    E -> E '+' T
    E -> T
    T -> T '*' F
    T -> F
    F -> '(' E ')'
    F -> 'a'
  ''');
  print(grammar);
}

Grammar parse(String grammarString) {
  final builder = new GrammarBuilder();
  final pattern = new RegExp(r'^\s*(\w+) -> (.*?)$', multiLine: true);
  for (final match in pattern.allMatches(grammarString)) {
    if (match == null) continue;
    builder.startSymbol ??= match.group(1);
    builder.add(match.group(1), match.group(2).split(new RegExp(r'\s+')));
  }
  return builder.build();
}
