import 'package:flutter/material.dart';

import 'demo_session.dart';
import 'device_benchmark_page.dart';
import 'media_runtime_perf_page.dart';
import 'pages/showcase_page.dart';
import 'pages/status_page.dart';
import 'pages/video_studio_page.dart';
import 'process_page.dart';
import 'queue_page.dart';

void main() {
  runApp(const VideoProcessorDemoApp());
}

class VideoProcessorDemoApp extends StatelessWidget {
  const VideoProcessorDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_video_processor demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const DemoShell(),
    );
  }
}

class DemoShell extends StatefulWidget {
  const DemoShell({super.key});

  @override
  State<DemoShell> createState() => _DemoShellState();
}

class _DemoShellState extends State<DemoShell> {
  final _session = DemoSession();
  int _tab = 0;

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Video Processor'),
            actions: [
              if (_session.busy)
                const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
            ],
          ),
          body: SafeArea(
            child: IndexedStack(
              index: _tab,
              children: [
                ShowcasePage(session: _session),
                const StatusPage(),
                VideoStudioPage(session: _session),
                ProcessPage(session: _session),
                QueuePage(session: _session),
                DeviceBenchmarkPage(session: _session),
                MediaRuntimePerfPage(session: _session),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome),
                label: 'Showcase',
              ),
              NavigationDestination(
                icon: Icon(Icons.circle_outlined),
                selectedIcon: Icon(Icons.add_circle),
                label: 'Status',
              ),
              NavigationDestination(
                icon: Icon(Icons.content_cut_outlined),
                selectedIcon: Icon(Icons.content_cut),
                label: 'Studio',
              ),
              NavigationDestination(
                icon: Icon(Icons.movie_outlined),
                selectedIcon: Icon(Icons.movie),
                label: 'Process',
              ),
              NavigationDestination(
                icon: Icon(Icons.queue_outlined),
                selectedIcon: Icon(Icons.queue),
                label: 'Queue',
              ),
              NavigationDestination(
                icon: Icon(Icons.speed_outlined),
                selectedIcon: Icon(Icons.speed),
                label: 'Benchmark',
              ),
              NavigationDestination(
                icon: Icon(Icons.monitor_heart_outlined),
                selectedIcon: Icon(Icons.monitor_heart),
                label: 'Preview',
              ),
            ],
          ),
        );
      },
    );
  }
}
