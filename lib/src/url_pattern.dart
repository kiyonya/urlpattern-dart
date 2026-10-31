import 'path_to_regex_modified.dart';
import 'url_pattern_interfaces.dart';
import 'url_pattern_parser.dart';
import 'url_utils.dart';

const List<String> _components = [
  'protocol',
  'username',
  'password',
  'hostname',
  'port',
  'pathname',
  'search',
  'hash',
];

const String _defaultPattern = '*';

URLPatternInit urlPatternInitFromObject(Object? input) {
  if (input is URLPatternInit) {
    return input;
  }
  if (input is Map) {
    return URLPatternInit.fromMap(Map<Object?, Object?>.from(input));
  }
  throw URLPatternTypeError(
    "parameter 1 is not of type 'string' and cannot convert to dictionary.",
  );
}

String? _initValue(URLPatternInit init, String component) {
  switch (component) {
    case 'protocol':
      return init.protocol;
    case 'username':
      return init.username;
    case 'password':
      return init.password;
    case 'hostname':
      return init.hostname;
    case 'port':
      return init.port;
    case 'pathname':
      return init.pathname;
    case 'search':
      return init.search;
    case 'hash':
      return init.hash;
  }
  return null;
}

URLPatternInit _emptyValues() {
  return URLPatternInit(
    pathname: '',
    protocol: '',
    username: '',
    password: '',
    hostname: '',
    port: '',
    search: '',
    hash: '',
  );
}

URLPatternInit _extractValues(String url, String? baseURL) {
  UrlParts? parts = parseAbsoluteUrl(url);
  if (parts == null) {
    if (baseURL == null || baseURL.isEmpty) {
      throw URLPatternTypeError("parameter 1 is not of type 'string'.");
    }
    final resolved = Uri.parse(baseURL).resolve(url);
    if (!resolved.hasScheme) {
      throw URLPatternTypeError("parameter 1 is not of type 'string'.");
    }
    parts = parseAbsoluteUrl(resolved.toString());
    if (parts == null) {
      throw URLPatternTypeError("parameter 1 is not of type 'string'.");
    }
  }

  return URLPatternInit(
    protocol: parts.protocol,
    username: parts.username,
    password: parts.password,
    hostname: parts.hostname,
    port: parts.port,
    pathname: parts.pathname,
    search: parts.search.isEmpty ? null : parts.search,
    hash: parts.hash.isEmpty ? null : parts.hash,
  );
}

String _processBaseURLString(String input, bool isPattern) {
  if (!isPattern) {
    return input;
  }

  return _escapePatternString(input);
}

