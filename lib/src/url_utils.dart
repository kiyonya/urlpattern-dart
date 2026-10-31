import 'dart:convert';

import 'path_to_regex_modified.dart';
import 'url_pattern_interfaces.dart';

final Options defaultOptions = Options(
  delimiter: '',
  prefixes: '',
  sensitive: true,
  strict: true,
);

final Options hostnameOptions = Options(
  delimiter: '.',
  prefixes: '',
  sensitive: true,
  strict: true,
);

final Options pathnameOptions = Options(
  delimiter: '/',
  prefixes: '/',
  sensitive: true,
  strict: true,
);

const List<String> specialSchemes = [
  'ftp',
  'file',
  'http',
  'https',
  'ws',
  'wss',
];

const String _fragmentEncodeChars = ' "<>`';
const String _queryEncodeChars = ' "#<>';
const String _specialQueryEncodeChars = " \"#<>'";
const String _pathEncodeChars = ' "#<>?`{}';
const String _userinfoEncodeChars = ' "#<>?`{}/:;=@[\\]^|';

class UrlParts {
  UrlParts({
    required this.protocol,
    required this.username,
    required this.password,
    required this.hostname,
    required this.port,
    required this.pathname,
    required this.search,
    required this.hash,
  });

  final String protocol;
  final String username;
  final String password;
  final String hostname;
  final String port;
  final String pathname;
  final String search;
  final String hash;
}

String _hex(int value) => value.toRadixString(16).toUpperCase().padLeft(2, '0');

String _percentEncode(String input, String encodeChars) {
  final result = StringBuffer();
  for (final rune in input.runes) {
    if (rune <= 0x7E) {
      final char = String.fromCharCode(rune);
      if (rune <= 0x1F || rune == 0x7F || encodeChars.contains(char)) {
        result.write('%${_hex(rune)}');
      } else {
        result.write(char);
      }
    } else {
      for (final byte in utf8.encode(String.fromCharCode(rune))) {
        result.write('%${_hex(byte)}');
      }
    }
  }
  return result.toString();
}

String _encodeUserInfo(String input) =>
    _percentEncode(input, _userinfoEncodeChars);

String _encodePath(String input) => _percentEncode(input, _pathEncodeChars);

String _encodeOpaquePath(String input) => _percentEncode(input, '');

String _encodeQuery(String input, {required bool special}) {
  return _percentEncode(
    input,
    special ? _specialQueryEncodeChars : _queryEncodeChars,
  );
}

String _encodeFragment(String input) =>
    _percentEncode(input, _fragmentEncodeChars);

