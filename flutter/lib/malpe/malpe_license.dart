import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:window_manager/window_manager.dart';

import '../models/platform_model.dart';

/// MALPE License System client for MALPE Desk.
///
/// Follows the public contract used by the other MALPE desktop apps:
/// email + license key + a per-install random deviceId, checked against
/// `/licenses/public/activate` once and `/licenses/public/verify` afterwards.
class MalpeLicense {
  MalpeLicense._();

  static const String apiBase = 'https://api-production-ad77.up.railway.app';
  static const String productSlug = 'malpe-desk';
  static const String appVersion = '1.5.3-malpe';
  static const Duration recheckEvery = Duration(minutes: 5);
  static const Duration requestTimeout = Duration(seconds: 15);

  static const _kEmail = 'malpe-license-email';
  static const _kKey = 'malpe-license-key';
  static const _kDevice = 'malpe-device-id';
  static const _kDeadline = 'malpe-offline-deadline';
  static const _kPlan = 'malpe-plan-name';
  static const _kExpires = 'malpe-expires-at';

  static String _get(String k) => bind.mainGetLocalOption(key: k);
  static Future<void> _set(String k, String v) =>
      bind.mainSetLocalOption(key: k, value: v);

  static String get savedEmail => _get(_kEmail);
  static String get savedKey => _get(_kKey);
  static String get planName => _get(_kPlan);
  static String get expiresAt => _get(_kExpires);
  static bool get hasSavedLicense =>
      savedEmail.isNotEmpty && savedKey.isNotEmpty;

  static Future<String> deviceId() async {
    var id = _get(_kDevice);
    if (id.isEmpty) {
      id = const Uuid().v4();
      await _set(_kDevice, id);
    }
    return id;
  }

  static String normalizeKey(String key) => key.trim().toUpperCase();

  static Future<LicenseResult> activate(String email, String key) async {
    final id = await deviceId();
    final host = Platform.localHostname;
    final r = await _post('/licenses/public/activate', {
      'email': email.trim(),
      'key': normalizeKey(key),
      'deviceId': id,
      'deviceLabel': host,
      'computerName': host,
      'operatingSystem': Platform.operatingSystem,
      'appVersion': appVersion,
      'productSlug': productSlug,
    });
    if (r.ok) {
      await _set(_kEmail, email.trim());
      await _set(_kKey, normalizeKey(key));
      await _store(r.body);
    }
    return r;
  }

  static Future<LicenseResult> verify() async {
    if (!hasSavedLicense) {
      return LicenseResult.fail('NO_LICENSE', 'Ative sua licença MALPE.');
    }
    final id = await deviceId();
    final r = await _post('/licenses/public/verify', {
      'key': savedKey,
      'deviceId': id,
      'computerName': Platform.localHostname,
      'operatingSystem': Platform.operatingSystem,
      'appVersion': appVersion,
      'productSlug': productSlug,
    });
    if (r.ok) {
      await _store(r.body);
      return r;
    }
    if (r.isNetworkError && _withinOfflineGrace()) {
      return LicenseResult.offline();
    }
    return r;
  }

  static Future<void> signOut() async {
    if (hasSavedLicense) {
      final id = await deviceId();
      await _post('/licenses/public/deactivate',
          {'key': savedKey, 'deviceId': id});
    }
    for (final k in [_kKey, _kDeadline, _kPlan, _kExpires]) {
      await _set(k, '');
    }
  }

  static bool _withinOfflineGrace() {
    final d = DateTime.tryParse(_get(_kDeadline));
    return d != null && DateTime.now().toUtc().isBefore(d.toUtc());
  }

  static Future<void> _store(Map<String, dynamic> body) async {
    await _set(_kDeadline, (body['offlineDeadline'] ?? '').toString());
    final lic = body['license'];
    if (lic is Map) {
      final plan = lic['plan'];
      await _set(_kPlan, plan is Map ? (plan['name'] ?? '').toString() : '');
      await _set(_kExpires, (lic['expiresAt'] ?? '').toString());
    }
  }

