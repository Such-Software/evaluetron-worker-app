import 'package:flutter/material.dart';

import '../../../core/brand.dart';
import '../../network/presentation/managed_network_controller.dart';
import '../../network/presentation/managed_network_page.dart';
import '../../pairing/presentation/pair_node_dialog.dart';
import '../domain/capability_policy.dart';
import 'worker_controller.dart';

class WorkerHome extends StatefulWidget {
  const WorkerHome({
    required this.controller,
    required this.networkController,
    super.key,
  });

  final WorkerController controller;
  final ManagedNetworkController networkController;

  @override
  State<WorkerHome> createState() => _WorkerHomeState();
}

class _WorkerHomeState extends State<WorkerHome> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (widget.controller.loading &&
            widget.controller.registration == null) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EvaluetronMark(size: 52, semanticLabel: 'Evaluetron Worker'),
                  SizedBox(height: 24),
                  CircularProgressIndicator(
                    semanticsLabel: 'Loading secure node state',
                  ),
                ],
              ),
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final content = _pageForIndex();
            return Scaffold(
              appBar: AppBar(
                toolbarHeight: 72,
                title: const EvaluetronLockup(),
                actions: [
                  _ConnectionBadge(status: widget.controller.sessionStatus),
                  const SizedBox(width: 16),
                ],
              ),
              body: SafeArea(
                child: Row(
                  children: [
                    if (wide)
                      NavigationRail(
                        extended: constraints.maxWidth >= 1100,
                        selectedIndex: _selectedIndex,
                        onDestinationSelected: _select,
                        labelType: constraints.maxWidth >= 1100
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.all,
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.memory_outlined),
                            selectedIcon: Icon(Icons.memory),
                            label: Text('Node'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.vpn_lock_outlined),
                            selectedIcon: Icon(Icons.vpn_lock),
                            label: Text('Network'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.view_list_outlined),
                            selectedIcon: Icon(Icons.view_list),
                            label: Text('Capabilities'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.settings_outlined),
                            selectedIcon: Icon(Icons.settings),
                            label: Text('Settings'),
                          ),
                        ],
                      ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: KeyedSubtree(
                          key: ValueKey(_selectedIndex),
                          child: content,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              bottomNavigationBar: wide
                  ? null
                  : NavigationBar(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: _select,
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.memory_outlined),
                          selectedIcon: Icon(Icons.memory),
                          label: 'Node',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.vpn_lock_outlined),
                          selectedIcon: Icon(Icons.vpn_lock),
                          label: 'Network',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.view_list_outlined),
                          selectedIcon: Icon(Icons.view_list),
                          label: 'Capabilities',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.settings_outlined),
                          selectedIcon: Icon(Icons.settings),
                          label: 'Settings',
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  void _select(int index) => setState(() => _selectedIndex = index);

  Widget _pageForIndex() => switch (_selectedIndex) {
    0 => _NodePage(controller: widget.controller),
    1 => ManagedNetworkPage(controller: widget.networkController),
    2 => _CapabilitiesPage(controller: widget.controller),
    _ => _SettingsPage(controller: widget.controller),
  };
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: child,
        ),
      ),
    );
  }
}

class _NodePage extends StatelessWidget {
  const _NodePage({required this.controller});

  final WorkerController controller;

