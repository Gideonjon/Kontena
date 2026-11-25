import 'package:intl/intl.dart';

final _usd = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
final _usd0 = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

String usd(int cents) => _usd.format(cents / 100);
String usdShort(int cents) => cents % 100 == 0 ? _usd0.format(cents / 100) : _usd.format(cents / 100);
String usdStr(String s) => _usd.format(double.tryParse(s) ?? 0);

String dateShort(int epoch) => DateFormat('d MMM, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(epoch * 1000));
String dateDay(int epoch) => DateFormat('d MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(epoch * 1000));

String timeLeft(int epoch) {
  final d = DateTime.fromMillisecondsSinceEpoch(epoch * 1000).difference(DateTime.now());
  if (d.isNegative) return 'Closed';
  if (d.inDays >= 1) return '${d.inDays}d left';
  if (d.inHours >= 1) return '${d.inHours}h left';
  return '${d.inMinutes}m left';
}

String initials(String name) {
  final p = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (p.isEmpty) return '?';
  return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
}

final _ngn = NumberFormat.currency(symbol: '₦', decimalDigits: 2);
/// Kobo (integer, 1/100 naira) -> "₦1,234.50"
String ngn(int kobo) => _ngn.format(kobo / 100);
