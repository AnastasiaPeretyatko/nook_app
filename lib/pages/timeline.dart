// import 'package:flutter/material.dart';

// class TimalinePage extends StatefulWidget {
//   const TimalinePage({super.key});

//   @override
//   State<TimalinePage> createState() => _TimalinePageState();
// }

// class _TimalinePageState extends State<TimalinePage> {
//   DateTime selectedDay = DateTime.now();

//   List<DateTime> _getWeekDays() {
//     final now = DateTime.now();
//     final monday = now.subtract(Duration(days: now.weekday - 1));
//     return List.generate(7, (i) => monday.add(Duration(days: i)));
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Center(
//         child: _buildWeekStrip()
//         ),
//       ),
//     );
//   }
// }
