import 'package:flutter/material.dart';

import 'managed_network_controller.dart';

class ManagedNetworkPage extends StatelessWidget {
  const ManagedNetworkPage({required this.controller, super.key});

  final ManagedNetworkController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final profile = controller.profile;
        final active = controller.status == ManagedNetworkStatus.running;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Network',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            active ? Icons.vpn_lock : Icons.vpn_lock_outlined,
                            size: 44,
                            color: active
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _title(controller.status),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Semantics(
                            liveRegion: true,
                            child: Text(_summary(controller.status)),
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              if (controller.status ==
                                  ManagedNetworkStatus.ready)
                                FilledButton.icon(
                                  key: const Key('network-start'),
                                  onPressed: controller.start,
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Start'),
                                ),
                              if (active)
                                OutlinedButton.icon(
                                  key: const Key('network-stop'),
                                  onPressed: controller.stop,
                                  icon: const Icon(Icons.stop),
                                  label: const Text('Stop'),
                                ),
                              if (controller.status ==
                                      ManagedNetworkStatus.engineUnavailable ||
                                  controller.status ==
                                      ManagedNetworkStatus.error)
                                TextButton.icon(
                                  key: const Key('network-refresh'),
                                  onPressed: controller.initialize,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry'),
                                ),
                              if (controller.status ==
                                  ManagedNetworkStatus.consentRequired)
                                FilledButton.tonalIcon(
                                  key: const Key('network-consent'),
                                  onPressed: controller.requestConsent,
                                  icon: const Icon(Icons.admin_panel_settings),
                                  label: const Text('Review permission'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Details'),
                      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      children: [
                        if (controller.message != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(controller.message!),
                            ),
                          ),
                        const _PolicyLine(
                          icon: Icons.route,
                          text: 'Only the Brain route is eligible.',
                        ),
                        const _PolicyLine(
                          icon: Icons.public_off,
                          text: 'No default route.',
                        ),
                        const _PolicyLine(
                          icon: Icons.dns_outlined,
                          text: 'No DNS interception.',
                        ),
                        const _PolicyLine(
                          icon: Icons.verified_user_outlined,
                          text: 'TLS verification remains enabled.',
                        ),
                        if (profile != null)
                          _PolicyLine(
                            icon: Icons.lan_outlined,
                            text: 'Route: ${profile.routePolicy.routes.single}',
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _title(ManagedNetworkStatus status) => switch (status) {
    ManagedNetworkStatus.loading => 'Inspecting…',
    ManagedNetworkStatus.engineUnavailable => 'Tunnel engine not installed',
    ManagedNetworkStatus.notEnrolled => 'Network enrollment required',
    ManagedNetworkStatus.consentRequired => 'Permission required',
    ManagedNetworkStatus.ready => 'Ready to connect',
    ManagedNetworkStatus.running => 'Private network active',
    ManagedNetworkStatus.error => 'Network needs attention',
  };

  static String _summary(ManagedNetworkStatus status) => switch (status) {
    ManagedNetworkStatus.loading => 'Checking status…',
    ManagedNetworkStatus.engineUnavailable => 'Not available in this build.',
    ManagedNetworkStatus.notEnrolled => 'No private network is configured.',
    ManagedNetworkStatus.consentRequired => 'Permission is required.',
    ManagedNetworkStatus.ready => 'Ready.',
    ManagedNetworkStatus.running => 'Connected.',
    ManagedNetworkStatus.error => 'Could not check the network.',
  };
}

class _PolicyLine extends StatelessWidget {
  const _PolicyLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
