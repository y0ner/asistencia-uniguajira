import 'package:flutter/material.dart';

import 'app/app_flavor.dart';
import 'app/asistencia_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AsistenciaApp(flavor: AppFlavor.docente));
}
