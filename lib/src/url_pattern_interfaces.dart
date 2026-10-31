typedef URLPatternComponent = String;

typedef URLPatternKeys = String;

class URLPatternTypeError extends Error {
  URLPatternTypeError(this.message);

  final String message;

  @override
  String toString() => message;
}

class URLPatternInit {
  URLPatternInit({
    this.baseURL,
    this.username,
    this.password,
    this.protocol,
    this.hostname,
    this.port,
    this.pathname,
    this.search,
    this.hash,
  });

  factory URLPatternInit.fromMap(Map<Object?, Object?> map) {
    String? stringValue(Object? value) => value is String ? value : null;
    return URLPatternInit(
      baseURL: stringValue(map['baseURL']),
      username: stringValue(map['username']),
      password: stringValue(map['password']),
      protocol: stringValue(map['protocol']),
      hostname: stringValue(map['hostname']),
      port: stringValue(map['port']),
      pathname: stringValue(map['pathname']),
      search: stringValue(map['search']),
      hash: stringValue(map['hash']),
    );
  }

  String? baseURL;
  String? username;
  String? password;
  String? protocol;
  String? hostname;
  String? port;
  String? pathname;
  String? search;
  String? hash;

  Map<String, String> toMap() {
    final result = <String, String>{};
    if (baseURL != null) result['baseURL'] = baseURL!;
    if (username != null) result['username'] = username!;
    if (password != null) result['password'] = password!;
    if (protocol != null) result['protocol'] = protocol!;
    if (hostname != null) result['hostname'] = hostname!;
    if (port != null) result['port'] = port!;
    if (pathname != null) result['pathname'] = pathname!;
    if (search != null) result['search'] = search!;
    if (hash != null) result['hash'] = hash!;
    return result;
  }
}

class URLPatternOptions {
  const URLPatternOptions({this.ignoreCase = false});

  final bool ignoreCase;
}

class URLPatternComponentResult {
  const URLPatternComponentResult({required this.input, required this.groups});

  final String input;
  final Map<String, String?> groups;
}

class URLPatternResult {
  const URLPatternResult({
    required this.inputs,
    required this.protocol,
    required this.username,
    required this.password,
    required this.hostname,
    required this.port,
    required this.pathname,
    required this.search,
    required this.hash,
  });

  final List<Object?> inputs;
  final URLPatternComponentResult protocol;
  final URLPatternComponentResult username;
  final URLPatternComponentResult password;
  final URLPatternComponentResult hostname;
  final URLPatternComponentResult port;
  final URLPatternComponentResult pathname;
  final URLPatternComponentResult search;
  final URLPatternComponentResult hash;
}
