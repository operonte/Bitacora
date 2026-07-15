import 'package:flutter/material.dart';

import 'colors.dart';
import 'utils/web_reload_stub.dart'
    if (dart.library.html) 'utils/web_reload_web.dart';

class StartupErrorScreen extends StatelessWidget {
  final String error;

  const StartupErrorScreen({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: AppColors.error,
                ),
                const SizedBox(height: 24),
                const Text(
                  'No se pudo iniciar Bitácora',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const Spacer(),
                const ElevatedButton(
                  onPressed: reloadPage,
                  child: Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