URLPatternInit _applyInit(
  URLPatternInit o,
  URLPatternInit init,
  bool isPattern,
) {
  UrlParts? baseURL;
  if (init.baseURL != null) {
    try {
      baseURL = parseAbsoluteUrl(init.baseURL!);
      if (baseURL == null) {
        throw const FormatException('Base URL must be absolute.');
      }

      if (init.protocol == null) {
        o.protocol = _processBaseURLString(baseURL.protocol, isPattern);
      }
      if (!isPattern &&
          init.protocol == null &&
          init.hostname == null &&
          init.port == null &&
          init.username == null) {
        o.username = _processBaseURLString(baseURL.username, isPattern);
      }
      if (!isPattern &&
          init.protocol == null &&
          init.hostname == null &&
          init.port == null &&
          init.username == null &&
          init.password == null) {
        o.password = _processBaseURLString(baseURL.password, isPattern);
      }
      if (init.protocol == null && init.hostname == null) {
        o.hostname = _processBaseURLString(baseURL.hostname, isPattern);
      }
      if (init.protocol == null && init.hostname == null && init.port == null) {
        o.port = _processBaseURLString(baseURL.port, isPattern);
      }
      if (init.protocol == null &&
          init.hostname == null &&
          init.port == null &&
          init.pathname == null) {
        o.pathname = _processBaseURLString(baseURL.pathname, isPattern);
      }
      if (init.protocol == null &&
          init.hostname == null &&
          init.port == null &&
          init.pathname == null &&
          init.search == null) {
        o.search = _processBaseURLString(baseURL.search, isPattern);
      }
      if (init.protocol == null &&
          init.hostname == null &&
          init.port == null &&
          init.pathname == null &&
          init.search == null &&
          init.hash == null) {
        o.hash = _processBaseURLString(baseURL.hash, isPattern);
      }
    } catch (_) {
      throw URLPatternTypeError("invalid baseURL '${init.baseURL}'.");
    }
  }

  if (init.protocol != null) {
    o.protocol = canonicalizeProtocol(init.protocol!, isPattern);
  }

  if (init.username != null) {
    o.username = canonicalizeUsername(init.username!, isPattern);
  }

  if (init.password != null) {
    o.password = canonicalizePassword(init.password!, isPattern);
  }

  if (init.hostname != null) {
    o.hostname = canonicalizeHostname(init.hostname!, isPattern);
  }

  if (init.port != null) {
    o.port = canonicalizePort(init.port!, o.protocol, isPattern);
  }

  if (init.pathname != null) {
    o.pathname = init.pathname;
    if (baseURL != null && !isAbsolutePathname(o.pathname!, isPattern)) {
      final slashIndex = baseURL.pathname.lastIndexOf('/');
      if (slashIndex >= 0) {
        o.pathname =
            _processBaseURLString(
              baseURL.pathname.substring(0, slashIndex + 1),
              isPattern,
            ) +
            o.pathname!;
      }
    }
    o.pathname = canonicalizePathname(o.pathname!, o.protocol, isPattern);
  }

  if (init.search != null) {
    o.search = canonicalizeSearch(init.search!, isPattern);
  }

  if (init.hash != null) {
    o.hash = canonicalizeHash(init.hash!, isPattern);
  }

  return o;
}

String _escapePatternString(String value) {
  return value.replaceAllMapped(
    RegExp(r'([+*?:{}()\\])'),
    (match) => '\\${match[0]}',
  );
}

String _escapeRegexpString(String value) {
  return value.replaceAllMapped(
    RegExp(r'([.+*?^${}()[\]|/\\])'),
    (match) => '\\${match[0]}',
  );
}

final RegExp _regexIdentifierPart = RegExp(
  r'[$_\u200C\u200D\p{ID_Continue}]',
  unicode: true,
);

String _partsToPattern(List<Part> parts, Options options) {
  options.delimiter ??= '/#?';
  options.prefixes ??= './';
  options.sensitive ??= false;
  options.strict ??= false;
  options.end ??= true;
  options.start ??= true;
  options.endsWith = '';

  const kFullWildcardRegex = '.*';
  final segmentWildcardRegex =
      '[^${_escapeRegexpString(options.delimiter!)}]+?';

  var result = '';
  for (var i = 0; i < parts.length; ++i) {
    final part = parts[i];

    if (part.type == PartType.kFixed) {
      if (part.modifier == Modifier.kNone) {
        result += _escapePatternString(part.value);
        continue;
      }

      result +=
          '{${_escapePatternString(part.value)}}${modifierToString(part.modifier)}';
      continue;
    }

    final customName = part.hasCustomName();

    var needsGrouping =
        part.suffix.isNotEmpty ||
        (part.prefix.isNotEmpty &&
            (part.prefix.length != 1 ||
                !options.prefixes!.contains(part.prefix)));

    final lastPart = i > 0 ? parts[i - 1] : null;
    final nextPart = i < parts.length - 1 ? parts[i + 1] : null;

    if (!needsGrouping &&
        customName &&
        part.type == PartType.kSegmentWildcard &&
        part.modifier == Modifier.kNone &&
        nextPart != null &&
        nextPart.prefix.isEmpty &&
        nextPart.suffix.isEmpty) {
      if (nextPart.type == PartType.kFixed) {
        final code = nextPart.value.isNotEmpty ? nextPart.value[0] : '';
        needsGrouping = _regexIdentifierPart.hasMatch(code);
      } else {
        needsGrouping = !nextPart.hasCustomName();
      }
    }

    if (!needsGrouping &&
        part.prefix.isEmpty &&
        lastPart != null &&
        lastPart.type == PartType.kFixed &&
        lastPart.value.isNotEmpty) {
      final code = lastPart.value[lastPart.value.length - 1];
      needsGrouping = options.prefixes!.contains(code);
    }

    if (needsGrouping) {
      result += '{';
    }

    result += _escapePatternString(part.prefix);

    if (customName) {
      result += ':${part.name}';
    }

    if (part.type == PartType.kRegex) {
      result += '(${part.value})';
    } else if (part.type == PartType.kSegmentWildcard) {
      if (!customName) {
        result += '($segmentWildcardRegex)';
      }
    } else if (part.type == PartType.kFullWildcard) {
      if (!customName &&
          (lastPart == null ||
              lastPart.type == PartType.kFixed ||
              lastPart.modifier != Modifier.kNone ||
              needsGrouping ||
              part.prefix.isNotEmpty)) {
        result += '*';
      } else {
        result += '($kFullWildcardRegex)';
      }
    }

    if (part.type == PartType.kSegmentWildcard &&
        customName &&
        part.suffix.isNotEmpty) {
      if (_regexIdentifierPart.hasMatch(part.suffix[0])) {
        result += r'\';
      }
    }

    result += _escapePatternString(part.suffix);

    if (needsGrouping) {
      result += '}';
    }

    if (part.modifier != Modifier.kNone) {
      result += modifierToString(part.modifier);
    }
  }

  return result;
}

