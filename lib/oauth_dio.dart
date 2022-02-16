library oauth_dio;

import 'dart:convert';

import 'package:dio/dio.dart';

typedef OAuthToken OAuthTokenExtractor(Response response);
typedef Future<bool> OAuthTokenValidator(OAuthToken token);

class OAuthException implements Exception {
  final String code;
  final String message;

  OAuthException(this.code, this.message) : super();

  @override
  String toString() => 'OAuthException: [$code] $message';
}

/// Interceptor to send the bearer access token and update the access token when needed
class BearerInterceptor extends Interceptor {
  OAuth oauth;
  Future<void> Function(Exception error)? onInvalid;

  BearerInterceptor(this.oauth, {this.onInvalid});

  /// Add Bearer token to Authorization Header
  @override
  Future onRequest(RequestOptions options, RequestInterceptorHandler handle) async {
    final token = await oauth.fetchOrRefreshAccessToken().catchError((err) {
      if (onInvalid != null) {
        onInvalid!(err);
      }
      return null;
    });

    if (token != null) {
      options.headers.addAll({"Authorization": "Bearer ${token.accessToken}"});
    }

    return handle.next(options);
  }
}

/// Use to implement a custom grantType
abstract class OAuthGrantType {
  RequestOptions handle(RequestOptions request);
}

/// Obtain an access token using a username and password
class PasswordGrant extends OAuthGrantType {
  final String username;
  final String password;
  final List<String> scope;

  PasswordGrant({this.username = '', this.password = '', this.scope = const []});

  /// Prepare Request
  @override
  RequestOptions handle(RequestOptions request) {
    request.data = {"grant_type": "password", "username": username, "password": password, "scope": scope.join(' ')};

    return request;
  }
}

/// Obtain an access token using an refresh token
class RefreshTokenGrant extends OAuthGrantType {
  String refreshToken;

  RefreshTokenGrant({required this.refreshToken});

  /// Prepare Request
  @override
  RequestOptions handle(RequestOptions request) {
    request.data = "grant_type=refresh_token&refresh_token=$refreshToken";
    return request;
  }
}

/// Use to implement custom token storage
abstract class OAuthStorage {
  /// Read token
  Future<OAuthToken?> fetch();

  /// Save Token
  Future<OAuthToken> save(OAuthToken token);

  /// Clear token
  Future<void> clear();
}

/// Save Token in Memory
class OAuthMemoryStorage extends OAuthStorage {
  OAuthToken? _token;

  /// Read
  @override
  Future<OAuthToken?> fetch() async {
    return _token;
  }

  /// Save
  @override
  Future<OAuthToken> save(OAuthToken token) async {
    return _token = token;
  }

  /// Clear
  Future<void> clear() async {
    _token = null;
  }
}

/// Token
class OAuthToken {
  OAuthToken({this.accessToken, this.refreshToken, this.expiration});

  final String? accessToken;
  final String? refreshToken;
  final DateTime? expiration;

  bool get isExpired => expiration != null && DateTime.now().isAfter(expiration!);

  factory OAuthToken.fromMap(Map<String, dynamic> map) {
    return OAuthToken(
      accessToken: map['access_token'],
      refreshToken: map['refresh_token'],
      expiration: DateTime.now().add(
        Duration(
          seconds: map['expires_in'] ?? map['expires'],
        ),
      ),
    );
  }

  Map<String, dynamic> toMap() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_in': expiration?.millisecondsSinceEpoch,
      };

  String toString() {
    return 'OAuthToken{\naccess_token:${this.accessToken},\nrefresh_token:${this.refreshToken},\nexpires_in:${this.expiration}';
  }
}

/// Encode String To Base64
Codec<String, String> stringToBase64 = utf8.fuse(base64);

/// OAuth Client
class OAuth {
  String tokenUrl;
  String clientId;
  String clientSecret;
  Dio dio;
  OAuthStorage storage;
  OAuthTokenExtractor extractor;
  OAuthTokenValidator validator;

  OAuth({
    required this.tokenUrl,
    required this.clientId,
    required this.clientSecret,
    Dio? dio,
    OAuthStorage? storage,
    OAuthTokenExtractor? extractor,
    OAuthTokenValidator? validator,
  })  : this.dio = dio ?? Dio(),
        this.storage = storage ?? OAuthMemoryStorage(),
        this.extractor = extractor ?? ((res) => OAuthToken.fromMap(res.data)),
        this.validator = validator ?? ((token) => Future.value(!token.isExpired));

  Future<OAuthToken> requestTokenAndSave(OAuthGrantType grantType) async {
    return requestToken(grantType).then((token) => storage.save(token));
  }

  /// Request a new Access Token using a strategy
  Future<OAuthToken> requestToken(OAuthGrantType grantType) {
    final request = grantType.handle(
      RequestOptions(
        method: 'POST',
        path: '/',
        contentType: 'application/x-www-form-urlencoded',
        headers: {"Authorization": "Basic ${stringToBase64.encode('$clientId:$clientSecret')}"},
      ),
    );

    return this
        .dio
        .request(tokenUrl,
            data: request.data,
            options: Options(
              contentType: request.contentType,
              headers: request.headers,
              method: request.method,
            ))
        .then((res) => extractor(res));
  }

  /// return current access token or refresh
  Future<OAuthToken?> fetchOrRefreshAccessToken() async {
    OAuthToken? token = await this.storage.fetch();

    if (token?.accessToken == null) {
      throw OAuthException('missing_access_token', 'Missing access token!');
    }

    if (await this.validator(token!)) return token;

    return this.refreshAccessToken();
  }

  /// Refresh Access Token
  Future<OAuthToken> refreshAccessToken() async {
    OAuthToken? token = await this.storage.fetch();

    if (token?.refreshToken == null) {
      throw OAuthException('missing_refresh_token', 'Missing refresh token!');
    }

    return this.requestTokenAndSave(RefreshTokenGrant(refreshToken: token!.refreshToken!));
  }
}
