class ExpressionEngineException implements Exception {
  final String message;
  const ExpressionEngineException(this.message);
  @override
  String toString() => message;
}

abstract class _Node {
  double eval(Map<String, double> vars);
}

class _NumberNode extends _Node {
  final double value;
  _NumberNode(this.value);
  @override
  double eval(Map<String, double> vars) => value;
}

class _VarNode extends _Node {
  final String name;
  _VarNode(this.name);
  @override
  double eval(Map<String, double> vars) {
    final v = vars[name];
    if (v == null) {
      throw ExpressionEngineException('Missing variable: $name');
    }
    return v;
  }
}

class _BinNode extends _Node {
  final String op;
  final _Node left;
  final _Node right;
  _BinNode(this.op, this.left, this.right);
  @override
  double eval(Map<String, double> vars) {
    final l = left.eval(vars);
    final r = right.eval(vars);
    switch (op) {
      case '+':
        return l + r;
      case '-':
        return l - r;
      case '*':
        return l * r;
      case '/':
        if (r == 0) {
          throw const ExpressionEngineException('Division by zero');
        }
        return l / r;
      default:
        throw ExpressionEngineException('Unsupported operator: $op');
    }
  }
}

class _Parser {
  _Parser(this.tokens);
  final List<String> tokens;
  int i = 0;

  bool get _done => i >= tokens.length;
  String get _cur => tokens[i];

  _Node parse() {
    final node = _expr();
    if (!_done) {
      throw ExpressionEngineException('Unexpected token: ${tokens[i]}');
    }
    return node;
  }

  _Node _expr() {
    var node = _term();
    while (!_done && (_cur == '+' || _cur == '-')) {
      final op = _cur;
      i++;
      node = _BinNode(op, node, _term());
    }
    return node;
  }

  _Node _term() {
    var node = _factor();
    while (!_done && (_cur == '*' || _cur == '/')) {
      final op = _cur;
      i++;
      node = _BinNode(op, node, _factor());
    }
    return node;
  }

  _Node _factor() {
    if (_done) {
      throw const ExpressionEngineException('Unexpected end of expression');
    }
    final t = _cur;
    if (t == '(') {
      i++;
      final n = _expr();
      if (_done || _cur != ')') {
        throw const ExpressionEngineException('Missing closing ")"');
      }
      i++;
      return n;
    }
    if (t == '-') {
      i++;
      return _BinNode('*', _NumberNode(-1), _factor());
    }
    final n = double.tryParse(t);
    if (n != null) {
      i++;
      return _NumberNode(n);
    }
    i++;
    return _VarNode(t);
  }
}

class ExpressionEngine {
  static final RegExp _tokenRe =
      RegExp(r'\s*([A-Za-z_][A-Za-z0-9_.]*|\d+(?:\.\d+)?|[()+\-*/])\s*');
  static final RegExp _idTokenRe = RegExp(r'\$\{([^}]+)\}');

  static Set<String> extractIds(String expression) {
    final ids = <String>{};
    for (final m in _idTokenRe.allMatches(expression)) {
      ids.add(m.group(1)!.trim());
    }
    return ids;
  }

  static double evaluate(
    String expression, {
    required Map<String, double> variables,
  }) {
    var raw = expression.trim();
    final tokenMap = <String, String>{};
    int i = 0;
    raw = raw.replaceAllMapped(_idTokenRe, (m) {
      final id = m.group(1)!.trim();
      final alias = '__v$i';
      i++;
      tokenMap[alias] = id;
      return alias;
    });
    if (raw.isEmpty) {
      throw const ExpressionEngineException('Expression is empty');
    }
    final aliasedVars = <String, double>{};
    for (final entry in tokenMap.entries) {
      final value = variables[entry.value];
      if (value == null) {
        throw ExpressionEngineException('Missing variable: ${entry.value}');
      }
      aliasedVars[entry.key] = value;
    }

    final tokens = <String>[];
    int index = 0;
    while (index < raw.length) {
      final m = _tokenRe.matchAsPrefix(raw, index);
      if (m == null) {
        throw ExpressionEngineException(
          'Invalid token near: "${raw.substring(index)}"',
        );
      }
      tokens.add(m.group(1)!);
      index = m.end;
    }

    final ast = _Parser(tokens).parse();
    return ast.eval(aliasedVars);
  }
}
