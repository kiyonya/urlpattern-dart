import 'package:urlpattern_dart/urlpattern_dart.dart';

void main() {
  final pattern = URLPattern({'pathname': '/foo/:name'});
  final result = pattern.exec('https://example.com/foo/bar');

  print(result?.pathname.input);
  print(result?.pathname.groups['name']);
}
