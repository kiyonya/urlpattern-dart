import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:urlpattern_dart/urlpattern_dart.dart';

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

Object? _normalize(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  if (value is List) {
    return value.map(_normalize).toList();
  }
  return value;
}

URLPattern _construct(List<dynamic> args) {
  final normalized = args.map(_normalize).toList();
  if (normalized.isEmpty) {
    return URLPattern();
  }
  if (normalized.length == 1) {
    return URLPattern(normalized[0]);
  }
  if (normalized.length == 2) {
    return URLPattern(normalized[0], normalized[1]);
  }
  return URLPattern(normalized[0], normalized[1], normalized[2]);
}

Object? _invoke(URLPattern pattern, bool isTest, List<dynamic> inputs) {
  final normalized = inputs.map(_normalize).toList();
  if (isTest) {
    if (normalized.isEmpty) return pattern.test();
    if (normalized.length == 1) return pattern.test(normalized[0]);
    return pattern.test(normalized[0], normalized[1] as String?);
  }
  if (normalized.isEmpty) return pattern.exec();
  if (normalized.length == 1) return pattern.exec(normalized[0]);
  return pattern.exec(normalized[0], normalized[1] as String?);
}

URLPatternComponentResult _componentResult(
  URLPatternResult result,
  String component,
) {
  switch (component) {
    case 'protocol':
      return result.protocol;
    case 'username':
      return result.username;
    case 'password':
      return result.password;
    case 'hostname':
      return result.hostname;
    case 'port':
      return result.port;
    case 'pathname':
      return result.pathname;
    case 'search':
      return result.search;
    case 'hash':
      return result.hash;
  }
  throw StateError('Unknown component: $component');
}

String _baseValue(Uri uri, String component) {
  switch (component) {
    case 'protocol':
      return uri.scheme;
    case 'username':
      final userInfo = uri.userInfo;
      final index = userInfo.indexOf(':');
      return index == -1 ? userInfo : userInfo.substring(0, index);
    case 'password':
      final userInfo = uri.userInfo;
      final index = userInfo.indexOf(':');
      return index == -1 ? '' : userInfo.substring(index + 1);
    case 'hostname':
      final host = uri.host;
      return !host.startsWith('[') && host.contains(':') ? '[$host]' : host;
    case 'port':
      if (!uri.hasPort) {
        return '';
      }
      const defaultPorts = {
        'http': 80,
        'https': 443,
        'ftp': 21,
        'ws': 80,
        'wss': 443,
      };
      return defaultPorts[uri.scheme] == uri.port ? '' : uri.port.toString();
    case 'pathname':
      if (uri.path.isEmpty && uri.hasAuthority) {
        return '/';
      }
      return uri.path;
    case 'search':
      return uri.query;
    case 'hash':
      return uri.fragment;
  }
  throw StateError('Unknown component: $component');
}

String? _autoExpectedPattern(Map<String, dynamic> entry, String component) {
  final pattern = entry['pattern'] as List<dynamic>;
  final expectedObject = entry['expected_obj'];
  if (expectedObject is Map && expectedObject[component] != null) {
    return expectedObject[component] as String;
  }

  final exactlyEmpty = entry['exactly_empty_components'];
  if (exactlyEmpty is List && exactlyEmpty.contains(component)) {
    return '';
  }

  final first = pattern.isNotEmpty ? pattern[0] : null;
  if (first is Map && first[component] != null && first[component] != '') {
    return first[component] as String;
  }

  const earlierComponents = <String, List<String>>{
    'protocol': [],
    'hostname': ['protocol'],
    'port': ['protocol', 'hostname'],
    'username': [],
    'password': [],
    'pathname': ['protocol', 'hostname', 'port'],
    'search': ['protocol', 'hostname', 'port', 'pathname'],
    'hash': ['protocol', 'hostname', 'port', 'pathname', 'search'],
  };

  if (first is Map &&
      earlierComponents[component]!.any((name) => first.containsKey(name))) {
    return '*';
  }

  Uri? baseURL;
  if (first is Map && first['baseURL'] is String) {
    baseURL = Uri.parse(first['baseURL'] as String);
  } else if (pattern.length > 1 && pattern[1] is String) {
    baseURL = Uri.parse(pattern[1] as String);
  }

  if (baseURL != null && component != 'username' && component != 'password') {
    return _baseValue(baseURL, component);
  }

  return '*';
}

