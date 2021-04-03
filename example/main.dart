import 'package:oauth_dio/oauth_dio.dart';

void main() {
  final oauth = OAuth(
      clientId: 'foo',
      clientSecret: 'bar',
      tokenUrl: 'https://example.com/oauth/token');

  oauth
      .requestToken(PasswordGrant(username: 'foo', password: 'bar'))
      .then((token) {
    print('AccessToken: ${token.accessToken}');
    print('RefreshToken: ${token.refreshToken}');
    print('Expiration: ${token.expiration}');
  });
}
