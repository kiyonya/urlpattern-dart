import 'url_pattern_interfaces.dart';

URLPatternInit parseShorthand(String str) {
  var protocol = '';
  var hostname = '';
  var pathname = '';
  var search = '';
  var hash = '';

  var i = str.indexOf('://');
  if (i != -1) {
    protocol = str.substring(0, i);
    str = str.substring(i + 3);

    i = str.indexOf('/');
    if (i == -1) {
      hostname = '';
    } else {
      hostname = str.substring(0, i);
      str = str.substring(i + 1);
    }
  }

  i = str.indexOf('#');
  if (i != -1) {
    hash = str.substring(i + 1);
    str = str.substring(0, i);
  }

  str = str
      .replaceAllMapped(RegExp(r'(:\w+)\?'), (match) => '${match[1]}§')
      .replaceAll('*?', '*§')
      .replaceAll(')?', ')§');
  i = str.indexOf('?');

  if (i != -1) {
    pathname = str.substring(0, i).replaceFirst('§', '?');
    search = str.substring(i + 1).replaceFirst('§', '?');
  } else {
    pathname = str.replaceFirst('§', '?');
  }

  return URLPatternInit(
    protocol: protocol,
    hostname: hostname,
    pathname: pathname,
    search: search,
    hash: hash,
  );
}