  @override
  Widget build(BuildContext context) {
    final registration = controller.registration;
    return _PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'EDGE WORKER',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            registration == null
                ? 'Make this device a node'
                : registration.nodeName,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            registration == null
                ? 'Pair directly with a brain. No terminal, copied command, or shared fleet secret.'
                : 'Paired securely with ${registration.brainBaseUrl.host}',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          if (registration == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.phonelink_lock, size: 44),
                    const SizedBox(height: 16),
                    Text(
                      'One-time app enrollment',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Create a Phone or Worker enrollment in Fleet, then paste its private link here.',
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      key: const Key('open-pairing'),
                      onPressed: () => showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => PairNodeDialog(onPair: controller.pair),
                      ),
                      icon: const Icon(Icons.add_link),
                      label: const Text('Pair node'),
                    ),
                  ],
                ),
              ),
            )
          else
            _SessionCard(controller: controller),
          if (controller.message != null) ...[
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(controller.message!),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Runtime status',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const _StatusRow(
                    icon: Icons.security,
                    label: 'Credential',
                    value: 'Platform-secure storage',
                  ),
                  _StatusRow(
                    icon: Icons.model_training_outlined,
                    label: 'Model adapter',
                    value: 'Not installed',
                    warning: true,
                  ),
                  _StatusRow(
                    icon: Icons.workspaces_outline,
                    label: 'Advertised generators',
                    value: 'None',
                    warning: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.controller});

  final WorkerController controller;

  @override
  Widget build(BuildContext context) {
    final running = controller.sessionStatus == WorkerSessionStatus.running;
    final busy = controller.sessionStatus == WorkerSessionStatus.starting;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              running ? Icons.radio_button_checked : Icons.pause_circle_outline,
              size: 44,
              color: running ? Theme.of(context).colorScheme.primary : null,
            ),
            const SizedBox(height: 16),
            Text(
              running ? 'Worker session active' : 'Worker session stopped',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              running
                  ? 'This app is visible and heartbeating to the paired brain.'
                  : 'Starting registers this device and keeps a foreground session alive while the app is open.',
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  key: const Key('start-session'),
                  onPressed: running || busy ? null : controller.start,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(busy ? 'Starting…' : 'Start session'),
                ),
                OutlinedButton.icon(
                  key: const Key('stop-session'),
                  onPressed: running ? controller.stop : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CapabilitiesPage extends StatelessWidget {
  const _CapabilitiesPage({required this.controller});

  final WorkerController controller;

  @override
  Widget build(BuildContext context) {
    final policy = controller.policy;
    return _PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Capability policy',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'The same adaptive UI targets Android and Linux, but distribution rules change what a build may do.',
          ),
          const SizedBox(height: 20),
          SegmentedButton<DistributionTrack>(
            segments: DistributionTrack.values
                .map(
                  (track) =>
                      ButtonSegment(value: track, label: Text(track.label)),
                )
                .toList(),
            selected: {controller.track},
            onSelectionChanged: (value) => controller.setTrack(value.single),
          ),
          const SizedBox(height: 20),
          _PolicyCard(
            title: '${policy.track.label}: allowed',
            icon: Icons.check_circle_outline,
            items: policy.allowed,
          ),
          const SizedBox(height: 16),
          _PolicyCard(
            title: 'Boundaries',
            icon: Icons.gpp_maybe_outlined,
            items: policy.restrictions,
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Current MVP truth: pairing and foreground fleet presence work. '
                'Inference remains disabled until a signed runtime adapter and model provenance checks ship.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•'),
                    const SizedBox(width: 10),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.controller});

  final WorkerController controller;

  @override
  Widget build(BuildContext context) {
    final registration = controller.registration;
    return _PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Node settings',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: registration == null
                  ? const Text('This device is not paired.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _StatusRow(
                          icon: Icons.badge_outlined,
                          label: 'Node',
                          value: registration.nodeName,
                        ),
                        _StatusRow(
                          icon: Icons.dns_outlined,
                          label: 'Brain',
                          value: registration.brainBaseUrl.host,
                        ),
                        _StatusRow(
                          icon: Icons.admin_panel_settings_outlined,
                          label: 'Roles',
                          value: registration.roles.join(', '),
                        ),
                        const Divider(height: 32),
                        OutlinedButton.icon(
                          onPressed: () => _confirmForget(context),
                          icon: const Icon(Icons.link_off),
                          label: const Text('Forget this node'),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmForget(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget this node?'),
        content: const Text(
          'The app will delete its local node credential. An operator should also revoke the node in Fleet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await controller.forgetNode();
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    this.warning = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            color: warning ? Theme.of(context).colorScheme.tertiary : null,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.status});

  final WorkerSessionStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      WorkerSessionStatus.running => (
        'Running',
        Theme.of(context).colorScheme.primary,
      ),
      WorkerSessionStatus.starting => (
        'Starting',
        Theme.of(context).colorScheme.tertiary,
      ),
      WorkerSessionStatus.error => (
        'Attention',
        Theme.of(context).colorScheme.error,
      ),
      WorkerSessionStatus.stopped => ('Stopped', Colors.grey),
    };
    return Semantics(
      label: 'Worker session: $label',
      child: Chip(
        avatar: Icon(Icons.circle, size: 12, color: color),
        label: Text(label),
      ),
    );
  }
}
