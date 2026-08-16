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
                            icon: Icon(Icons.home_outlined),
                            selectedIcon: Icon(Icons.home),
                            label: Text('Worker'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.vpn_lock_outlined),
                            selectedIcon: Icon(Icons.vpn_lock),
                            label: Text('Network'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.more_horiz),
                            selectedIcon: Icon(Icons.more),
                            label: Text('More'),
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
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(Icons.home),
                          label: 'Worker',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.vpn_lock_outlined),
                          selectedIcon: Icon(Icons.vpn_lock),
                          label: 'Network',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.more_horiz),
                          selectedIcon: Icon(Icons.more),
                          label: 'More',
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
    _ => _MorePage(controller: widget.controller),
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
            registration == null ? 'Pair this device' : registration.nodeName,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          if (registration == null) ...[
            const SizedBox(height: 8),
            Text(
              'Scan a Fleet QR to get started.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
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
                    FilledButton.icon(
                      key: const Key('open-pairing'),
                      onPressed: () => showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => PairNodeDialog(onPair: controller.pair),
                      ),
                      icon: const Icon(Icons.add_link),
                      label: const Text('Scan Fleet QR'),
                    ),
                  ],
                ),
              ),
            )
          else
            _SessionCard(controller: controller),
          if ((controller.sessionStatus == WorkerSessionStatus.error ||
                  controller.sessionStatus ==
                      WorkerSessionStatus.reconnecting) &&
              controller.message != null) ...[
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
    final status = controller.sessionStatus;
    final running = status == WorkerSessionStatus.running;
    final reconnecting = status == WorkerSessionStatus.reconnecting;
    final busy = status == WorkerSessionStatus.starting;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              running
                  ? Icons.radio_button_checked
                  : reconnecting
                  ? Icons.sync_problem
                  : Icons.pause_circle_outline,
              size: 44,
              color: running
                  ? scheme.primary
                  : reconnecting
                  ? scheme.tertiary
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              running
                  ? 'Online'
                  : reconnecting
                  ? 'Reconnecting…'
                  : busy
                  ? 'Connecting…'
                  : 'Offline',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              running
                  ? 'Connected to the Brain.'
                  : reconnecting
                  ? 'The session stays open while this device retries the Brain.'
                  : 'Start when this device should accept work.',
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (running || reconnecting)
                  OutlinedButton.icon(
                    key: const Key('stop-session'),
                    onPressed: controller.stop,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  )
                else
                  FilledButton.icon(
                    key: const Key('start-session'),
                    onPressed: busy ? null : controller.start,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(busy ? 'Starting…' : 'Start'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MorePage extends StatelessWidget {
  const _MorePage({required this.controller});

  final WorkerController controller;

  @override
  Widget build(BuildContext context) {
    final registration = controller.registration;
    return _PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('More', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.memory_outlined),
              title: const Text('Capabilities'),
              subtitle: const Text('None enabled'),
              childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                SegmentedButton<DistributionTrack>(
                  segments: DistributionTrack.values
                      .map(
                        (track) => ButtonSegment(
                          value: track,
                          label: Text(track.label),
                        ),
                      )
                      .toList(),
                  selected: {controller.track},
                  onSelectionChanged: (value) =>
                      controller.setTrack(value.single),
                ),
                const SizedBox(height: 16),
                Text(
                  'No model runtime is installed. This node stays online but does not advertise generation capabilities.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Node details'),
              subtitle: Text(registration?.nodeName ?? 'Not paired'),
              childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: registration == null
                  ? [const Text('This device is not paired.')]
                  : [
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
                      const _StatusRow(
                        icon: Icons.security,
                        label: 'Credential',
                        value: 'Secure storage',
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
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon),
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
      WorkerSessionStatus.reconnecting => (
        'Reconnecting',
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