bool isAbsolutePathname(String pathname, bool isPattern) {
  if (pathname.isEmpty) {
    return false;
  }

  if (pathname[0] == '/') {
    return true;
  }

  if (!isPattern) {
    return false;
  }

  if (pathname.length < 2) {
    return false;
  }

  if ((pathname[0] == r'\' || pathname[0] == '{') && pathname[1] == '/') {
    return true;
  }

  return false;
}

String _maybeStripPrefix(String value, String prefix) {
  if (value.startsWith(prefix)) {
    return value.substring(prefix.length);
  }
  return value;
}

String _maybeStripSuffix(String value, String suffix) {
  if (value.endsWith(suffix)) {
    return value.substring(0, value.length - suffix.length);
  }
  return value;
}

bool treatAsIPv6Hostname(String? value) {
  if (value == null || value.length < 2) {
    return false;
  }

  if (value[0] == '[') {
    return true;
  }

  if ((value[0] == r'\' || value[0] == '{') && value[1] == '[') {
    return true;
  }

  return false;
}

bool isSpecialScheme(RegExp? protocolRegexp) {
  if (protocolRegexp == null) {
    return true;
  }
  for (final scheme in specialSchemes) {
    if (protocolRegexp.hasMatch(scheme)) {
      return true;
    }
  }
  return false;
}

String urlProtocol(Uri uri) => uri.scheme;

String urlPathname(Uri uri) {
  final path = uri.path;
  if (path.isEmpty && specialSchemes.contains(uri.scheme)) {
    return '/';
  }
  return path;
}

String urlHostname(Uri uri) {
  final host = uri.host;
  if (!host.startsWith('[') && host.contains(':')) {
    return '[$host]';
  }
  return host;
}

String urlPort(Uri uri) {
  if (!uri.hasPort) {
    return '';
  }
  final port = uri.port.toString();
  if (defaultPortForProtocol(uri.scheme) == port) {
    return '';
  }
  return port;
}

String urlUsername(Uri uri) {
  final userInfo = uri.userInfo;
  final index = userInfo.indexOf(':');
  return index == -1 ? userInfo : userInfo.substring(0, index);
}

String urlPassword(Uri uri) {
  final userInfo = uri.userInfo;
  final index = userInfo.indexOf(':');
  return index == -1 ? '' : userInfo.substring(index + 1);
}

String _canonicalizeHostInput(String hostname) {
  if (hostname.isEmpty || hostname.startsWith('[')) {
    return hostname.toLowerCase();
  }
  return _domainToAscii(hostname);
}

UrlParts? parseAbsoluteUrl(String input) {
  final match = RegExp(
    r'^([A-Za-z][A-Za-z0-9+.\-]*):(.*)$',
    dotAll: true,
  ).firstMatch(input);
  if (match == null) {
    return null;
  }

  final protocol = match[1]!.toLowerCase();
  var rest = match[2]!;
  final special = specialSchemes.contains(protocol);

  if (special) {
    rest = rest.replaceAll(r'\', '/');
    if (!rest.startsWith('//')) {
      rest = '//$rest';
    }
  }

  var username = '';
  var password = '';
  var hostname = '';
  var port = '';
  var hasAuthority = false;

  if (rest.startsWith('//')) {
    hasAuthority = true;

    var authorityEnd = rest.length;
    for (final separator in const ['/', '?', '#']) {
      final index = rest.indexOf(separator, 2);
      if (index != -1 && index < authorityEnd) {
        authorityEnd = index;
      }
    }

    final authority = rest.substring(2, authorityEnd);
    rest = rest.substring(authorityEnd);

    final atIndex = authority.lastIndexOf('@');
    if (atIndex != -1) {
      final userInfo = authority.substring(0, atIndex);
      final colonIndex = userInfo.indexOf(':');
      username = _encodeUserInfo(
        colonIndex == -1 ? userInfo : userInfo.substring(0, colonIndex),
      );
      password = _encodeUserInfo(
        colonIndex == -1 ? '' : userInfo.substring(colonIndex + 1),
      );
    }

    var hostPort = authority.substring(atIndex + 1);
    if (hostPort.startsWith('[')) {
      final closeIndex = hostPort.indexOf(']');
      if (closeIndex == -1) {
        return null;
      }
      hostname = hostPort.substring(0, closeIndex + 1).toLowerCase();
      final afterHost = hostPort.substring(closeIndex + 1);
      if (afterHost.startsWith(':')) {
        port = afterHost.substring(1);
      }
    } else {
      final colonIndex = hostPort.lastIndexOf(':');
      if (colonIndex != -1) {
        hostname = hostPort.substring(0, colonIndex);
        port = hostPort.substring(colonIndex + 1);
      } else {
        hostname = hostPort;
      }
      hostname = _canonicalizeHostInput(hostname);
    }
  }

  var pathname = rest;
  var search = '';
  var hash = '';

  final hashIndex = pathname.indexOf('#');
  if (hashIndex != -1) {
    hash = pathname.substring(hashIndex + 1);
    pathname = pathname.substring(0, hashIndex);
  }

  final queryIndex = pathname.indexOf('?');
  if (queryIndex != -1) {
    search = pathname.substring(queryIndex + 1);
    pathname = pathname.substring(0, queryIndex);
  }

  if (hasAuthority) {
    if (special && pathname.isEmpty) {
      pathname = '/';
    }
    pathname = _encodePath(pathname);
  } else {
    pathname = _encodeOpaquePath(pathname);
  }

  search = _encodeQuery(search, special: special);
  hash = _encodeFragment(hash);

  if (defaultPortForProtocol(protocol) == port) {
    port = '';
  }

  return UrlParts(
    protocol: protocol,
    username: username,
    password: password,
    hostname: hostname,
    port: port,
    pathname: pathname,
    search: search,
    hash: hash,
  );
}

String _removeDotSegments(String path) {
  if (path.isEmpty || !path.startsWith('/')) {
    return path;
  }

  final segments = path.substring(1).split('/');
  final output = <String>[];

  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    if (segment == '.') {
      if (i == segments.length - 1) {
        output.add('');
      }
      continue;
    }
    if (segment == '..') {
      if (output.isNotEmpty) {
        output.removeLast();
      }
      if (i == segments.length - 1) {
        output.add('');
      }
      continue;
    }
    output.add(segment);
  }

  return '/${output.join('/')}';
}

String canonicalizeHash(String hash, bool isPattern) {
  hash = _maybeStripPrefix(hash, '#');
  if (isPattern || hash.isEmpty) {
    return hash;
  }
  return _encodeFragment(hash);
}

String canonicalizeSearch(String search, bool isPattern) {
  search = _maybeStripPrefix(search, '?');
  if (isPattern || search.isEmpty) {
    return search;
  }
  return _encodeQuery(search, special: true);
}

String canonicalizeHostname(String hostname, bool isPattern) {
  if (isPattern || hostname.isEmpty) {
    return hostname;
  }
  if (treatAsIPv6Hostname(hostname)) {
    return ipv6HostnameEncodeCallback(hostname);
  }
  return hostnameEncodeCallback(hostname);
}

String canonicalizePassword(String password, bool isPattern) {
  if (isPattern || password.isEmpty) {
    return password;
  }
  return _encodeUserInfo(password);
}

String canonicalizeUsername(String username, bool isPattern) {
  if (isPattern || username.isEmpty) {
    return username;
  }
  return _encodeUserInfo(username);
}

String canonicalizePathname(String pathname, String? protocol, bool isPattern) {
  if (isPattern || pathname.isEmpty) {
    return pathname;
  }

  if (protocol != null &&
      protocol.isNotEmpty &&
      !specialSchemes.contains(protocol)) {
    var opaquePath = pathname;
    final hashIndex = opaquePath.indexOf('#');
    if (hashIndex != -1) {
      opaquePath = opaquePath.substring(0, hashIndex);
    }
    final queryIndex = opaquePath.indexOf('?');
    if (queryIndex != -1) {
      opaquePath = opaquePath.substring(0, queryIndex);
    }
    return _encodeOpaquePath(opaquePath);
  }

  final encoded = _encodePath(pathname.replaceAll(r'\', '/'));
  return _removeDotSegments(encoded);
}

String canonicalizePort(String port, String? protocol, bool isPattern) {
  if (defaultPortForProtocol(protocol) == port) {
    port = '';
  }

  if (isPattern || port.isEmpty) {
    return port;
  }

  return portEncodeCallback(port);
}

String canonicalizeProtocol(String protocol, bool isPattern) {
  protocol = _maybeStripSuffix(protocol, ':');

  if (isPattern || protocol.isEmpty) {
    return protocol;
  }

  return protocolEncodeCallback(protocol);
}

String defaultPortForProtocol(String? protocol) {
  switch (protocol) {
    case 'ws':
    case 'http':
      return '80';
    case 'wws':
    case 'https':
      return '443';
    case 'ftp':
      return '21';
    default:
      return '';
  }
}

String protocolEncodeCallback(String input) {
  if (input.isEmpty) {
    return input;
  }
  if (RegExp(r'^[-+.A-Za-z0-9]*$').hasMatch(input)) {
    return input.toLowerCase();
  }
  throw URLPatternTypeError("Invalid protocol '$input'.");
}

String usernameEncodeCallback(String input) {
  if (input.isEmpty) {
    return input;
  }
  return _encodeUserInfo(input);
}

String passwordEncodeCallback(String input) {
  if (input.isEmpty) {
    return input;
  }
  return _encodeUserInfo(input);
}

String hostnameEncodeCallback(String input) {
  if (input.isEmpty) {
    return input;
  }
  if (RegExp(r'[\t\n\r #%/:<>?@[\]^\\|]').hasMatch(input)) {
    throw URLPatternTypeError("Invalid hostname '$input'");
  }
  return _domainToAscii(input);
}

String ipv6HostnameEncodeCallback(String input) {
  if (input.isEmpty) {
    return input;
  }
  if (RegExp(r'[^0-9a-fA-F[\]:]').hasMatch(input)) {
    throw URLPatternTypeError("Invalid IPv6 hostname '$input'");
  }
  return input.toLowerCase();
}

String portEncodeCallback(String input) {
  if (input.isEmpty) {
    return input;
  }
  if (RegExp(r'^[0-9]*$').hasMatch(input) && int.parse(input) <= 65535) {
    return input;
  }
  throw URLPatternTypeError("Invalid port '$input'.");
}

String standardURLPathnameEncodeCallback(String input) {
  if (input.isEmpty) {
    return input;
  }
  final encoded = _encodePath(input.replaceAll(r'\', '/'));
  return _removeDotSegments(encoded);
}

String pathURLPathnameEncodeCallback(String input) {
  if (input.isEmpty) {
    return input;
  }
  return _encodeOpaquePath(input);
}

String searchEncodeCallback(String input) {
  if (input.isEmpty) {
    return input;
  }
  return _encodeQuery(input, special: true);
}

String hashEncodeCallback(String input) {
  if (input.isEmpty) {
    return input;
  }
  return _encodeFragment(input);
}

const int _punycodeBase = 36;
const int _punycodeTMin = 1;
const int _punycodeTMax = 26;
const int _punycodeSkew = 38;
const int _punycodeDamp = 700;
const int _punycodeInitialBias = 72;
const int _punycodeInitialN = 128;

int _punycodeAdapt(int delta, int numPoints, bool firstTime) {
  delta = firstTime ? delta ~/ _punycodeDamp : delta ~/ 2;
  delta += delta ~/ numPoints;

  var k = 0;
  while (delta > ((_punycodeBase - _punycodeTMin) * _punycodeTMax) ~/ 2) {
    delta ~/= _punycodeBase - _punycodeTMin;
    k += _punycodeBase;
  }

  return k +
      (((_punycodeBase - _punycodeTMin + 1) * delta) ~/
          (delta + _punycodeSkew));
}

String _punycodeDigit(int value) {
  if (value < 26) {
    return String.fromCharCode(0x61 + value);
  }
  return String.fromCharCode(0x30 + value - 26);
}

String _punycodeEncode(String input) {
  final codePoints = input.runes.toList();
  final output = <int>[];
  var basicCount = 0;

  for (final codePoint in codePoints) {
    if (codePoint < 0x80) {
      output.add(codePoint);
      basicCount++;
    }
  }

  var handled = basicCount;
  if (basicCount > 0) {
    output.add(0x2D);
  }

  var n = _punycodeInitialN;
  var delta = 0;
  var bias = _punycodeInitialBias;

  while (handled < codePoints.length) {
    var m = 0x7FFFFFFF;
    for (final codePoint in codePoints) {
      if (codePoint >= n && codePoint < m) {
        m = codePoint;
      }
    }

    delta += (m - n) * (handled + 1);
    n = m;

    for (final codePoint in codePoints) {
      if (codePoint < n) {
        delta++;
      }
      if (codePoint == n) {
        var q = delta;
        var k = _punycodeBase;
        while (true) {
          final t = k <= bias
              ? _punycodeTMin
              : (k >= bias + _punycodeTMax ? _punycodeTMax : k - bias);
          if (q < t) {
            break;
          }
          output.add(
            _punycodeDigit(t + (q - t) % (_punycodeBase - t)).codeUnitAt(0),
          );
          q = (q - t) ~/ (_punycodeBase - t);
          k += _punycodeBase;
        }
        output.add(_punycodeDigit(q).codeUnitAt(0));
        bias = _punycodeAdapt(delta, handled + 1, handled == basicCount);
        delta = 0;
        handled++;
      }
    }

    delta++;
    n++;
  }

  return String.fromCharCodes(output);
}

String _domainToAscii(String hostname) {
  final trailingDot = hostname.endsWith('.');
  final labels = hostname.split('.');
  final result = <String>[];

  for (var i = 0; i < labels.length; i++) {
    var label = labels[i].toLowerCase();
    if (label.isEmpty && i == labels.length - 1 && trailingDot) {
      continue;
    }
    if (label.runes.every((codePoint) => codePoint < 0x80)) {
      result.add(label);
    } else {
      result.add('xn--${_punycodeEncode(label)}');
    }
  }

  return result.join('.') + (trailingDot ? '.' : '');
}
