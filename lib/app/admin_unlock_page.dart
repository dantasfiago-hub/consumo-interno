import 'package:flutter/material.dart';
import 'app_state.dart';
import 'connection_page.dart';

class AdminUnlockPage extends StatefulWidget {
  final AppState state;
  const AdminUnlockPage({super.key, required this.state});
  @override
  State<AdminUnlockPage> createState() => _AdminUnlockPageState();
}

class _AdminUnlockPageState extends State<AdminUnlockPage> {
  final password = TextEditingController(),
      confirmation = TextEditingController();
  bool busy = false;
  String error = '';
  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configured = widget.state.adminGuard.configured;
    return Scaffold(
      appBar: AppBar(title: const Text('Acesso administrativo')),
      body: Center(
        child: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                configured
                    ? 'Informe a senha deste aparelho administrativo.'
                    : 'Defina uma senha para proteger as funções administrativas. Nenhum e-mail é necessário.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: password,
                enabled: !busy,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Senha administrativa',
                ),
              ),
              if (!configured) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: confirmation,
                  enabled: !busy,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Repita a senha',
                  ),
                ),
              ],
              if (error.isNotEmpty)
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() {
                          busy = true;
                          error = '';
                        });
                        try {
                          if (!configured) {
                            if (password.text != confirmation.text) {
                              throw StateError('As senhas são diferentes.');
                            }
                            await widget.state.adminGuard.create(password.text);
                          } else {
                            await widget.state.adminGuard.unlock(password.text);
                          }
                          await widget.state.load();
                        } catch (e) {
                          if (mounted) setState(() => error = '$e');
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: Text(
                  busy
                      ? 'Verificando...'
                      : configured
                      ? 'Desbloquear administração'
                      : 'Definir senha',
                ),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ConnectionPage(state: widget.state),
                        ),
                      ),
                child: const Text('Recuperar com novo código de ativação'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
