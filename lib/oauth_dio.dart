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
  Dio dio = Dio();
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
      this.storage}) {
    dio = dio ?? Dio();
    storage = storage ?? OAuthMemoryStorage();
    extractor = extractor ??
        (res) => OAuthToken(
            accessToken: res.data['access_token'],
            refreshToken: res.data['refresh_token']);
    validator = validator ?? (token) => Future.value(true);
  }

  Future<OAuthToken> requestToken(
      {String grantType,
      String username,
      String password,
      String scope,
      String refreshToken}) {
    final data = {"grant_type": grantType};

    if (grantType == 'password') {
      data.addAll({"username": username, "password": password});
    } else if (grantType == 'refresh_token') {
      data['refresh_token'] = refreshToken;
    }

    if (scope != null && scope.isNotEmpty) {
      data['scope'] = scope;
    }

    final encodedData = data.entries
        .toList()
        .map((entry) => [
              Uri.encodeComponent(entry.key),
              Uri.encodeComponent(entry.value)
            ].join('='))
        .join('&');

    return dio
        .post(tokenUrl,
            data: encodedData,
            options: Options(
                contentType: 'application/x-www-form-urlencoded',
                headers: {
                  "Authorization":
                      "Basic ${stringToBase64.encode('$clientId:$clientSecret')}"
                }))
        .then((res) => extractor(res))
        .then((token) => storage.save(token))
        .catchError((err) {
      print(err.response.data);
      print(err.request.headers);
      throw err;
    });
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

    return this.requestToken(
        grantType: 'refresh_token', refreshToken: token.refreshToken);
  }
}
