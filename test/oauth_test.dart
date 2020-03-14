import 'package:flutter_test/flutter_test.dart';
import 'package:oauth_dio/oauth_dio.dart';

void main() {
  final oauth = OAuth();

  String lastToken;

  test('Request AccessToken using password grantType', () async {
    OAuthToken token = await oauth.requestToken(
        grantType: 'password',
        username: 'root@b2bnow.com.br',
        password: 'b2bnow2019');

    expect(token.accessToken, isA<String>());

    lastToken = token.accessToken;
  });

  test('Refresh AcessToken using refresh_token grantType', () async {
    final newToken = await oauth.refreshAccessToken();
    expect(newToken.accessToken, isA<String>());
    expect(newToken.accessToken, isNotEmpty);
    expect(newToken.accessToken, isNot(equals(lastToken)));
  });

  test('Clear tokens from storage', () async {
    expect(await oauth.storage.fetch(), isNot(equals(null)));
    await oauth.storage.clear();
    expect(await oauth.storage.fetch(), equals(null));
  });
}
