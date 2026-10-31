import 'url_pattern_interfaces.dart';

enum LexTokenType {
  open,
  close,
  regex,
  name,
  char,
  escapedChar,
  otherModifier,
  asterisk,
  end,
  invalidChar,
}

class LexToken {
  const LexToken(this.type, this.index, this.value);

  final LexTokenType type;
  final int index;
  final String value;
}

enum Modifier { kZeroOrMore, kOptional, kOneOrMore, kNone }

enum PartType { kFullWildcard, kSegmentWildcard, kRegex, kFixed }

class Part {
  Part(
    this.type,
    this.name,
    this.prefix,
    this.value,
    this.suffix,
    this.modifier,
  );

  PartType type;
  Object? name;
  String prefix;
  String value;
  String suffix;
  Modifier modifier;

  bool hasCustomName() => name is String && (name as String).isNotEmpty;
}

typedef EncodePartCallback = String Function(String value);

class ParseOptions {
  ParseOptions({this.delimiter, this.prefixes, this.encodePart});

  String? delimiter;
  String? prefixes;
  EncodePartCallback? encodePart;
}

class Options extends ParseOptions {
  Options({
    super.delimiter,
    super.prefixes,
    super.encodePart,
    this.ignoreCase,
    this.strict,
    this.end,
    this.start,
    this.sensitive,
    this.endsWith,
  });

  bool? ignoreCase;
  bool? strict;
  bool? end;
  bool? start;
  bool? sensitive;
  String? endsWith;

  Options copy() {
    return Options(
      ignoreCase: ignoreCase,
      strict: strict,
      end: end,
      start: start,
      delimiter: delimiter,
      prefixes: prefixes,
      sensitive: sensitive,
      endsWith: endsWith,
      encodePart: encodePart,
    );
  }
}

final RegExp _regexIdentifierStart = RegExp(r'[$_\p{ID_Start}]', unicode: true);
final RegExp _regexIdentifierPart = RegExp(
  r'[$_\u200C\u200D\p{ID_Continue}]',
  unicode: true,
);

const String _kFullWildcardRegex = '.*';

bool _isAscii(String str, bool extended) {
  return (extended ? RegExp(r'^[\x00-\xFF]*$') : RegExp(r'^[\x00-\x7F]*$'))
      .hasMatch(str);
}

List<LexToken> lexer(String str, [bool lenient = false]) {
  final tokens = <LexToken>[];
  var i = 0;

  while (i < str.length) {
    final char = str[i];

    void errorOrInvalid(String msg) {
      if (!lenient) throw URLPatternTypeError(msg);
      tokens.add(LexToken(LexTokenType.invalidChar, i, str[i]));
      i++;
    }

    if (char == '*') {
      tokens.add(LexToken(LexTokenType.asterisk, i, str[i]));
      i++;
      continue;
    }

    if (char == '+' || char == '?') {
      tokens.add(LexToken(LexTokenType.otherModifier, i, str[i]));
      i++;
      continue;
    }

    if (char == r'\') {
      final index = i;
      i++;
      final value = i < str.length ? str[i] : '';
      if (i < str.length) i++;
      tokens.add(LexToken(LexTokenType.escapedChar, index, value));
      continue;
    }

    if (char == '{') {
      tokens.add(LexToken(LexTokenType.open, i, str[i]));
      i++;
      continue;
    }

    if (char == '}') {
      tokens.add(LexToken(LexTokenType.close, i, str[i]));
      i++;
      continue;
    }

    if (char == ':') {
      var name = '';
      var j = i + 1;

      while (j < str.length) {
        final code = str.substring(j, j + 1);

        if ((j == i + 1 && _regexIdentifierStart.hasMatch(code)) ||
            (j != i + 1 && _regexIdentifierPart.hasMatch(code))) {
          name += str[j];
          j++;
          continue;
        }

        break;
      }

      if (name.isEmpty) {
        errorOrInvalid('Missing parameter name at $i');
        continue;
      }

      tokens.add(LexToken(LexTokenType.name, i, name));
      i = j;
      continue;
    }

    if (char == '(') {
      var count = 1;
      var pattern = '';
      var j = i + 1;
      var error = false;

      if (j < str.length && str[j] == '?') {
        errorOrInvalid('Pattern cannot start with "?" at $j');
        continue;
      }

      while (j < str.length) {
        if (!_isAscii(str[j], false)) {
          errorOrInvalid("Invalid character '${str[j]}' at $j.");
          error = true;
          break;
        }

        if (str[j] == r'\') {
          pattern += str[j];
          j++;
          if (j < str.length) {
            pattern += str[j];
            j++;
          }
          continue;
        }

        if (str[j] == ')') {
          count--;
          if (count == 0) {
            j++;
            break;
          }
        } else if (str[j] == '(') {
          count++;
          if (j + 1 >= str.length || str[j + 1] != '?') {
            errorOrInvalid('Capturing groups are not allowed at $j');
            error = true;
            break;
          }
        }

        pattern += str[j];
        j++;
      }

      if (error) {
        continue;
      }

      if (count != 0) {
        errorOrInvalid('Unbalanced pattern at $i');
        continue;
      }
      if (pattern.isEmpty) {
        errorOrInvalid('Missing pattern at $i');
        continue;
      }

      tokens.add(LexToken(LexTokenType.regex, i, pattern));
      i = j;
      continue;
    }

    tokens.add(LexToken(LexTokenType.char, i, str[i]));
    i++;
  }

  tokens.add(LexToken(LexTokenType.end, i, ''));

  return tokens;
}

