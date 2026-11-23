import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.2),
    child: Image.asset(
      'assets/logo.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
      semanticLabel: 'Logótipo AbigailOvos',
    ),
  );
}
