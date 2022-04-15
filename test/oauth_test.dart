import 'package:oauth_dio/oauth_dio.dart';
import 'package:test/test.dart';

void main() {
  final oauth = OAuth(
    tokenUrl: 'https://api.pubby.club/oauth/token',
    clientId: 'pubby_web',
    clientSecret: '12345',
  );

  String? lastToken;

  test('Request AccessToken using password grantType', () async {
    OAuthToken token = await oauth.requestTokenAndSave(
        PasswordGrant(username: 'neto', password: '01061999', scope: ['user']));

    expect(token.accessToken, isA<String>());
    expect(token.refreshToken, isA<String>());

    lastToken = token.accessToken;
  });

  test('Refresh AccessToken using refresh_token grantType', () async {
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
