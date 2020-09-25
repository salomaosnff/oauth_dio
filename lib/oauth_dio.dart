library oauth_dio;

import 'dart:convert';

import 'package:dio/dio.dart';

typedef OAuthToken OAuthTokenExtractor(Response response);
typedef Future<bool> OAuthTokenValidator(OAuthToken token);

/// Interceptor to send the bearer access token and update the access token when needed
class BearerInterceptor extends Interceptor {
  OAuth oauth;

  BearerInterceptor(this.oauth);

  /// Add Bearer token to Authorization Header
  @override
  Future onRequest(RequestOptions options) async {
    final token = await oauth.fetchOrRefreshAccessToken();
    if (token != null) {
      options.headers.addAll({"Authorization": "Bearer ${token.accessToken}"});
    }
    return options;
  }
}

/// Use to implement a custom grantType
abstract class OAuthGrantType {
  RequestOptions handle(RequestOptions request);
}

/// Obtain an access token using a username and password
class PasswordGrant extends OAuthGrantType {
  String username;
  String password;
  List<String> scope = [];

  PasswordGrant({this.username, this.password, this.scope});

  /// Prepare Request
  @override
  RequestOptions handle(RequestOptions request) {
    request.data =
        "grant_type=password&username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}";
    return request;
  }
}

/// Obtain an access token using an refresh token
class RefreshTokenGrant extends OAuthGrantType {
  String refreshToken;

  RefreshTokenGrant({this.refreshToken});

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
  Future<OAuthToken> fetch();

  /// Save Token
  Future<OAuthToken> save(OAuthToken token);

  /// Clear token
  Future<void> clear();
}

/// Save Token in Memory
class OAuthMemoryStorage extends OAuthStorage {
  OAuthToken _token;

  /// Read
  @override
  Future<OAuthToken> fetch() async {
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
  String accessToken;
  String refreshToken;

  OAuthToken({this.accessToken, this.refreshToken});
}

/// Encode String To Base64
Codec<String, String> stringToBase64 = utf8.fuse(base64);

/// OAuth Client
class OAuth {
  Dio dio;
  String tokenUrl;
  String clientId;
  String clientSecret;
  OAuthStorage storage;
  OAuthTokenExtractor extractor;
  OAuthTokenValidator validator;

  OAuth(
      {this.tokenUrl,
      this.clientId,
      this.clientSecret,
      this.extractor,
      this.dio,
      this.storage,
      this.validator}) {
    dio = dio ?? Dio();
    storage = storage ?? OAuthMemoryStorage();
    extractor = extractor ??
        (res) => OAuthToken(
            accessToken: res.data['access_token'],
            refreshToken: res.data['refresh_token']);
    validator = validator ?? (token) => Future.value(true);
  }

  /// Request a new Access Token using a strategy
  Future<OAuthToken> requestToken(OAuthGrantType grantType) {
    final request = grantType.handle(RequestOptions(
        method: 'POST',
        contentType: 'application/x-www-form-urlencoded',
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "Authorization":
              "Basic ${stringToBase64.encode('$clientId:$clientSecret')}"
        }));

    return dio
        .request(tokenUrl, data: request.data, options: request)
        .then((res) => extractor(res))
        .then((token) => storage.save(token));
  }

  /// return current access token or refresh
  Future<OAuthToken> fetchOrRefreshAccessToken() async {
    OAuthToken token = await storage.fetch();

    if (token == null) {
      return null;
    }

    if (await this.validator(token)) return token;

    return this.refreshAccessToken();
  }

  /// Refresh Access Token
  Future<OAuthToken> refreshAccessToken() async {
    OAuthToken token = await storage.fetch();

    return this
        .requestToken(RefreshTokenGrant(refreshToken: token.refreshToken));
  }
}
