import 'package:flutter/material.dart';

import '../core/theme/bos_tokens.dart';

/// Shown only while the stored session is being read back.
///
/// This is a fraction of a second on a warm start, but it is the difference
/// between opening straight into the dashboard and watching the login screen
/// appear and then vanish.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Scaffold(
      backgroundColor: bos.bgPage,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 66,
              width: 66,
              decoration: BoxDecoration(
                color: bos.brand,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.grid_view_rounded,
                  color: Colors.white, size: 32),
            ),
            const SizedBox(height: 18),
            Text(
              'Zuhoo',
              style: TextStyle(
                color: bos.text,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: bos.brand),
            ),
          ],
        ),
      ),
    );
  }
}