class URLPattern {
  URLPattern([
    Object? init = const <String, Object?>{},
    Object? baseURLOrOptions,
    Object? options,
  ]) {
    try {
      String? baseURL;
      Object? rawOptions;
      if (baseURLOrOptions is String) {
        baseURL = baseURLOrOptions;
        rawOptions = options;
      } else {
        rawOptions = baseURLOrOptions ?? options;
      }

      final URLPatternOptions normalizedOptions;
      if (rawOptions is URLPatternOptions) {
        normalizedOptions = rawOptions;
      } else if (rawOptions is Map) {
        normalizedOptions = URLPatternOptions(
          ignoreCase: rawOptions['ignoreCase'] == true,
        );
      } else if (rawOptions == null) {
        normalizedOptions = const URLPatternOptions();
      } else {
        throw URLPatternTypeError(
          "parameter 2 is not of type 'string' or URLPatternOptions.",
        );
      }

      final URLPatternInit initObject;
      if (init is String) {
        final parser = Parser(init);
        parser.parse();
        initObject = parser.result;
        if (baseURL == null && initObject.protocol == null) {
          throw URLPatternTypeError(
            'A base URL must be provided for a relative constructor string.',
          );
        }
        initObject.baseURL = baseURL;
      } else {
        if (init == null || (init is! Map && init is! URLPatternInit)) {
          throw URLPatternTypeError(
            "parameter 1 is not of type 'string' and cannot convert to dictionary.",
          );
        }
        initObject = urlPatternInitFromObject(init);
        if (baseURL != null) {
          throw URLPatternTypeError("parameter 1 is not of type 'string'.");
        }
      }

      final ignoreCase = normalizedOptions.ignoreCase;

      final defaults = URLPatternInit(
        pathname: _defaultPattern,
        protocol: _defaultPattern,
        username: _defaultPattern,
        password: _defaultPattern,
        hostname: _defaultPattern,
        port: _defaultPattern,
        search: _defaultPattern,
        hash: _defaultPattern,
      );

      _pattern = _applyInit(defaults, initObject, true);

      if (defaultPortForProtocol(_pattern.protocol) == _pattern.port) {
        _pattern.port = '';
      }

      for (final component in _components) {
        if (_initValue(_pattern, component) == null) {
          continue;
        }
        final options = Options();
        final pattern = _initValue(_pattern, component)!;
        _names[component] = <Object?>[];
        switch (component) {
          case 'protocol':
            _copyOptions(options, defaultOptions);
            options.encodePart = protocolEncodeCallback;
            break;
          case 'username':
            _copyOptions(options, defaultOptions);
            options.encodePart = usernameEncodeCallback;
            break;
          case 'password':
            _copyOptions(options, defaultOptions);
            options.encodePart = passwordEncodeCallback;
            break;
          case 'hostname':
            _copyOptions(options, hostnameOptions);
            if (treatAsIPv6Hostname(pattern)) {
              options.encodePart = ipv6HostnameEncodeCallback;
            } else {
              options.encodePart = hostnameEncodeCallback;
            }
            break;
          case 'port':
            _copyOptions(options, defaultOptions);
            options.encodePart = portEncodeCallback;
            break;
          case 'pathname':
            if (isSpecialScheme(_regexp['protocol'])) {
              _copyOptions(options, pathnameOptions);
              options.ignoreCase = ignoreCase;
              options.encodePart = standardURLPathnameEncodeCallback;
            } else {
              _copyOptions(options, defaultOptions);
              options.ignoreCase = ignoreCase;
              options.encodePart = pathURLPathnameEncodeCallback;
            }
            break;
          case 'search':
            _copyOptions(options, defaultOptions);
            options.ignoreCase = ignoreCase;
            options.encodePart = searchEncodeCallback;
            break;
          case 'hash':
            _copyOptions(options, defaultOptions);
            options.ignoreCase = ignoreCase;
            options.encodePart = hashEncodeCallback;
            break;
        }
        try {
          final parts = parse(pattern, options);
          _parts[component] = parts;
          _regexp[component] = partsToRegexp(parts, _names[component], options);
          _componentPattern[component] = _partsToPattern(parts, options);
          _hasRegExpGroups =
              _hasRegExpGroups ||
              parts.any((part) => part.type == PartType.kRegex);
        } catch (_) {
          throw URLPatternTypeError(
            "invalid $component pattern '${_initValue(_pattern, component)}'.",
          );
        }
      }
    } catch (error) {
      if (error is URLPatternTypeError) {
        throw URLPatternTypeError(
          "Failed to construct 'URLPattern': ${error.message}",
        );
      }
      throw URLPatternTypeError("Failed to construct 'URLPattern': $error");
    }
  }