String _escapeString(String str) {
  return str.replaceAllMapped(
    RegExp(r'([.+*?^${}()[\]|/\\])'),
    (match) => '\\${match[0]}',
  );
}

List<Part> parse(String str, [ParseOptions? options]) {
  final tokens = lexer(str);
  options ??= ParseOptions();

  options.delimiter ??= '/#?';
  options.prefixes ??= './';

  final segmentWildcardRegex = '[^${_escapeString(options.delimiter!)}]+?';
  final result = <Part>[];
  var key = 0;
  var i = 0;
  final nameSet = <Object?>{};

  String? tryConsume(LexTokenType type) {
    if (i < tokens.length && tokens[i].type == type) {
      return tokens[i++].value;
    }
    return null;
  }

  String? tryConsumeModifier() {
    return tryConsume(LexTokenType.otherModifier) ??
        tryConsume(LexTokenType.asterisk);
  }

  String mustConsume(LexTokenType type) {
    final value = tryConsume(type);
    if (value != null) return value;
    final next = tokens[i];
    throw URLPatternTypeError(
      'Unexpected ${next.type.name} at ${next.index}, expected ${type.name}',
    );
  }

  String consumeText() {
    var text = '';
    String? value;
    while ((value =
            tryConsume(LexTokenType.char) ??
            tryConsume(LexTokenType.escapedChar)) !=
        null) {
      text += value!;
    }
    return text;
  }

  String defaultEncodePart(String value) => value;
  final encodePart = options.encodePart ?? defaultEncodePart;

  var pendingFixedValue = '';
  void appendToPendingFixedValue(String value) {
    pendingFixedValue += value;
  }

  void maybeAddPartFromPendingFixedValue() {
    if (pendingFixedValue.isEmpty) {
      return;
    }

    result.add(
      Part(
        PartType.kFixed,
        '',
        '',
        encodePart(pendingFixedValue),
        '',
        Modifier.kNone,
      ),
    );
    pendingFixedValue = '';
  }

  void addPart(
    String prefix,
    String? nameToken,
    String? regexOrWildcardToken,
    String suffix,
    String? modifierToken,
  ) {
    var modifier = Modifier.kNone;
    switch (modifierToken) {
      case '?':
        modifier = Modifier.kOptional;
        break;
      case '*':
        modifier = Modifier.kZeroOrMore;
        break;
      case '+':
        modifier = Modifier.kOneOrMore;
        break;
    }

    if (nameToken == null &&
        regexOrWildcardToken == null &&
        modifier == Modifier.kNone) {
      appendToPendingFixedValue(prefix);
      return;
    }

    maybeAddPartFromPendingFixedValue();

    if (nameToken == null && regexOrWildcardToken == null) {
      if (prefix.isEmpty) {
        return;
      }

      result.add(
        Part(PartType.kFixed, '', '', encodePart(prefix), '', modifier),
      );
      return;
    }

    String regexValue;
    if (regexOrWildcardToken == null) {
      regexValue = segmentWildcardRegex;
    } else if (regexOrWildcardToken == '*') {
      regexValue = _kFullWildcardRegex;
    } else {
      regexValue = regexOrWildcardToken;
    }

    var type = PartType.kRegex;
    if (regexValue == segmentWildcardRegex) {
      type = PartType.kSegmentWildcard;
      regexValue = '';
    } else if (regexValue == _kFullWildcardRegex) {
      type = PartType.kFullWildcard;
      regexValue = '';
    }

    Object? name;
    if (nameToken != null) {
      name = nameToken;
    } else if (regexOrWildcardToken != null) {
      name = key++;
    }

    if (nameSet.contains(name)) {
      throw URLPatternTypeError("Duplicate name '$name'.");
    }
    nameSet.add(name);

    result.add(
      Part(
        type,
        name ?? '',
        encodePart(prefix),
        regexValue,
        encodePart(suffix),
        modifier,
      ),
    );
  }

  while (i < tokens.length) {
    final charToken = tryConsume(LexTokenType.char);
    final nameToken = tryConsume(LexTokenType.name);
    var regexOrWildcardToken = tryConsume(LexTokenType.regex);

    if (nameToken == null && regexOrWildcardToken == null) {
      regexOrWildcardToken = tryConsume(LexTokenType.asterisk);
    }

    if (nameToken != null || regexOrWildcardToken != null) {
      var prefix = charToken ?? '';
      if (!options.prefixes!.contains(prefix)) {
        appendToPendingFixedValue(prefix);
        prefix = '';
      }

      maybeAddPartFromPendingFixedValue();

      final modifierToken = tryConsumeModifier();

      addPart(prefix, nameToken, regexOrWildcardToken, '', modifierToken);

      continue;
    }

    final value = charToken ?? tryConsume(LexTokenType.escapedChar);
    if (value != null) {
      appendToPendingFixedValue(value);
      continue;
    }

    final openToken = tryConsume(LexTokenType.open);
    if (openToken != null) {
      final prefix = consumeText();
      final nameToken = tryConsume(LexTokenType.name);
      var regexOrWildcardToken = tryConsume(LexTokenType.regex);

      if (nameToken == null && regexOrWildcardToken == null) {
        regexOrWildcardToken = tryConsume(LexTokenType.asterisk);
      }

      final suffix = consumeText();

      mustConsume(LexTokenType.close);

      final modifierToken = tryConsumeModifier();

      addPart(prefix, nameToken, regexOrWildcardToken, suffix, modifierToken);
      continue;
    }

    maybeAddPartFromPendingFixedValue();

    mustConsume(LexTokenType.end);
  }

  return result;
}

