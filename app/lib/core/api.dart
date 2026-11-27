import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'config.dart';
import 'passkeys.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);
  @override
  String toString() => message;
}

/// Thin wrapper over the Cloudflare Worker. Always sends a fresh Firebase ID token when signed in.
class Api {
  Api._() {
    _dio = Dio(BaseOptions(
      baseUrl: Config.apiUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        final t = await u.getIdToken();
        o.headers['Authorization'] = 'Bearer $t';
      }
      h.next(o);
    }));
  }
  static final Api i = Api._();
  late final Dio _dio;

  static Map<String, dynamic> _data(Response<dynamic> r) {
    final d = r.data;
    return d is Map<String, dynamic> ? d : <String, dynamic>{};
  }

  static ApiException _error(DioException e) {
    final d = e.response?.data;
    final msg = d is Map && d['error'] is String
        ? d['error'] as String
        : (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout)
            ? 'No connection. Check your internet and try again.'
            : 'Something went wrong. Please try again.';
    return ApiException(msg, e.response?.statusCode);
  }

  /// Runs a request. If the server asks for a fingerprint confirmation (money actions for users with a passkey),
  /// prompts for it once and retries with the confirmation token.
  Future<Map<String, dynamic>> _run(Future<Response<dynamic>> Function(Options o) f) async {
    try {
      return _data(await f(Options()));
    } on DioException catch (e) {
      final err = _error(e);
      if (err.status != 403 || err.message != 'PASSKEY_REQUIRED') throw err;
    }
    final token = await Passkeys.confirm();
    try {
      return _data(await f(Options(headers: {'X-Passkey-Token': token})));
    } on DioException catch (e) {
      throw _error(e);
    }
  }

  Future<Map<String, dynamic>> get(String p, {Map<String, dynamic>? q}) => _run((o) => _dio.get(p, queryParameters: q, options: o));
  Future<Map<String, dynamic>> post(String p, [Object? body]) => _run((o) => _dio.post(p, data: body ?? {}, options: o));
  Future<Map<String, dynamic>> patch(String p, Object body) => _run((o) => _dio.patch(p, data: body, options: o));
  Future<Map<String, dynamic>> delete(String p) => _run((o) => _dio.delete(p, options: o));

  /// Uploads an image and returns its storage key.
  Future<String> upload(List<int> bytes, String contentType) async {
    final r = await _run((_) => _dio.post('/media', data: Stream.fromIterable([bytes]),
        options: Options(contentType: contentType, headers: {Headers.contentLengthHeader: bytes.length})));
    return r['key'] as String;
  }

  static String mediaUrl(String? key) => key == null ? '' : '${Config.apiUrl}/media/$key';
}

extension J on Map<String, dynamic> {
  String s(String k, [String d = '']) => this[k] is String ? this[k] as String : d;
  int i(String k, [int d = 0]) => this[k] is num ? (this[k] as num).toInt() : d;
  bool b(String k) => this[k] == true || this[k] == 1;
  List<Map<String, dynamic>> list(String k) =>
      (this[k] is List ? (this[k] as List) : const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  Map<String, dynamic> m(String k) => this[k] is Map ? Map<String, dynamic>.from(this[k] as Map) : <String, dynamic>{};
}
