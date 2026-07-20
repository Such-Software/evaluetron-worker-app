import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../features/network/presentation/managed_network_controller.dart';
import '../features/worker/presentation/worker_controller.dart';
import '../features/worker/presentation/worker_home.dart';

class WorkerApp extends StatefulWidget {
  const WorkerApp({
    required this.controller,
    required this.networkController,
    super.key,
  });

  final WorkerController controller;
  final ManagedNetworkController networkController;

  @override
  State<WorkerApp> createState() => _WorkerAppState();
}

class _WorkerAppState extends State<WorkerApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
    widget.networkController.initialize();
  }

  @override
  void dispose() {
    widget.controller.dispose();
    widget.networkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Evaluetron Worker',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: buildWorkerTheme(Brightness.light),
      darkTheme: buildWorkerTheme(Brightness.dark),
      home: WorkerHome(
        controller: widget.controller,
        networkController: widget.networkController,
      ),
    );
  }
}
