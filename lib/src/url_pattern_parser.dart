import 'path_to_regex_modified.dart';
import 'url_pattern_interfaces.dart';
import 'url_utils.dart';

enum _State {
  init,
  protocol,
  authority,
  username,
  password,
  hostname,
  port,
  pathname,
  search,
  hash,
  done,
}

class Parser {
  Parser(this._input);

  final String _input;

  List<LexToken> _tokenList = [];
  final URLPatternInit _internalResult = URLPatternInit();
  int _tokenIndex = 0;
  int _tokenIncrement = 1;
  int _componentStart = 0;
  _State _state = _State.init;
  int _groupDepth = 0;
  int _hostnameIPv6BracketDepth = 0;
  bool _shouldTreatAsStandardURL = false;

  URLPatternInit get result => _internalResult;

  void parse() {
    _tokenList = lexer(_input, true);

    for (; _tokenIndex < _tokenList.length; _tokenIndex += _tokenIncrement) {
      _tokenIncrement = 1;

      if (_tokenList[_tokenIndex].type == LexTokenType.end) {
        if (_state == _State.init) {
          _rewind();

          if (_isHashPrefix()) {
            _changeState(_State.hash, 1);
          } else if (_isSearchPrefix()) {
            _changeState(_State.search, 1);
          } else {
            _changeState(_State.pathname, 0);
          }
          continue;
        } else if (_state == _State.authority) {
          _rewindAndSetState(_State.hostname);
          continue;
        }

        _changeState(_State.done, 0);
        break;
      }

      if (_groupDepth > 0) {
        if (_isGroupClose()) {
          _groupDepth -= 1;
        } else {
          continue;
        }
      }

      if (_isGroupOpen()) {
        _groupDepth += 1;
        continue;
      }

      switch (_state) {
        case _State.init:
          if (_isProtocolSuffix()) {
            _rewindAndSetState(_State.protocol);
          }
          break;

        case _State.protocol:
          if (_isProtocolSuffix()) {
            _computeShouldTreatAsStandardURL();

            var nextState = _State.pathname;
            var skip = 1;

            if (_nextIsAuthoritySlashes()) {
              nextState = _State.authority;
              skip = 3;
            } else if (_shouldTreatAsStandardURL) {
              nextState = _State.authority;
            }

            _changeState(nextState, skip);
          }
          break;

        case _State.authority:
          if (_isIdentityTerminator()) {
            _rewindAndSetState(_State.username);
          } else if (_isPathnameStart() ||
              _isSearchPrefix() ||
              _isHashPrefix()) {
            _rewindAndSetState(_State.hostname);
          }
          break;

        case _State.username:
          if (_isPasswordPrefix()) {
            _changeState(_State.password, 1);
          } else if (_isIdentityTerminator()) {
            _changeState(_State.hostname, 1);
          }
          break;

        case _State.password:
          if (_isIdentityTerminator()) {
            _changeState(_State.hostname, 1);
          }
          break;

        case _State.hostname:
          if (_isIPv6Open()) {
            _hostnameIPv6BracketDepth += 1;
          } else if (_isIPv6Close()) {
            _hostnameIPv6BracketDepth -= 1;
          }

          if (_isPortPrefix() && _hostnameIPv6BracketDepth == 0) {
            _changeState(_State.port, 1);
          } else if (_isPathnameStart()) {
            _changeState(_State.pathname, 0);
          } else if (_isSearchPrefix()) {
            _changeState(_State.search, 1);
          } else if (_isHashPrefix()) {
            _changeState(_State.hash, 1);
          }
          break;

        case _State.port:
          if (_isPathnameStart()) {
            _changeState(_State.pathname, 0);
          } else if (_isSearchPrefix()) {
            _changeState(_State.search, 1);
          } else if (_isHashPrefix()) {
            _changeState(_State.hash, 1);
          }
          break;

        case _State.pathname:
          if (_isSearchPrefix()) {
            _changeState(_State.search, 1);
          } else if (_isHashPrefix()) {
            _changeState(_State.hash, 1);
          }
          break;

        case _State.search:
          if (_isHashPrefix()) {
            _changeState(_State.hash, 1);
          }
          break;

        case _State.hash:
          break;

        case _State.done:
          break;
      }
    }

    if (_internalResult.hostname != null && _internalResult.port == null) {
      _internalResult.port = '';
    }
  }

