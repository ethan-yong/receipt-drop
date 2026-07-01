import 'dart:io';

import 'package:flutter/material.dart';

Widget buildLocalFileImage(
  String path, {
  required Widget placeholder,
}) {
  return Image.file(
    File(path),
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => placeholder,
  );
}
