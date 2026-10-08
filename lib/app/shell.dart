import 'package:flutter/material.dart';

import '../features/administration/presentation/administration_page.dart';
import 'app_state.dart';
import '../features/settings/presentation/appearance_card.dart';
import 'connection_page.dart';
import 'admin_unlock_page.dart';
import '../core/access/sectors.dart';
import '../features/exports/presentation/exports_page.dart';
import '../features/products/presentation/products_page.dart';
import '../features/consumption/presentation/entry_page.dart';
import '../features/consumption/presentation/history_page.dart';
import '../features/reports/presentation/reports_page.dart';
import '../features/settings/presentation/settings_page.dart';

class Shell extends StatefulWidget {
  final AppState state;
  const Shell({super.key, required this.state});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int selected = 0;
  static const labels = [
    'Produtos',
    'Lançar consumo',
    'Histórico',
    'Relatórios',
    'Exportações',
    'Configurações',
    'Administração',
  ];
  static const icons = [
    Icons.inventory_2_outlined,
    Icons.add_circle_outline,
    Icons.receipt_long_outlined,
    Icons.bar_chart_outlined,
    Icons.file_upload_outlined,
    Icons.settings_outlined,
    Icons.admin_panel_settings_outlined,
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && widget.state.adminProtected) {
      widget.state.lockAdministration();
    }
    if (state == AppLifecycleState.resumed) widget.state.sync();
  }

  Future<void> leave() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair ou trocar de setor?'),
        content: const Text(
          'Os registros serão sincronizados e uma cópia local será preservada. Rascunhos ainda não lançados serão descartados. Para entrar novamente ou trocar de setor, use um código autorizado pelo administrador.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sincronizar e sair'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await widget.state.leaveForSetup();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final s = widget.state;
      if (!s.session.accessReady) return ConnectionPage(state: s);
      if (s.adminProtected && !s.adminGuard.unlocked) {
        return AdminUnlockPage(state: s);
      }
      final labels = s.canManage
          ? _ShellState.labels
          : ['Lançar consumo', 'Cancelar consumo'];
      final icons = s.canManage
          ? _ShellState.icons
          : [Icons.add_circle_outline, Icons.cancel_outlined];
      if (selected >= labels.length) selected = 0;
      final wide = MediaQuery.sizeOf(context).width >= 900;
      return Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Image.asset(
                'assets/branding/app_icon.png',
                width: 32,
                height: 32,
                semanticLabel: 'Consumo interno',
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.canManage ? 'Consumo interno' : sectorLabel(s.sectorId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              key: const ValueKey('change-theme'),
              tooltip: 'Alterar tema',
              icon: const Icon(Icons.brightness_6_outlined),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Tema do aparelho'),
                  content: SizedBox(
                    width: 420,
                    child: SingleChildScrollView(
                      child: AppearanceCard(controller: s.appearance),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Fechar'),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Sair ou trocar de setor',
              onPressed: s.syncing ? null : leave,
              icon: const Icon(Icons.logout),
            ),
            if (s.adminProtected)
              IconButton(
                tooltip: 'Bloquear administração',
                onPressed: s.lockAdministration,
                icon: const Icon(Icons.lock_outline),
              ),
            if (wide)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Chip(
                  avatar: Icon(
                    s.pending.isEmpty
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_upload_outlined,
                    size: 18,
                  ),
                  label: Text(
                    s.cloudConfigured
                        ? '${s.pending.length} pendências'
                        : 'Modo local',
                  ),
                ),
              ),
            IconButton(
              tooltip: 'Sincronizar',
              onPressed: s.syncing || !s.cloudConfigured
                  ? null
                  : () => s.sync(),
              icon: s.syncing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.sync),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: Column(
          children: [
            if (!wide)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: Row(
                  children: [
                    Icon(
                      s.cloudConfigured
                          ? Icons.cloud_upload_outlined
                          : Icons.cloud_off_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.syncing
                            ? 'Sincronizando...'
                            : '${s.cloudConfigured ? 'Dados locais' : 'Modo local'} · ${s.pending.length} pendência(s)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (s.syncError.isNotEmpty)
              MaterialBanner(
                content: Text(
                  s.syncError,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                leading: Icon(Icons.cloud_off),
                actions: [
                  TextButton(
                    onPressed: s.canManage
                        ? () => setState(() => selected = 5)
                        : () => s.sync(),
                    child: Text(
                      s.canManage ? 'Ver pendências' : 'Tentar sincronizar',
                    ),
                  ),
                ],
              ),
            Expanded(
              child: Row(
                children: [
                  if (wide)
                    SizedBox(
                      width: 224,
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        child: Column(
                          children: [
                            const SizedBox(height: 20),
                            for (var i = 0; i < labels.length; i++)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                child: ListTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  selected: selected == i,
                                  selectedTileColor: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  leading: Icon(icons[i]),
                                  title: Text(labels[i]),
                                  onTap: () => setState(() => selected = i),
                                ),
                              ),
                            const Spacer(),
                            Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                'Uso interno\nAndroid e Windows',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: IndexedStack(
                      index: selected,
                      children: s.canManage
                          ? [
                              ProductsPage(state: s),
                              EntryPage(state: s),
                              HistoryPage(state: s),
                              ReportsPage(state: s),
                              ExportsPage(state: s),
                              SettingsPage(state: s),
                              AdministrationPage(state: s),
                            ]
                          : [EntryPage(state: s), HistoryPage(state: s)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                labelBehavior:
                    NavigationDestinationLabelBehavior.onlyShowSelected,
                selectedIndex: selected,
                onDestinationSelected: (i) => setState(() => selected = i),
                destinations: [
                  for (var i = 0; i < labels.length; i++)
                    NavigationDestination(
                      icon: Icon(icons[i]),
                      label: (s.canManage
                          ? [
                              'Produtos',
                              'Lançar',
                              'Histórico',
                              'Relatórios',
                              'Exportar',
                              'Ajustes',
                              'Admin',
                            ]
                          : ['Lançar', 'Cancelar'])[i],
                    ),
                ],
              ),
      );
    },
  );
}
