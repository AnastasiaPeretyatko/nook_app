import 'package:flutter/material.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'package:todo_app/utils/cycle.dart';

/// Phase colours of `DESIGN.md` §6.3. Mid tones, so they read on both themes.
const periodColor = Color(0xFFD07D99);
const fertileColor = Color(0xFF7FA3E3);
const ovulationColor = Color(0xFF5D4DB0);

/// Today's ring and badge on the cycle ring.
const todayBlue = Color(0xFF3B66B5);

/// The cycle ring's dots for the days that are neither period nor fertile.
Color otherDayColor(AppPalette p) => p.background.computeLuminance() > 0.5
    ? const Color(0xFFDDE2EA)
    : p.segmentSelected;

/// The heart of a day marked with sex.
const heartColor = Color(0xFFC04F75);

Color cyclePhaseColor(CyclePhase phase, AppPalette p) => switch (phase) {
  CyclePhase.period => periodColor,
  CyclePhase.fertile => fertileColor,
  CyclePhase.ovulation => ovulationColor,
  CyclePhase.other => p.chip,
};

/// The dot of each mood, in the order of `cycleMoods`.
const cycleMoodColors = [
  Color(0xFF6FB497),
  Color(0xFF7FA3E3),
  Color(0xFF6DAFB2),
  Color(0xFFCF93AB),
  Color(0xFF9C8DDB),
  Color(0xFF8A92A1),
];

/// The dot of a symptom chip: the design gives each one of three tones. Which
/// one is only a matter of the symptom's place in `cycleSymptoms`, so a symptom
/// keeps its colour.
const cycleSymptomColors = [
  Color(0xFFCF93AB),
  Color(0xFF9C8DDB),
  Color(0xFF7FA3E3),
];

/// The dot on the flow's and the discharge's chips.
const cycleFlowDot = periodColor;
const cycleDischargeDot = fertileColor;