String modifierToString(Modifier modifier) {
  switch (modifier) {
    case Modifier.kZeroOrMore:
      return '*';
    case Modifier.kOptional:
      return '?';
    case Modifier.kOneOrMore:
      return '+';
    case Modifier.kNone:
      return '';
  }
}

RegExp stringToRegexp(String path, [List<Object?>? names, Options? options]) {
  return partsToRegexp(parse(path, options), names, options);
}

RegExp partsToRegexp(
  List<Part> parts, [
  List<Object?>? names,
  Options? options,
]) {
  options ??= Options();
  options.delimiter ??= '/#?';
  options.prefixes ??= './';
  options.sensitive ??= false;
  options.strict ??= false;
  options.end ??= true;
  options.start ??= true;
  options.endsWith = '';

  var result = (options.start ?? true) ? '^' : '';

  for (final part in parts) {
    if (part.type == PartType.kFixed) {
      if (part.modifier == Modifier.kNone) {
        result += _escapeString(part.value);
      } else {
        result +=
            '(?:${_escapeString(part.value)})${modifierToString(part.modifier)}';
      }
      continue;
    }

    names?.add(part.name);

    final segmentWildcardRegex = '[^${_escapeString(options.delimiter!)}]+?';

    var regexValue = part.value;
    if (part.type == PartType.kSegmentWildcard) {
      regexValue = segmentWildcardRegex;
    } else if (part.type == PartType.kFullWildcard) {
      regexValue = _kFullWildcardRegex;
    }

    if (part.prefix.isEmpty && part.suffix.isEmpty) {
      if (part.modifier == Modifier.kNone ||
          part.modifier == Modifier.kOptional) {
        result += '($regexValue)${modifierToString(part.modifier)}';
      } else {
        result += '((?:$regexValue)${modifierToString(part.modifier)})';
      }
      continue;
    }

    if (part.modifier == Modifier.kNone ||
        part.modifier == Modifier.kOptional) {
      result +=
          '(?:${_escapeString(part.prefix)}($regexValue)${_escapeString(part.suffix)})';
      result += modifierToString(part.modifier);
      continue;
    }

    result += '(?:${_escapeString(part.prefix)}';
    result += '((?:$regexValue)(?:';
    result += _escapeString(part.suffix);
    result += _escapeString(part.prefix);
    result += '(?:$regexValue))*)${_escapeString(part.suffix)})';
    if (part.modifier == Modifier.kZeroOrMore) {
      result += '?';
    }
  }

  final endsWith = '[${_escapeString(options.endsWith!)}]|\$';
  final delimiter = '[${_escapeString(options.delimiter!)}]';

  if (options.end ?? true) {
    if (!(options.strict ?? false)) {
      result += '$delimiter?';
    }

    if (options.endsWith!.isEmpty) {
      result += r'$';
    } else {
      result += '(?=$endsWith)';
    }
  } else {
    if (!(options.strict ?? false)) {
      result += '(?:$delimiter(?=$endsWith))?';
    }

    var isEndDelimited = false;
    if (parts.isNotEmpty) {
      final lastPart = parts[parts.length - 1];
      if (lastPart.type == PartType.kFixed &&
          lastPart.modifier == Modifier.kNone) {
        isEndDelimited = options.delimiter!.contains(lastPart.value);
      }
    }

    if (!isEndDelimited) {
      result += '(?=$delimiter|$endsWith)';
    }
  }

  return RegExp(
    result,
    caseSensitive: !(options.ignoreCase ?? false),
    unicode: true,
  );
}
