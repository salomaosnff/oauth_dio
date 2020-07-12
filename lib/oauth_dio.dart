library oauth_dio;

import 'dart:convert';

import 'package:dio/dio.dart';

typedef OAuthToken OAuthTokenExtractor(Response response);
typedef Future<bool> OAuthTokenValidator(OAuthToken token);

// Dio Interceptor for Bearer AccessToken
class BearerInterceptor extends Interceptor {
  OAuth oauth;

  BearerInterceptor(this.oauth);

  @override
  Future onRequest(RequestOptions options) async {
    final token = await oauth.fetchOrRefreshAccessToken();
    if (token != null) {
      options.headers.addAll({"Authorization": "Bearer $token"});
    }
    return options;
  }
}

// OAuth Grant Type
abstract class OAuthGrantType {
  RequestOptions handle(RequestOptions request);
}

// GrantType Password
class PasswordGrant extends OAuthGrantType {
  String username;
  String password;
  List<String> scope = [];

  PasswordGrant({this.username, this.password, this.scope});

  @override
  RequestOptions handle(RequestOptions request) {
    request.data =
        "grant_type=password&username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}";
    return request;
  }
}

// GrantType Refresh Token
class RefreshTokenGrant extends OAuthGrantType {
  String refreshToken;

  RefreshTokenGrant({this.refreshToken});

  @override
  RequestOptions handle(RequestOptions request) {
    request.data = "grant_type=refresh_token&refresh_token=$refreshToken";
    return request;
  }
}

// OAuth Storage
abstract class OAuthStorage {
  Future<OAuthToken> fetch();
  Future<OAuthToken> save(OAuthToken token);
  Future<void> clear();
}

// Memory Storage
class OAuthMemoryStorage extends OAuthStorage {
  OAuthToken _token;

  @override
  Future<OAuthToken> fetch() async {
    return _token;
  }

  @override
  Future<OAuthToken> save(OAuthToken token) async {
    return _token = token;
  }

  Future<void> clear() async {
    _token = null;
  }
}

// OAuth Token
class OAuthToken {
  String accessToken;
  String refreshToken;

  OAuthToken({this.accessToken, this.refreshToken});
}

Codec<String, String> stringToBase64 = utf8.fuse(base64);

// OAuth
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

  Future<OAuthToken> requestToken(OAuthGrantType grantType) {
    final request = grantType.handle(
      RequestOptions(
        method: 'POST',
        contentType: 'application/x-www-form-urlencoded',
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "Authorization":
              "Basic ${stringToBase64.encode('$clientId:$clientSecret')}"
        })
    );

    return dio
        .request(tokenUrl, data: request.data, options: request)
        .then((res) => extractor(res))
        .then((token) => storage.save(token));
  }

  Future<OAuthToken> fetchOrRefreshAccessToken() async {
    OAuthToken token = await storage.fetch();

    if (token == null) {
      return null;
    }

    if (await this.validator(token)) return token;

    return this.refreshAccessToken();
  }

  Future<OAuthToken> refreshAccessToken() async {
    OAuthToken token = await storage.fetch();

    return this.requestToken(RefreshTokenGrant(refreshToken: token.refreshToken));
  }
}
