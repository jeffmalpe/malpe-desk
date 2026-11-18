import 'dart:io';

import 'package:flutter/material.dart';

import '../consts.dart';
import '../models/platform_model.dart';
import '../models/server_model.dart' show kUsePermanentPassword;

/// "Acesso direto" setup: lets another MALPE Desk enter this PC with a fixed
/// password, without anyone clicking "Accept" on this side.
///
/// It sets the permanent password, approve-mode = password and
/// verification-method = permanent password, and optionally keeps Windows
/// from sleeping. Unattended access only survives a reboot when the app is
/// installed (Windows service), so installing comes first.
class MalpeDirectAccess {
  MalpeDirectAccess._();

  static const _kSetup = 'malpe-direct-setup'; // '', 'done', 'skipped'

  static bool get shouldOfferOnStart =>
      Platform.isWindows &&
      bind.mainGetLocalOption(key: _kSetup).isEmpty &&
      !bind.isOutgoingOnly();

  static Future<void> markSkipped() =>
      bind.mainSetLocalOption(key: _kSetup, value: 'skipped');

  static bool get isEnabled =>
      bind.mainGetOptionSync(key: kOptionApproveMode) == 'password' &&
      bind.mainGetOptionSync(key: kOptionVerificationMethod) ==
          kUsePermanentPassword;

  /// Returns an error message, or null on success.
  static Future<String?> enable(String password, {bool noSleep = true}) async {
    final ok = await bind.mainSetPermanentPasswordWithResult(password: password);
    if (!ok) return 'Não foi possível salvar a senha. Tente de novo.';
    await bind.mainSetOption(
        key: kOptionVerificationMethod, value: kUsePermanentPassword);
    await bind.mainSetOption(key: kOptionApproveMode, value: 'password');
    if (noSleep && Platform.isWindows) {
      try {
        await Process.run('powercfg', ['/change', 'standby-timeout-ac', '0']);
        await Process.run('powercfg', ['/change', 'hibernate-timeout-ac', '0']);
      } catch (_) {
        // Not critical: the user can change it in the Windows power settings.
      }
    }
    await bind.mainSetLocalOption(key: _kSetup, value: 'done');
    return null;
  }

