import 'package:asistencia_uniguajira/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final morning = DateTime(2026, 11, 11, 8, 41);

  test('fechas en español cotidiano', () {
    expect(UiFormat.longDate(morning), 'Miércoles 11 de noviembre');
    expect(UiFormat.shortDate(morning), 'Mié 11 nov');
    expect(UiFormat.shortDateTime(morning), 'Mié 11 nov · 8:41 a. m.');
    expect(UiFormat.longDate(DateTime(2026, 3, 1)), 'Domingo 1 de marzo');
  });

  test('horas en formato de 12 horas', () {
    expect(UiFormat.time(DateTime(2026, 1, 1, 0, 5)), '12:05 a. m.');
    expect(UiFormat.time(DateTime(2026, 1, 1, 12, 0)), '12:00 p. m.');
    expect(UiFormat.time(DateTime(2026, 1, 1, 19, 30)), '7:30 p. m.');
  });

  test('saludo según la hora', () {
    expect(UiFormat.greeting(DateTime(2026, 1, 1, 7)), 'Buenos días');
    expect(UiFormat.greeting(DateTime(2026, 1, 1, 15)), 'Buenas tardes');
    expect(UiFormat.greeting(DateTime(2026, 1, 1, 21)), 'Buenas noches');
  });

  test('duraciones y plurales', () {
    expect(UiFormat.elapsed(const Duration(seconds: 12)), '0:12');
    expect(UiFormat.elapsed(const Duration(minutes: 3, seconds: 5)), '3:05');
    expect(UiFormat.count(1, 'estudiante', 'estudiantes'), '1 estudiante');
    expect(UiFormat.count(32, 'estudiante', 'estudiantes'), '32 estudiantes');
  });
}
