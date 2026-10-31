import 'parse_shorthand.dart';
import 'url_pattern.dart';
import 'url_pattern_interfaces.dart';
import 'url_utils.dart';

URLPatternInit _merge(URLPatternInit base, URLPatternInit override) {
  final result = URLPatternInit(
    baseURL: base.baseURL,
    username: base.username,
    password: base.password,
    protocol: base.protocol,
    hostname: base.hostname,
    port: base.port,
    pathname: base.pathname,
    search: base.search,
    hash: base.hash,
  );

  if (override.baseURL != null) result.baseURL = override.baseURL;
  if (override.username != null) result.username = override.username;
  if (override.password != null) result.password = override.password;
  if (override.protocol != null) result.protocol = override.protocol;
  if (override.hostname != null) result.hostname = override.hostname;
  if (override.port != null) result.port = override.port;
  if (override.pathname != null) result.pathname = override.pathname;
  if (override.search != null) result.search = override.search;
  if (override.hash != null) result.hash = override.hash;

  return result;
}

bool _isValidUrl(String url) => parseAbsoluteUrl(url) != null;

class URLPatternList {
  URLPatternList(
    List<Object?> list, [
    Map<Object?, Object?> options = const <Object?, Object?>{},
  ]) {
    if (list.isEmpty) {
      return;
    }

    final firstItem = list[0];
    if (firstItem is URLPattern) {
      for (final pattern in list) {
        if (pattern is! URLPattern) {
          throw URLPatternTypeError(
            'parameter list must be if type URLPattern[]',
          );
        }
        _patterns.add(pattern);
      }
    } else {
      try {
        final optionsInit = urlPatternInitFromObject(options);
        for (final patternInit in list) {
          final URLPatternInit init;
          if (patternInit is Map || patternInit is URLPatternInit) {
            init = _merge(optionsInit, urlPatternInitFromObject(patternInit));
          } else if (patternInit is String) {
            init = _merge(optionsInit, parseShorthand(patternInit));
          } else {
            throw URLPatternTypeError('List contains no parsable information');
          }

          _patterns.add(URLPattern(init));
        }
      } catch (_) {
        throw URLPatternTypeError('List contains no parsable information');
      }
    }
  }

  final List<URLPattern> _patterns = [];

  bool test(String url) {
    if (!_isValidUrl(url)) {
      return false;
    }

    for (final urlPattern in _patterns) {
      if (urlPattern.test(url)) {
        return true;
      }
    }
    return false;
  }

  URLPatternResult? exec(String url) {
    if (!_isValidUrl(url)) {
      return null;
    }

    for (final urlPattern in _patterns) {
      final value = urlPattern.exec(url);
      if (value != null) {
        return value;
      }
    }
    return null;
  }
}
