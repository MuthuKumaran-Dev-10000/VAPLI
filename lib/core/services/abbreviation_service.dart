class AbbreviationService {
  final Map<String, String> _headerToAbbr = {};
  final Map<String, String> _valueToAbbr = {};
  final Set<String> _usedAbbrs = {};

  /// Abbreviates a label, resolving collisions.
  String abbreviate(String label, {bool isHeader = false}) {
    final cleanLabel = label.trim();
    if (cleanLabel.isEmpty) return '';

    if (_headerToAbbr.containsKey(cleanLabel)) {
      return _headerToAbbr[cleanLabel]!;
    }
    if (_valueToAbbr.containsKey(cleanLabel)) {
      return _valueToAbbr[cleanLabel]!;
    }

    String candidate = _generateBase(cleanLabel);
    String finalAbbr = candidate;

    if (_usedAbbrs.contains(candidate)) {
      finalAbbr = _resolveCollision(cleanLabel, candidate);
    }

    _usedAbbrs.add(finalAbbr);
    if (isHeader) {
      _headerToAbbr[cleanLabel] = finalAbbr;
    } else {
      _valueToAbbr[cleanLabel] = finalAbbr;
    }

    return finalAbbr;
  }

  String _resolveCollision(String cleanLabel, String candidate) {
    final words = cleanLabel.split(RegExp(r'\s+'));
    if (words.length > 1) {
      final w1 = words.first;
      final otherInitials = words.skip(1).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();

      for (int i = 2; i <= w1.length; i++) {
        final prefix = w1.substring(0, i);
        final formattedPrefix = prefix[0].toUpperCase() + prefix.substring(1).toLowerCase();
        final testAbbr = '$formattedPrefix$otherInitials';
        if (!_usedAbbrs.contains(testAbbr)) {
          return testAbbr;
        }
      }
    } else {
      final w = words.first;
      for (int i = 4; i <= w.length; i++) {
        final prefix = w.substring(0, i);
        final testAbbr = prefix[0].toUpperCase() + prefix.substring(1).toLowerCase();
        if (!_usedAbbrs.contains(testAbbr)) {
          return testAbbr;
        }
      }
    }

    int counter = 1;
    while (true) {
      final testAbbr = '$candidate$counter';
      if (!_usedAbbrs.contains(testAbbr)) {
        return testAbbr;
      }
      counter++;
    }
  }

  String _generateBase(String label) {
    final words = label.split(RegExp(r'\s+'));
    if (words.length > 1) {
      return words.map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
    } else {
      final w = words.first;
      if (w.length <= 3) return w.toUpperCase();
      return w.substring(0, 3).toUpperCase();
    }
  }

  Map<String, String> get headerLegends => _headerToAbbr;
  Map<String, String> get valueLegends => _valueToAbbr;

  Map<String, String> get legends {
    final combined = <String, String>{};
    combined.addAll(_headerToAbbr);
    combined.addAll(_valueToAbbr);
    return combined;
  }
}