  /// Back to the default: someone on this PC must accept each connection.
  static Future<void> disable() async {
    await bind.mainSetOption(key: kOptionApproveMode, value: '');
    await bind.mainSetOption(key: kOptionVerificationMethod, value: '');
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

/// Opens the setup as a dialog (from the home page button).
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

/// Small button for the home page, under the ID and password.
class MalpeDirectAccessButton extends StatefulWidget {
  const MalpeDirectAccessButton({Key? key}) : super(key: key);

  @override
  State<MalpeDirectAccessButton> createState() =>
      _MalpeDirectAccessButtonState();
}

class _MalpeDirectAccessButtonState extends State<MalpeDirectAccessButton> {
  @override
  Widget build(BuildContext context) {
    final on = MalpeDirectAccess.isEnabled;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: on ? _green : _violetLight,
          side: BorderSide(color: on ? _green.withOpacity(0.5) : _violet),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: Icon(on ? Icons.verified_user : Icons.bolt, size: 18),
        label: Text(on ? 'Acesso direto ligado' : 'Acesso direto',
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
  bool _noSleep = true;
  bool _busy = false;
  bool _show = false;
  String _error = '';
  String? _doneId; // set after success

  bool get _installed => bind.mainIsInstalled();

  @override
  void dispose() {
    _p0.dispose();
    _p1.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final p = _p0.text.trim();
    final rule = MalpeDirectAccess.validatePassword(p);
    if (rule != null) return setState(() => _error = rule);
    if (_p1.text.trim() != p) {
      return setState(() => _error = 'As duas senhas não são iguais.');
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    final err = await MalpeDirectAccess.enable(p, noSleep: _noSleep);
    final id = err == null ? await bind.mainGetMyId() : null;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err ?? '';
      _doneId = id;
    });
  }

  Future<void> _skip() async {
    await MalpeDirectAccess.markSkipped();
    widget.onFinished();
  }

  Future<void> _turnOff() async {
    await MalpeDirectAccess.disable();
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 460,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 12))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: _doneId != null ? _doneView() : _formView(),
      ),
    );
  }

  Widget _header(IconData icon, String title, String subtitle) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
            color: _violet, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: Colors.white),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(color: _muted, fontSize: 13, height: 1.4)),
        ]),
      ),
    ]);
  }

  Widget _stepTitle(int n, String text, {bool done = false}) {
    return Row(children: [
      CircleAvatar(
        radius: 11,
        backgroundColor: done ? _green : _violet,
        child: done
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : Text('$n',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
      ),
      const SizedBox(width: 10),
      Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
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

  Widget _formView() {
    final installed = _installed;
    final enabled = MalpeDirectAccess.isEnabled;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(Icons.bolt, 'Acesso direto',
            'Outro computador MALPE entra neste PC com uma senha fixa, sem ninguém precisar clicar em "Aceitar".'),
        const SizedBox(height: 22),
        _stepTitle(1, 'Instalar neste PC', done: installed),
        Padding(
          padding: const EdgeInsets.only(left: 32, top: 6, bottom: 16),
          child: installed
              ? const Text('Instalado. O MALPE Desk liga junto com o Windows.',
                  style: TextStyle(color: _muted, fontSize: 13))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text(
                      'Sem instalar, o acesso para quando o PC reinicia. O app vai fechar, instalar e abrir de novo; depois volte aqui para o passo 2.',
                      style:
                          TextStyle(color: _muted, fontSize: 13, height: 1.4)),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _violet),
                    icon: const Icon(Icons.download_done, size: 18),
                    label: const Text('Instalar agora'),
                    onPressed: () => bind.mainGotoInstall(),
                  ),
                ]),
        ),
        _stepTitle(2, 'Criar a senha de acesso', done: enabled),
        Padding(
          padding: const EdgeInsets.only(left: 32, top: 10),
          child: Opacity(
            opacity: installed ? 1 : 0.4,
            child: AbsorbPointer(
              absorbing: !installed,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _p0,
                      obscureText: !_show,
                      style: const TextStyle(color: Colors.white),
                      decoration: _dec('Senha (8+ caracteres, A-z e número)')
                          .copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                              _show ? Icons.visibility_off : Icons.visibility,
                              color: _muted,
                              size: 18),
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
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: _noSleep,
                      onChanged: (v) => setState(() => _noSleep = v ?? true),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: _violet,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                          'Não deixar este PC dormir (recomendado para PCs de live)',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                  ]),
            ),
          ),
        ),
        if (_error.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0x33F87171),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x66F87171)),
            ),
            child: Text(_error,
                style: const TextStyle(color: _red, fontSize: 13)),
          ),
        const SizedBox(height: 18),
        Row(children: [
          if (enabled)
            TextButton(
              onPressed: _busy ? null : _turnOff,
              child: const Text('Desligar acesso direto',
                  style: TextStyle(color: _red)),
            )
          else
            TextButton(
              onPressed: _busy ? null : _skip,
              child: const Text('Agora não', style: TextStyle(color: _muted)),
            ),
          const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _violet,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            onPressed: (!installed || _busy) ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(enabled ? 'Trocar a senha' : 'Ligar acesso direto'),
          ),
        ]),
      ],
    );
  }

  Widget _doneView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(Icons.verified_user, 'Acesso direto ligado',
            'Este PC aceita conexões com a senha fixa, sem ninguém clicar em "Aceitar".'),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _field,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ID deste PC',
                style: TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 4),
            SelectableText(_doneId ?? '',
                style: const TextStyle(
                    color: _violetLight,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
          ]),
        ),
        const SizedBox(height: 16),
        const Text('No computador que vai acessar:',
            style: TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text(
            '1. Digite este ID e clique em Conectar.\n'
            '2. Digite a senha uma vez e marque "Lembrar senha".\n'
            '3. Pronto: das próximas vezes entra direto.',
            style: TextStyle(color: _muted, fontSize: 13, height: 1.6)),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _violet,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            onPressed: widget.onFinished,
            child: const Text('Concluir'),
          ),
        ),
      ],
    );
  }
}