  static Future<LicenseResult> _post(
      String path, Map<String, dynamic> payload) async {
    try {
      final resp = await http
          .post(Uri.parse('$apiBase$path'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload))
          .timeout(requestTimeout);
      Map<String, dynamic> body = {};
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {}
      if (resp.statusCode >= 200 && resp.statusCode < 300 && body['ok'] == true) {
        return LicenseResult(true, body: body);
      }
      final err = body['error'];
      final code = err is Map ? (err['code'] ?? '').toString() : '';
      if (resp.statusCode == 429) {
        return LicenseResult.fail('RATE_LIMIT', _message('RATE_LIMIT'));
      }
      return LicenseResult.fail(
          code.isEmpty ? 'HTTP_${resp.statusCode}' : code, _message(code));
    } on TimeoutException {
      return LicenseResult.network();
    } on SocketException {
      return LicenseResult.network();
    } on http.ClientException {
      return LicenseResult.network();
    }
  }

  static String _message(String code) {
    switch (code) {
      case 'INVALID_LICENSE':
        return 'E-mail ou chave de licença incorretos.';
      case 'LICENSE_NOT_ACTIVE':
        return 'Sua licença está vencida, suspensa ou cancelada. Fale com a MALPE para renovar.';
      case 'PRODUCT_NOT_ENTITLED':
        return 'Esta licença não inclui o MALPE Desk.';
      case 'DEVICE_LIMIT_REACHED':
        return 'Limite de computadores desta licença atingido. Fale com a MALPE.';
      case 'DEVICE_BLOCKED':
        return 'Este computador foi bloqueado. Fale com a MALPE.';
      case 'DEVICE_NOT_ACTIVATED':
        return 'Este computador precisa ser ativado novamente.';
      case 'MAINTENANCE_MODE':
        return 'O sistema de licenças está em manutenção. Tente de novo em alguns minutos.';
      case 'RATE_LIMIT':
        return 'Muitas tentativas. Aguarde um minuto e tente de novo.';
      default:
        return 'Não foi possível validar a licença. Tente novamente.';
    }
  }
}

class LicenseResult {
  final bool ok;
  final bool isNetworkError;
  final bool isOffline;
  final String code;
  final String message;
  final Map<String, dynamic> body;

  LicenseResult(this.ok,
      {this.isNetworkError = false,
      this.isOffline = false,
      this.code = '',
      this.message = '',
      this.body = const {}});

  factory LicenseResult.fail(String code, String message) =>
      LicenseResult(false, code: code, message: message);
  factory LicenseResult.network() => LicenseResult(false,
      isNetworkError: true,
      code: 'NETWORK',
      message: 'Sem conexão com o servidor de licenças. Verifique a internet.');
  factory LicenseResult.offline() => LicenseResult(true, isOffline: true);
}

const _bg = Color(0xFF0E1220);
const _card = Color(0xFF141A2C);
const _border = Color(0xFF232A40);
const _violet = Color(0xFF6D5DF6);
const _violetLight = Color(0xFFC7C2FF);
const _muted = Color(0xFF8891AD);

/// Shows the MALPE login until the license is valid, then the app.
/// Re-checks every few minutes and locks again if the license stops being valid.
class MalpeLicenseGate extends StatefulWidget {
  final Widget child;
  const MalpeLicenseGate({Key? key, required this.child}) : super(key: key);

  @override
  State<MalpeLicenseGate> createState() => _MalpeLicenseGateState();
}

class _MalpeLicenseGateState extends State<MalpeLicenseGate> {
  bool _checking = true;
  bool _unlocked = false;
  String _lockMessage = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startupCheck();
    _timer = Timer.periodic(MalpeLicense.recheckEvery, (_) => _recheck());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _startupCheck() async {
    if (!MalpeLicense.hasSavedLicense) {
      setState(() => _checking = false);
      return;
    }
    final r = await MalpeLicense.verify();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _unlocked = r.ok;
      _lockMessage = r.ok ? '' : r.message;
    });
  }

  Future<void> _recheck() async {
    if (!_unlocked) return;
    final r = await MalpeLicense.verify();
    if (!mounted || r.ok) return;
    setState(() {
      _unlocked = false;
      _lockMessage = r.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        const _MalpeTitleBar(),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _body() {
    return _checking
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: _violet),
              SizedBox(height: 16),
              Text('Verificando licença MALPE…',
                  style: TextStyle(color: _muted, fontSize: 13)),
            ]))
          : MalpeLoginCard(
              initialMessage: _lockMessage,
              onActivated: () => setState(() {
                _unlocked = true;
                _lockMessage = '';
              }),
            );
  }
}

