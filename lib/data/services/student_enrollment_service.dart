import '../../core/models/student_enrollment_model.dart';
import '../local/app_database.dart';

/// Servicio de enrolamiento local del teléfono del estudiante.
///
/// Valida el contrato del QR generado por el docente, garantiza la integridad
/// del Bitmap y persiste una única credencial por curso.
class StudentEnrollmentService {
  StudentEnrollmentService(AppDatabase database) : _database = database;

  final AppDatabase _database;

  /// Valida y guarda la credencial recibida en el QR de enrolamiento.
  ///
  /// Lanza [FormatException] cuando el texto no es un QR de Asistencia
  /// Uniguajira, está corrupto o incumple el rango del Bitmap.
  Future<StudentEnrollmentModel> enrollFromQrPayload(String rawQrJson) async {
    final payload = rawQrJson.trim();
    if (payload.isEmpty) {
      throw const FormatException('El QR de Asistencia Uniguajira está vacío.');
    }

    final StudentEnrollmentModel enrollment;
    try {
      enrollment = StudentEnrollmentModel.fromQrPayloadJson(payload);
    } on FormatException catch (error) {
      throw FormatException(
        'El QR no pertenece a Asistencia Uniguajira o está corrupto: '
        '${error.message}',
        payload,
      );
    }

    if (enrollment.courseId.isEmpty) {
      throw const FormatException(
        'El QR no contiene el identificador del curso.',
      );
    }
    if (enrollment.studentCode.isEmpty) {
      throw const FormatException(
        'El QR no contiene el código del estudiante.',
      );
    }
    if (enrollment.bitIndex < 0 || enrollment.bitIndex > 63) {
      throw FormatException(
        'El QR tiene bitmapIndex ${enrollment.bitIndex}; '
        'debe estar entre 0 y 63.',
      );
    }
    if (enrollment.deviceSecret.isEmpty) {
      throw const FormatException(
        'El QR no contiene el secreto individual del estudiante.',
      );
    }
    if (enrollment.sharedSecret.isEmpty) {
      throw const FormatException(
        'El QR no contiene el secreto compartido del curso.',
      );
    }

    await _database.upsertStudentEnrollment(enrollment);
    return enrollment;
  }

  /// Lista las credenciales de los cursos enrolados en este teléfono.
  Future<List<StudentEnrollmentModel>> getEnrolledCourses() {
    return _database.getStudentEnrollments();
  }

  /// Elimina la credencial local de un curso.
  Future<void> removeEnrollment(String id) {
    return _database.deleteStudentEnrollment(id);
  }
}