  void _changeState(_State newState, int skip) {
    switch (_state) {
      case _State.init:
        break;
      case _State.protocol:
        _internalResult.protocol = _makeComponentString();
        break;
      case _State.authority:
        break;
      case _State.username:
        _internalResult.username = _makeComponentString();
        break;
      case _State.password:
        _internalResult.password = _makeComponentString();
        break;
      case _State.hostname:
        _internalResult.hostname = _makeComponentString();
        break;
      case _State.port:
        _internalResult.port = _makeComponentString();
        break;
      case _State.pathname:
        _internalResult.pathname = _makeComponentString();
        break;
      case _State.search:
        _internalResult.search = _makeComponentString();
        break;
      case _State.hash:
        _internalResult.hash = _makeComponentString();
        break;
      case _State.done:
        break;
    }

    if (_state != _State.init && newState != _State.done) {
      if (const [
            _State.protocol,
            _State.authority,
            _State.username,
            _State.password,
          ].contains(_state) &&
          const [
            _State.port,
            _State.pathname,
            _State.search,
            _State.hash,
          ].contains(newState)) {
        _internalResult.hostname ??= '';
      }
      if (const [
            _State.protocol,
            _State.authority,
            _State.username,
            _State.password,
            _State.hostname,
            _State.port,
          ].contains(_state) &&
          const [_State.search, _State.hash].contains(newState)) {
        _internalResult.pathname ??= _shouldTreatAsStandardURL ? '/' : '';
      }
      if (const [
            _State.protocol,
            _State.authority,
            _State.username,
            _State.password,
            _State.hostname,
            _State.port,
            _State.pathname,
          ].contains(_state) &&
          newState == _State.hash) {
        _internalResult.search ??= '';
      }
    }

    _changeStateWithoutSettingComponent(newState, skip);
  }

  void _changeStateWithoutSettingComponent(_State newState, int skip) {
    _state = newState;

    _componentStart = _tokenIndex + skip;

    _tokenIndex += skip;
    _tokenIncrement = 0;
  }

  void _rewind() {
    _tokenIndex = _componentStart;
    _tokenIncrement = 0;
  }

  void _rewindAndSetState(_State newState) {
    _rewind();
    _state = newState;
  }

  LexToken _safeToken(int index) {
    if (index < 0) {
      index = _tokenList.length - index;
    }

    if (index < _tokenList.length) {
      return _tokenList[index];
    }
    return _tokenList[_tokenList.length - 1];
  }

  bool _isNonSpecialPatternChar(int index, String value) {
    final token = _safeToken(index);
    return token.value == value &&
        (token.type == LexTokenType.char ||
            token.type == LexTokenType.escapedChar ||
            token.type == LexTokenType.invalidChar);
  }

  bool _isProtocolSuffix() {
    return _isNonSpecialPatternChar(_tokenIndex, ':');
  }

  bool _nextIsAuthoritySlashes() {
    return _isNonSpecialPatternChar(_tokenIndex + 1, '/') &&
        _isNonSpecialPatternChar(_tokenIndex + 2, '/');
  }

  bool _isIdentityTerminator() {
    return _isNonSpecialPatternChar(_tokenIndex, '@');
  }

  bool _isPasswordPrefix() {
    return _isNonSpecialPatternChar(_tokenIndex, ':');
  }

  bool _isPortPrefix() {
    return _isNonSpecialPatternChar(_tokenIndex, ':');
  }

  bool _isPathnameStart() {
    return _isNonSpecialPatternChar(_tokenIndex, '/');
  }

  bool _isSearchPrefix() {
    if (_isNonSpecialPatternChar(_tokenIndex, '?')) {
      return true;
    }

    if (_tokenList[_tokenIndex].value != '?') {
      return false;
    }

    final previousToken = _safeToken(_tokenIndex - 1);
    return previousToken.type != LexTokenType.name &&
        previousToken.type != LexTokenType.regex &&
        previousToken.type != LexTokenType.close &&
        previousToken.type != LexTokenType.asterisk;
  }

  bool _isHashPrefix() {
    return _isNonSpecialPatternChar(_tokenIndex, '#');
  }

  bool _isGroupOpen() {
    return _tokenList[_tokenIndex].type == LexTokenType.open;
  }

  bool _isGroupClose() {
    return _tokenList[_tokenIndex].type == LexTokenType.close;
  }

  bool _isIPv6Open() {
    return _isNonSpecialPatternChar(_tokenIndex, '[');
  }

  bool _isIPv6Close() {
    return _isNonSpecialPatternChar(_tokenIndex, ']');
  }

  String _makeComponentString() {
    final token = _tokenList[_tokenIndex];
    final componentCharStart = _safeToken(_componentStart).index;
    return _input.substring(componentCharStart, token.index);
  }

  void _computeShouldTreatAsStandardURL() {
    final options = defaultOptions.copy();
    options.encodePart = protocolEncodeCallback;
    final regexp = stringToRegexp(_makeComponentString(), null, options);
    _shouldTreatAsStandardURL = isSpecialScheme(regexp);
  }
}