void _runUrlPatternTest(Map<String, dynamic> entry) {
  final pattern = entry['pattern'] as List<dynamic>;
  final expectedObject = entry['expected_obj'];

  if (expectedObject == 'error') {
    expect(() => _construct(pattern), throwsA(isA<URLPatternTypeError>()));
    return;
  }

  final urlPattern = _construct(pattern);

  for (final component in _components) {
    expect(
      _componentPatternValue(urlPattern, component),
      _autoExpectedPattern(entry, component),
      reason: "compiled pattern property '$component'",
    );
  }

  final inputs = entry['inputs'] as List<dynamic>;
  final expectedMatch = entry['expected_match'];

  if (expectedMatch == 'error') {
    expect(
      () => _invoke(urlPattern, true, inputs),
      throwsA(isA<URLPatternTypeError>()),
    );
    expect(
      () => _invoke(urlPattern, false, inputs),
      throwsA(isA<URLPatternTypeError>()),
    );
    return;
  }

  final isMatch = expectedMatch is Map;
  expect(_invoke(urlPattern, true, inputs), isMatch, reason: 'test() result');

  final execResult = _invoke(urlPattern, false, inputs) as URLPatternResult?;
  if (!isMatch) {
    expect(execResult, isNull, reason: 'exec() failed match result');
    return;
  }

  final expectedInputs = (expectedMatch['inputs'] as List<dynamic>?) ?? inputs;
  expect(
    execResult!.inputs.length,
    expectedInputs.length,
    reason: 'exec() result.inputs.length',
  );

  for (var i = 0; i < execResult.inputs.length; i++) {
    final actual = execResult.inputs[i];
    final expected = _normalize(expectedInputs[i]);
    if (actual is String) {
      expect(actual, expected, reason: 'exec() result.inputs[$i]');
    } else {
      final actualMap = actual as Map;
      final expectedMap = expected as Map;
      for (final component in _components) {
        expect(
          actualMap[component],
          expectedMap[component],
          reason: 'exec() result.inputs[$i][$component]',
        );
      }
    }
  }

  final exactlyEmpty = entry['exactly_empty_components'] as List<dynamic>?;

  for (final component in _components) {
    var expectedComponent = expectedMatch[component] as Map<String, dynamic>?;
    if (expectedComponent == null) {
      expectedComponent = {'input': '', 'groups': <String, dynamic>{}};
      if (!(exactlyEmpty?.contains(component) ?? false)) {
        (expectedComponent['groups'] as Map<String, dynamic>)['0'] = '';
      }
    }

    final expectedGroups = Map<String, Object?>.from(
      expectedComponent['groups'] as Map? ?? {},
    );

    final actualComponent = _componentResult(execResult, component);
    expect(
      actualComponent.input,
      expectedComponent['input'],
      reason: 'exec() result for $component input',
    );
    expect(
      actualComponent.groups,
      equals(expectedGroups),
      reason: 'exec() result for $component groups',
    );
  }
}

String _componentPatternValue(URLPattern pattern, String component) {
  switch (component) {
    case 'protocol':
      return pattern.protocol;
    case 'username':
      return pattern.username;
    case 'password':
      return pattern.password;
    case 'hostname':
      return pattern.hostname;
    case 'port':
      return pattern.port;
    case 'pathname':
      return pattern.pathname;
    case 'search':
      return pattern.search;
    case 'hash':
      return pattern.hash;
  }
  throw StateError('Unknown component: $component');
}

void main() {
  group('WPT urlpatterntestdata', () {
    final file = File('test/data/urlpatterntestdata.json');
    final data = jsonDecode(file.readAsStringSync()) as List<dynamic>;

    for (var i = 0; i < data.length; i++) {
      final entry = data[i] as Map<String, dynamic>;
      test(
        '#$i Pattern: ${jsonEncode(entry['pattern'])} '
        'Inputs: ${jsonEncode(entry['inputs'])}',
        () => _runUrlPatternTest(entry),
      );
    }
  });

  group('WPT urlpattern-compare-test-data', () {
    final file = File('test/data/urlpattern-compare-test-data.json');
    final data = jsonDecode(file.readAsStringSync()) as List<dynamic>;

    for (var i = 0; i < data.length; i++) {
      final entry = data[i] as Map<String, dynamic>;
      test('#$i Component: ${entry['component']} '
          'Left: ${jsonEncode(entry['left'])} '
          'Right: ${jsonEncode(entry['right'])}', () {
        final left = URLPattern(_normalize(entry['left']));
        final right = URLPattern(_normalize(entry['right']));
        final component = entry['component'] as String;
        final expected = entry['expected'] as int;

        expect(URLPattern.compareComponent(component, left, right), expected);
        expect(
          URLPattern.compareComponent(component, right, left),
          -expected,
          reason: 'reverse order',
        );
        expect(
          URLPattern.compareComponent(component, left, left),
          0,
          reason: 'left equality',
        );
        expect(
          URLPattern.compareComponent(component, right, right),
          0,
          reason: 'right equality',
        );
      });
    }
  });

  group('hasRegExpGroups', () {
    test('reports regexp groups', () {
      expect(URLPattern().hasRegExpGroups, isFalse);
      for (final component in _components) {
        expect(
          URLPattern(<String, Object?>{component: '*'}).hasRegExpGroups,
          isFalse,
        );
        expect(
          URLPattern(<String, Object?>{component: ':foo'}).hasRegExpGroups,
          isFalse,
        );
        expect(
          URLPattern(<String, Object?>{component: ':foo?'}).hasRegExpGroups,
          isFalse,
        );
        expect(
          URLPattern(<String, Object?>{component: ':foo(hi)'}).hasRegExpGroups,
          isTrue,
        );
        expect(
          URLPattern(<String, Object?>{component: '(hi)'}).hasRegExpGroups,
          isTrue,
        );
        if (component != 'protocol' && component != 'port') {
          expect(
            URLPattern(<String, Object?>{component: 'a-{:hello}-z-*-a'})
                .hasRegExpGroups,
            isFalse,
          );
          expect(
            URLPattern(<String, Object?>{component: 'a-(hi)-z-(lo)-a'})
                .hasRegExpGroups,
            isTrue,
          );
        }
      }
      expect(
        URLPattern(<String, Object?>{'pathname': '/a/:foo/:baz?/b/*'})
            .hasRegExpGroups,
        isFalse,
      );
      expect(
        URLPattern(<String, Object?>{'pathname': '/a/:foo/:baz([a-z]+)?/b/*'})
            .hasRegExpGroups,
        isTrue,
      );
    });
  });
}
