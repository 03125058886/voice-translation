class PhoneUtils {
  /// Normalize to E.164-ish format. Pakistan numbers default to +92.
  static String normalize(String phone) {
    var p = phone.trim().replaceAll(RegExp(r'[\s\-()]'), '');
    if (p.startsWith('00')) p = '+${p.substring(2)}';
    if (!p.startsWith('+')) p = '+92${p.replaceFirst(RegExp(r'^0'), '')}';
    return p;
  }
}
