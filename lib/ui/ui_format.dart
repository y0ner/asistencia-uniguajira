/// Textos de fecha, hora y saludo en español cotidiano.
///
/// No depende de `intl` ni de datos de localización: funciona sin
/// inicialización y sin internet.
abstract final class UiFormat {
  static const _days = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  static const _months = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  static String _capitalize(String text) => text[0].toUpperCase() + text.substring(1);

  /// "Miércoles 11 de noviembre".
  static String longDate(DateTime date) {
    return '${_capitalize(_days[date.weekday - 1])} ${date.day} de ${_months[date.month - 1]}';
  }

  /// "Mié 11 nov".
  static String shortDate(DateTime date) {
    final day = _capitalize(_days[date.weekday - 1].substring(0, 3));
    return '$day ${date.day} ${_months[date.month - 1].substring(0, 3)}';
  }

  /// "8:41 a. m.".
  static String time(DateTime date) {
    final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour12:$minute ${date.hour < 12 ? 'a. m.' : 'p. m.'}';
  }

  /// "Mié 11 nov · 8:41 a. m.".
  static String shortDateTime(DateTime date) => '${shortDate(date)} · ${time(date)}';

  /// "Buenos días", "Buenas tardes" o "Buenas noches" según la hora.
  static String greeting(DateTime now) {
    if (now.hour < 12) return 'Buenos días';
    if (now.hour < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  /// "0:12" a partir de una duración (minutos:segundos).
  static String elapsed(Duration duration) {
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '${duration.inMinutes}:$seconds';
  }

  /// "1 estudiante" / "32 estudiantes".
  static String count(int n, String singular, String plural) => '$n ${n == 1 ? singular : plural}';
}