  late final URLPatternInit _pattern;
  final Map<String, RegExp> _regexp = {};
  final Map<String, List<Object?>> _names = {};
  final Map<String, String> _componentPattern = {};
  final Map<String, List<Part>> _parts = {};
  bool _hasRegExpGroups = false;

  void _copyOptions(Options target, Options source) {
    target.delimiter = source.delimiter;
    target.prefixes = source.prefixes;
    target.sensitive = source.sensitive;
    target.strict = source.strict;
    target.end = source.end;
    target.start = source.start;
    target.endsWith = source.endsWith;
    target.encodePart = source.encodePart;
  }

  bool test([Object? input = const <String, Object?>{}, String? baseURL]) {
    var values = _emptyValues();

    if (input is! String && baseURL != null) {
      throw URLPatternTypeError("parameter 1 is not of type 'string'.");
    }

    if (input == null) {
      return false;
    }

    try {
      if (input is String) {
        values = _applyInit(values, _extractValues(input, baseURL), false);
      } else {
        values = _applyInit(values, urlPatternInitFromObject(input), false);
      }
    } catch (_) {
      return false;
    }

    for (final component in _components) {
      final regexp = _regexp[component];
      if (regexp == null ||
          !regexp.hasMatch(_initValue(values, component) ?? '')) {
        return false;
      }
    }

    return true;
  }

