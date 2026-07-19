import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../features/worker/presentation/worker_controller.dart';
import '../features/worker/presentation/worker_home.dart';

class WorkerApp extends StatefulWidget {
  const WorkerApp({required this.controller, super.key});

  final WorkerController controller;

  @override
  State<WorkerApp> createState() => _WorkerAppState();
}

class _WorkerAppState extends State<WorkerApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Evaluetron Worker',
      debugShowCheckedModeBanner: false,
      theme: buildWorkerTheme(),
      home: WorkerHome(controller: widget.controller),
    );
  }
}
