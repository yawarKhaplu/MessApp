import 'package:flutter/material.dart';

/// Opens a date picker that cannot throw.
///
/// `showDatePicker` asserts that `initialDate` lies inside the
/// `firstDate`/`lastDate` window and crashes the app if it does not. Stored
/// dates can legitimately sit outside that window — a month range ends on the
/// last day of the month, which is still in the future mid-month — so every
/// date is clamped into the window before it reaches the picker.
Future<DateTime?> pickClampedDate(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
  DatePickerMode initialDatePickerMode = DatePickerMode.day,
}) {
  // A caller may hand over a window that is already inverted.
  final end = lastDate.isBefore(firstDate) ? firstDate : lastDate;

  var start = initialDate;
  if (start.isBefore(firstDate)) start = firstDate;
  if (start.isAfter(end)) start = end;

  return showDatePicker(
    context: context,
    initialDate: start,
    firstDate: firstDate,
    lastDate: end,
    helpText: helpText,
    initialDatePickerMode: initialDatePickerMode,
  );
}