  URLPatternResult? exec([
    Object? input = const <String, Object?>{},
    String? baseURL,
  ]) {
    var values = _emptyValues();

    if (input is! String && baseURL != null) {
      throw URLPatternTypeError("parameter 1 is not of type 'string'.");
    }

    if (input == null) {
      return null;
    }

    try {
      if (input is String) {
        values = _applyInit(values, _extractValues(input, baseURL), false);
      } else {
        values = _applyInit(values, urlPatternInitFromObject(input), false);
      }
    } catch (_) {
      return null;
    }

    final componentResults = <String, URLPatternComponentResult>{};

    for (final component in _components) {
      final regexp = _regexp[component];
      final match = regexp?.firstMatch(_initValue(values, component) ?? '');
      if (match == null) {
        return null;
      }

      final groups = <String, String?>{};
      final names = _names[component]!;
      for (var i = 0; i < names.length; i++) {
        groups[names[i].toString()] = match.group(i + 1);
      }

      componentResults[component] = URLPatternComponentResult(
        input: _initValue(values, component) ?? '',
        groups: groups,
      );
    }

    final inputs = baseURL != null
        ? <Object?>[input, baseURL]
        : <Object?>[input];

    return URLPatternResult(
      inputs: inputs,
      protocol: componentResults['protocol']!,
      username: componentResults['username']!,
      password: componentResults['password']!,
      hostname: componentResults['hostname']!,
      port: componentResults['port']!,
      pathname: componentResults['pathname']!,
      search: componentResults['search']!,
      hash: componentResults['hash']!,
    );
  }

  static int compareComponent(
    URLPatternComponent component,
    URLPattern left,
    URLPattern right,
  ) {
    int comparePart(Part left, Part right) {
      final leftValues = <Object>[
        left.type.index,
        left.modifier.index,
        left.prefix,
        left.value,
        left.suffix,
      ];
      final rightValues = <Object>[
        right.type.index,
        right.modifier.index,
        right.prefix,
        right.value,
        right.suffix,
      ];

      for (var i = 0; i < leftValues.length; i++) {
        final leftValue = leftValues[i];
        final rightValue = rightValues[i];
        final comparison = leftValue is int
            ? leftValue.compareTo(rightValue as int)
            : (leftValue as String).compareTo(rightValue as String);
        if (comparison < 0) {
          return -1;
        } else if (comparison > 0) {
          return 1;
        }
      }
      return 0;
    }

    int comparePartList(List<Part> left, List<Part> right) {
      var i = 0;
      for (
        ;
        i < (left.length < right.length ? left.length : right.length);
        ++i
      ) {
        final result = comparePart(left[i], right[i]);
        if (result != 0) {
          return result;
        }
      }

      if (left.length == right.length) {
        return 0;
      }

      final emptyFixedPart = Part(
        PartType.kFixed,
        '',
        '',
        '',
        '',
        Modifier.kNone,
      );
      return comparePart(
        i < left.length ? left[i] : emptyFixedPart,
        i < right.length ? right[i] : emptyFixedPart,
      );
    }

    final leftPattern = left._componentPattern[component];
    final rightPattern = right._componentPattern[component];
    final leftIsEmpty = leftPattern == null || leftPattern.isEmpty;
    final rightIsEmpty = rightPattern == null || rightPattern.isEmpty;

    if (leftIsEmpty && rightIsEmpty) {
      return 0;
    }

    final wildcardOnlyPart = Part(
      PartType.kFullWildcard,
      '',
      '',
      '',
      '',
      Modifier.kNone,
    );

    if (!leftIsEmpty && rightIsEmpty) {
      return comparePartList(left._parts[component]!, [wildcardOnlyPart]);
    }

    if (leftIsEmpty && !rightIsEmpty) {
      return comparePartList([wildcardOnlyPart], right._parts[component]!);
    }

    return comparePartList(left._parts[component]!, right._parts[component]!);
  }

  String get protocol => _componentPattern['protocol'] ?? '';
  String get username => _componentPattern['username'] ?? '';
  String get password => _componentPattern['password'] ?? '';
  String get hostname => _componentPattern['hostname'] ?? '';
  String get port => _componentPattern['port'] ?? '';
  String get pathname => _componentPattern['pathname'] ?? '';
  String get search => _componentPattern['search'] ?? '';
  String get hash => _componentPattern['hash'] ?? '';
  bool get hasRegExpGroups => _hasRegExpGroups;
}
