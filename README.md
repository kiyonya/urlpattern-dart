## URLPattern-Dart

A Dart edition of the
[URLPattern polyfill](https://github.com/kenchris/urlpattern-polyfill).

## Installation

```bash
dart pub add urlpattern_dart
```

## Usage
[https://developer.mozilla.org/en-US/docs/Web/API/URLPattern](https://developer.mozilla.org/en-US/docs/Web/API/URLPattern)

```dart
import 'package:urlpattern_dart/urlpattern.dart';

void main() {
  final pattern = URLPattern({'pathname': '/foo/:name'});

  final result = pattern.exec('https://example.com/foo/bar');
  print(result?.pathname.input); // /foo/bar
  print(result?.pathname.groups['name']); // bar
}
```

```dart
import 'package:urlpattern_dart/urlpattern.dart';

void main() {
  final pattern = URLPattern("*://example.com/foo/*");
  final result = pattern.test('https://example.com/foo/bar');
  print(result); // true
}
```

The package also exposes `URLPatternList` for matching against multiple
patterns.

## License

This package is a Dart port of the URLPattern polyfill. It includes code
derived from the following MIT-licensed projects:

[URLPattern polyfill](https://github.com/kenchris/urlpattern-polyfill)
Copyright 2020 Intel Corporation

[path-to-regexp](https://github.com/pillarjs/path-to-regexp)
Copyright (c) 2014 Blake Embrey (hello@blakeembrey.com)

This package is distributed under the MIT license. See [LICENSE](LICENSE).