/// Window bar for the login screen: the app's own title bar lives in the
/// main page, which is not shown until the license is valid.
class _MalpeTitleBar extends StatelessWidget {
  const _MalpeTitleBar();

  Widget _btn(IconData icon, VoidCallback onTap, {bool danger = false}) {
    return _HoverButton(icon: icon, onTap: onTap, danger: danger);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: Color(0xFF0A0D18),
        border: Border(bottom: BorderSide(color: Color(0xFF1C2236))),
      ),
      child: Row(children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => windowManager.startDragging(),
            child: const Padding(
              padding: EdgeInsets.only(left: 14),
              child: Row(children: [
                Icon(Icons.desktop_windows_outlined,
                    color: _violetLight, size: 16),
                SizedBox(width: 8),
                Text('MALPE Desk',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
        _btn(Icons.remove, () => windowManager.minimize()),
        _btn(Icons.close, () => windowManager.close(), danger: true),
      ]),
    );
  }
}

class _HoverButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  const _HoverButton(
      {required this.icon, required this.onTap, this.danger = false});

  @override
  State<_HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<_HoverButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: 38,
          color: _hover
              ? (widget.danger ? const Color(0xFFE5484D) : const Color(0xFF1C2236))
              : Colors.transparent,
          child: Icon(widget.icon, size: 16, color: Colors.white70),
        ),
      ),
    );
  }
}

class MalpeLoginCard extends StatefulWidget {
  final String initialMessage;
  final VoidCallback onActivated;
  const MalpeLoginCard(
      {Key? key, required this.initialMessage, required this.onActivated})
      : super(key: key);

  @override
  State<MalpeLoginCard> createState() => _MalpeLoginCardState();
}

class _MalpeLoginCardState extends State<MalpeLoginCard> {
  late final TextEditingController _email =
      TextEditingController(text: MalpeLicense.savedEmail);
  late final TextEditingController _key =
      TextEditingController(text: MalpeLicense.savedKey);
  bool _busy = false;
  late String _error = widget.initialMessage;

  @override
  void dispose() {
    _email.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final key = _key.text.trim();
    if (!email.contains('@') || email.length < 5) {
      setState(() => _error = 'Digite o e-mail cadastrado na MALPE.');
      return;
    }
    if (key.length < 10) {
      setState(() => _error = 'Digite a chave de licença completa.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    final r = await MalpeLicense.activate(email, key);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      widget.onActivated();
    } else {
      setState(() => _error = r.message);
    }
  }

  InputDecoration _field(String label, String hint, IconData icon) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: _muted),
        hintStyle: const TextStyle(color: Color(0xFF4A5275)),
        prefixIcon: Icon(icon, color: _muted, size: 20),
        filled: true,
        fillColor: _bg,
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _violet, width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: 400,
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                      color: _violet, borderRadius: BorderRadius.circular(16)),
                  child: const Center(
                      child: Text('M',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w800))),
                ),
              ),
              const SizedBox(height: 18),
              const Text('MALPE Desk',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Entre com o e-mail e a chave da sua licença MALPE.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, fontSize: 13, height: 1.5)),
              const SizedBox(height: 24),
              TextField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: _field(
                    'E-mail', 'voce@exemplo.com', Icons.mail_outline),
                onChanged: (_) => setState(() => _error = ''),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _key,
                enabled: !_busy,
                style: const TextStyle(
                    color: _violetLight, letterSpacing: 1.5),
                decoration: _field('Chave de licença',
                    'MVL-XXXX-XXXX-XXXX-XXXX', Icons.vpn_key_outlined),
                onChanged: (_) => setState(() => _error = ''),
                onSubmitted: (_) => _submit(),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFF3B1530),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(_error,
                      style: const TextStyle(
                          color: Color(0xFFFCA5A5), fontSize: 13)),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _violet,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Entrar',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 18),
              const Text('MALPE License System · plano mensal ou vitalício',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF6B7393), fontSize: 11)),
              const SizedBox(height: 4),
              const Text('Não tem licença? Fale com a MALPE.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
