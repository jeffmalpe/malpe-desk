import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../consts.dart';
import '../models/platform_model.dart';
import '../models/server_model.dart' show kUsePermanentPassword;

/// MALPE Desk "Conexão direta".
///
/// Main way: when a computer asks to connect, the person ticks "Permitir que
/// este computador se conecte direto" and accepts. From then on that computer
/// gets in without anyone clicking "Aceitar" (see `src/malpe_trust.rs`).
/// This panel lists those computers and removes them.
///
/// Optional extra: a fixed password, for PCs nobody can sit in front of to
/// accept the first connection.
class MalpeDirectAccess {
  MalpeDirectAccess._();

  static const kTrustedPeers = 'malpe-trusted-peers';

  static List<Map<String, dynamic>> trustedPeers() {
    try {
      final raw = bind.mainGetOptionSync(key: kTrustedPeers);
      if (raw.isEmpty) return [];
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> removeTrustedPeer(String id) async {
    final list = trustedPeers().where((e) => e['id'] != id).toList();
    await bind.mainSetOption(
        key: kTrustedPeers, value: list.isEmpty ? '' : jsonEncode(list));
  }

  static bool get passwordModeOn =>
      bind.mainGetOptionSync(key: kOptionApproveMode) == 'password' &&
      bind.mainGetOptionSync(key: kOptionVerificationMethod) ==
          kUsePermanentPassword;

  /// Returns an error message, or null on success.
  static Future<String?> enablePassword(String password) async {
    final ok = await bind.mainSetPermanentPasswordWithResult(password: password);
    if (!ok) return 'Não foi possível salvar a senha. Tente de novo.';
    await bind.mainSetOption(
        key: kOptionVerificationMethod, value: kUsePermanentPassword);
    await bind.mainSetOption(key: kOptionApproveMode, value: 'password');
    return null;
  }

  /// Back to the default: someone on this PC must accept each connection.
  static Future<void> disablePassword() async {
    await bind.mainSetOption(key: kOptionApproveMode, value: '');
    await bind.mainSetOption(key: kOptionVerificationMethod, value: '');
  }

  /// Turns off sleep and hibernation on AC power. Returns true on success.
  static Future<bool> keepAwake() async {
    if (!Platform.isWindows) return false;
    try {
      final a =
          await Process.run('powercfg', ['/change', 'standby-timeout-ac', '0']);
      final b = await Process.run(
          'powercfg', ['/change', 'hibernate-timeout-ac', '0']);
      return a.exitCode == 0 && b.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static String? validatePassword(String p) {
    if (p.length < 8) return 'Use pelo menos 8 caracteres.';
    if (!RegExp(r'[0-9]').hasMatch(p)) return 'Inclua pelo menos um número.';
    if (!RegExp(r'[A-Z]').hasMatch(p)) {
      return 'Inclua pelo menos uma letra maiúscula.';
    }
    if (!RegExp(r'[a-z]').hasMatch(p)) {
      return 'Inclua pelo menos uma letra minúscula.';
    }
    return null;
  }
}

const _card = Color(0xFF141A2C);
const _field = Color(0xFF0E1220);
const _border = Color(0xFF232A40);
const _violet = Color(0xFF6D5DF6);
const _violetLight = Color(0xFFC7C2FF);
const _muted = Color(0xFF8891AD);
const _green = Color(0xFF34D399);
const _red = Color(0xFFF87171);
const _amber = Color(0xFFFBBF24);

Future<void> showMalpeDirectAccessDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: MalpeDirectAccessCard(onFinished: () => Navigator.of(ctx).pop()),
    ),
  );
}

/// Button on the home page, under the ID and password.
class MalpeDirectAccessButton extends StatefulWidget {
  const MalpeDirectAccessButton({Key? key}) : super(key: key);

  @override
  State<MalpeDirectAccessButton> createState() =>
      _MalpeDirectAccessButtonState();
}

class _MalpeDirectAccessButtonState extends State<MalpeDirectAccessButton> {
  @override
  Widget build(BuildContext context) {
    final n = MalpeDirectAccess.trustedPeers().length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: n > 0 ? _green : _violetLight,
            side: BorderSide(color: n > 0 ? _green.withOpacity(0.5) : _violet),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          icon: Icon(n > 0 ? Icons.verified_user : Icons.bolt, size: 18),
          label: Text(n > 0 ? 'Conexão direta ($n)' : 'Conexão direta',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13)),
          onPressed: () async {
            await showMalpeDirectAccessDialog(context);
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }
}

class MalpeDirectAccessCard extends StatefulWidget {
  final VoidCallback onFinished;
  const MalpeDirectAccessCard({Key? key, required this.onFinished})
      : super(key: key);

  @override
  State<MalpeDirectAccessCard> createState() => _MalpeDirectAccessCardState();
}

class _MalpeDirectAccessCardState extends State<MalpeDirectAccessCard> {
  final _p0 = TextEditingController();
  final _p1 = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String _error = '';
  String _info = '';

