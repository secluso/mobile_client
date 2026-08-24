import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/relay_environment.dart';

/// Bearer-token session for the enterprise delivery service.
class EnterpriseSession {
  /// Refresh this long before the token actually expires
  static const Duration _refreshMargin = Duration(seconds: 60);

  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;

  /// In-flight login/refresh
  Future<String>? _inFlight;

  /// A usable access token, logging in or refreshing if the one we hold has aged out.
  Future<String> accessToken({
    required String serverAddr,
    required String username,
    required String password,
  }) {
    final current = _accessToken;
    final expiresAt = _expiresAt;

    if (current != null &&
        expiresAt != null &&
        DateTime.now().isBefore(expiresAt)) {
      return Future.value(current);
    }

    return _inFlight ??= _authenticate(
      serverAddr: serverAddr,
      username: username,
      password: password,
    ).whenComplete(() => _inFlight = null);
  }

  /// Refresh first: it skips the server's Argon2 verification
  Future<String> _authenticate({
    required String serverAddr,
    required String username,
    required String password,
  }) async {
    final refresh = _refreshToken;

    if (refresh != null) {
      try {
        return await _post(serverAddr, '/account/refresh', {
          'username': username,
          'refresh_token': refresh,
        });
      } catch (e) {
        Log.d('Enterprise refresh failed, logging in again: $e');
        clear();
      }
    }

    return _post(serverAddr, '/account/login', {
      'client_id': username,
      'client_secret': password,
    });
  }

  Future<void> register({
    required String serverAddr,
    required String username,
    required String password,
  }) async {
    try {
      await _post(serverAddr, '/account/register', {
        'username': username,
        'password': password,
      });
    } catch (e) {
      Log.d('Enterprise register did not take ($e); trying to log in');
      await accessToken(
        serverAddr: serverAddr,
        username: username,
        password: password,
      );
    }
  }

  Future<void> registerStrict({
    required String serverAddr,
    required String username,
    required String password,
  }) async {
    await _post(serverAddr, '/account/register', {
      'username': username,
      'password': password,
    });
  }

  /// Claim the free tier for this account.
  ///
  /// The server only allows this while FREE_TIER_OPEN
  ///  403 here = means the gate is closed
  ///  409 = account already has the free tier
  /// Returns the subscription uuid
  Future<String?> claimFreeTier({
    required String serverAddr,
    required String username,
    required String password,
  }) async {
    final token = await accessToken(
      serverAddr: serverAddr,
      username: username,
      password: password,
    );

    final base = Uri.parse(serverAddr);
    final url = base.replace(
      pathSegments: [
        ...base.pathSegments.where((segment) => segment.isNotEmpty),
        'subscription',
        'free',
      ],
    );

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        ...RelayEnvironment.stagingHeaders(),
      },
    );

    final alreadyHolds = response.statusCode == 409;
    if (!alreadyHolds &&
        (response.statusCode < 200 || response.statusCode >= 300)) {
      throw Exception(
        'Free tier claim failed: ${response.statusCode} ${response.body}',
      );
    }

    clear();

    if (alreadyHolds) {
      return null;
    }
    try {
      return (jsonDecode(response.body) as Map<String, dynamic>)['uuid']
          as String?;
    } catch (_) {
      return null;
    }
  }

  /// The subscriptions into an access token's claims.
  static List<dynamic> subsFromToken(String token) {
    try {
      final payload = token.split('.')[1];
      final claims =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(payload))),
              )
              as Map<String, dynamic>;
      return (claims['subs'] as List<dynamic>?) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  Future<String> _post(
    String serverAddr,
    String path,
    Map<String, String> payload,
  ) async {
    final base = Uri.parse(serverAddr);
    final url = base.replace(
      pathSegments: [
        ...base.pathSegments.where((segment) => segment.isNotEmpty),
        ...path.split('/').where((segment) => segment.isNotEmpty),
      ],
    );

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        ...RelayEnvironment.stagingHeaders(),
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Enterprise auth failed at $path: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final access = decoded['access_token'] as String?;
    final refresh = decoded['refresh_token'] as String?;
    final expiresIn = decoded['expires_in'] as int? ?? 0;

    if (access == null || refresh == null) {
      throw Exception('Enterprise auth response was missing a token');
    }

    _accessToken = access;
    _refreshToken = refresh;
    _expiresAt = DateTime.now()
        .add(Duration(seconds: expiresIn < 0 ? 0 : expiresIn))
        .subtract(_refreshMargin);

    return access;
  }

  void clear() {
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
  }
}
