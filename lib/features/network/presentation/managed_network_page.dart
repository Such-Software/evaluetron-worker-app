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
                    'Managed network',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'A separate, user-approved private network boundary for reaching the paired brain.',
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
                            child: Text(
                              controller.message ??
                                  'Inspecting managed network state.',
                            ),
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              FilledButton.icon(
                                key: const Key('network-start'),
                                onPressed:
                                    controller.status ==
                                        ManagedNetworkStatus.ready
                                    ? controller.start
                                    : null,
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Start private network'),
                              ),
                              OutlinedButton.icon(
                                key: const Key('network-stop'),
                                onPressed: active ? controller.stop : null,
                                icon: const Icon(Icons.stop),
                                label: const Text('Stop'),
                              ),
                              TextButton.icon(
                                key: const Key('network-refresh'),
                                onPressed: controller.initialize,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Check again'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Traffic boundary',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          const _PolicyLine(
                            icon: Icons.route,
                            text:
                                'Only the managed brain host route is eligible.',
                          ),
                          const _PolicyLine(
                            icon: Icons.public_off,
                            text: 'No default route or consumer VPN behavior.',
                          ),
                          const _PolicyLine(
                            icon: Icons.dns_outlined,
                            text: 'No DNS interception.',
                          ),
                          const _PolicyLine(
                            icon: Icons.verified_user_outlined,
                            text:
                                'Normal TLS verification remains in force above the tunnel.',
                          ),
                          if (profile != null)
                            _PolicyLine(
                              icon: Icons.lan_outlined,
                              text:
                                  'Approved route: ${profile.routePolicy.routes.single}',
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Consent and readiness',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Android VPN permission is requested only after you choose to enable a validated profile. '
                            'This build includes the native consent and service boundary, but deliberately does not '
                            'establish a TUN interface because the pinned Nebula packet engine is not linked yet.',
                          ),
                          const SizedBox(height: 16),
                          FilledButton.tonalIcon(
                            key: const Key('network-consent'),
                            onPressed:
                                controller.status ==
                                    ManagedNetworkStatus.consentRequired
                                ? controller.requestConsent
                                : null,
                            icon: const Icon(Icons.admin_panel_settings),
                            label: const Text('Review VPN permission'),
                          ),
                        ],
                      ),
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
