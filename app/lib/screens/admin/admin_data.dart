import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api.dart';

final adminSummaryProvider = FutureProvider.autoDispose((ref) => Api.i.get('/admin/summary'));
final adminInspectionsProvider = FutureProvider.autoDispose((ref) => Api.i.get('/admin/orders', q: {'status': 'inspection'}));
final adminRefundIssuesProvider = FutureProvider.autoDispose((ref) => Api.i.get('/admin/refund-issues'));
final adminWithdrawalsProvider = FutureProvider.autoDispose.family((ref, String status) => Api.i.get('/admin/withdrawals', q: {'status': status}));
final adminStoresProvider = FutureProvider.autoDispose((ref) => Api.i.get('/admin/stores'));
