import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'config.dart';

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

  Future<Map<String, dynamic>> _run(Future<Response<dynamic>> Function() f) async {
    try {
      final r = await f();
      final d = r.data;
      return d is Map<String, dynamic> ? d : <String, dynamic>{};
    } on DioException catch (e) {
      final d = e.response?.data;
      final msg = d is Map && d['error'] is String
          ? d['error'] as String
          : (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout)
              ? 'No connection. Check your internet and try again.'
              : 'Something went wrong. Please try again.';
      throw ApiException(msg, e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> get(String p, {Map<String, dynamic>? q}) => _run(() => _dio.get(p, queryParameters: q));
  Future<Map<String, dynamic>> post(String p, [Object? body]) => _run(() => _dio.post(p, data: body ?? {}));
  Future<Map<String, dynamic>> patch(String p, Object body) => _run(() => _dio.patch(p, data: body));
  Future<Map<String, dynamic>> delete(String p) => _run(() => _dio.delete(p));

  /// Uploads an image and returns its storage key.
  Future<String> upload(List<int> bytes, String contentType) async {
    final r = await _run(() => _dio.post('/media', data: Stream.fromIterable([bytes]),
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