  @override
  void dispose() {
    _p0.dispose();
    _p1.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    final p = _p0.text.trim();
    final rule = MalpeDirectAccess.validatePassword(p);
    if (rule != null) return setState(() => _error = rule);
    if (_p1.text.trim() != p) {
      return setState(() => _error = 'As duas senhas não são iguais.');
    }
    setState(() {
      _busy = true;
      _error = '';
      _info = '';
    });
    final err = await MalpeDirectAccess.enablePassword(p);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err ?? '';
      _info = err == null ? 'Senha fixa ligada.' : '';
      if (err == null) {
        _p0.clear();
        _p1.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 480,
      constraints: const BoxConstraints(maxHeight: 640),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 12))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              if (!bind.mainIsInstalled()) ...[
                const SizedBox(height: 16),
                _installWarning(),
              ],
              const SizedBox(height: 20),
              _sectionTitle('Computadores com conexão direta'),
              const SizedBox(height: 8),
              _trustedList(),
              const SizedBox(height: 10),
              const Text(
                'Para adicionar: quando um computador pedir para conectar, marque '
                '"Permitir que este computador se conecte direto" e clique em Aceitar.',
                style: TextStyle(color: _muted, fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 18),
              _keepAwakeRow(),
              const SizedBox(height: 8),
              _passwordSection(),
              if (_error.isNotEmpty) _banner(_error, _red),
              if (_info.isNotEmpty) _banner(_info, _green),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _violet,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                  ),
                  onPressed: widget.onFinished,
                  child: const Text('Fechar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
            color: _violet, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.bolt, color: Colors.white),
      ),
      const SizedBox(width: 14),
      const Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Conexão direta',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          Text(
              'Computadores desta lista entram neste PC sem ninguém precisar clicar em "Aceitar".',
              style: TextStyle(color: _muted, fontSize: 13, height: 1.4)),
        ]),
      ),
    ]);
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600));

  Widget _installWarning() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x22FBBF24),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x55FBBF24)),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline, color: _amber, size: 18),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
              'O MALPE Desk não está instalado. Sem instalar, a conexão direta para quando o PC reinicia.',
              style: TextStyle(color: _amber, fontSize: 12.5, height: 1.4)),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => bind.mainGotoInstall(),
          child: const Text('Instalar', style: TextStyle(color: _amber)),
        ),
      ]),
    );
  }

  Widget _trustedList() {
    final peers = MalpeDirectAccess.trustedPeers();
    if (peers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _field,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: const Text('Nenhum computador ainda.',
            style: TextStyle(color: _muted, fontSize: 13)),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: _field,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          for (final p in peers)
            ListTile(
              dense: true,
              leading: const Icon(Icons.computer, color: _violetLight),
              title: Text(
                  (p['name'] ?? '').toString().isEmpty
                      ? p['id'].toString()
                      : p['name'].toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
              subtitle: Text('ID ${p['id']}',
                  style: const TextStyle(color: _muted, fontSize: 12)),
              trailing: TextButton(
                onPressed: () async {
                  await MalpeDirectAccess.removeTrustedPeer(
                      p['id'].toString());
                  // The option goes to the service; give it a moment.
                  await Future.delayed(const Duration(milliseconds: 600));
                  if (mounted) setState(() {});
                },
                child: const Text('Remover', style: TextStyle(color: _red)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _keepAwakeRow() {
    return Row(children: [
      const Icon(Icons.bedtime_off_outlined, color: _muted, size: 18),
      const SizedBox(width: 10),
      const Expanded(
        child: Text('Não deixar este PC dormir (recomendado para PCs de live)',
            style: TextStyle(color: Colors.white, fontSize: 13)),
      ),
      TextButton(
        onPressed: () async {
          final ok = await MalpeDirectAccess.keepAwake();
          if (!mounted) return;
          setState(() {
            _error = ok ? '' : 'Não foi possível mudar a energia do Windows.';
            _info = ok ? 'Pronto: este PC não vai mais dormir na tomada.' : '';
          });
        },
        child: const Text('Aplicar', style: TextStyle(color: _violetLight)),
      ),
    ]);
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _muted),
        filled: true,
        fillColor: _field,
        isDense: true,
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _violet)),
      );

  Widget _passwordSection() {
    final on = MalpeDirectAccess.passwordModeOn;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        iconColor: _muted,
        collapsedIconColor: _muted,
        title: Text(on ? 'Senha fixa: ligada' : 'Senha fixa (opcional)',
            style: TextStyle(
                color: on ? _green : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        subtitle: const Text(
            'Para PCs onde não há ninguém para aceitar a primeira conexão.',
            style: TextStyle(color: _muted, fontSize: 12)),
        children: [
          TextField(
            controller: _p0,
            obscureText: !_show,
            style: const TextStyle(color: Colors.white),
            decoration: _dec('Senha (8+ caracteres, A-z e número)').copyWith(
              suffixIcon: IconButton(
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility,
                    color: _muted, size: 18),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _p1,
            obscureText: !_show,
            style: const TextStyle(color: Colors.white),
            decoration: _dec('Repita a senha'),
            onSubmitted: (_) => _savePassword(),
          ),
          const SizedBox(height: 10),
          Row(children: [
            if (on)
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await MalpeDirectAccess.disablePassword();
                        if (mounted) {
                          setState(() => _info = 'Senha fixa desligada.');
                        }
                      },
                child: const Text('Desligar senha fixa',
                    style: TextStyle(color: _red)),
              ),
            const Spacer(),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _violetLight,
                side: const BorderSide(color: _violet),
              ),
              onPressed: _busy ? null : _savePassword,
              child: Text(on ? 'Trocar senha' : 'Ligar senha fixa'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _banner(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 13)),
    );
  }
}
