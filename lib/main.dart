import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'core/constants/app_constants.dart';
import 'data/services/demo_seed_service.dart';
import 'features/student/student_courses_screen.dart';
import 'features/teacher/course_detail_screen.dart';
import 'features/teacher/course_reports_screen.dart';
import 'features/teacher/courses_dashboard_screen.dart';

/// Azul Institucional oficial de la Universidad de La Guajira.
const Color uniguajiraBlue = Color(0xFF0033A0);

/// Dorado Académico oficial de la Universidad de La Guajira.
const Color uniguajiraGold = Color(0xFFEAAA00);

void main() {
  runApp(const AsistenciaUniguajiraApp());
}

/// Raíz de la aplicación institucional de Asistencia Uniguajira.
class AsistenciaUniguajiraApp extends StatelessWidget {
  const AsistenciaUniguajiraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: uniguajiraBlue,
      primary: uniguajiraBlue,
      secondary: uniguajiraGold,
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        appBarTheme: const AppBarTheme(
          backgroundColor: uniguajiraBlue,
          foregroundColor: Colors.white,
          elevation: 2,
          centerTitle: true,
        ),
        cardTheme: const CardThemeData(
          elevation: 1.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
      ),
      home: const RoleSelectorScreen(),
    );
  }
}

/// Pantalla principal y selector de rol institucional con panel de sustentación
/// oficial 1-clic y diagnóstico de hardware BLE / Cámara.
class RoleSelectorScreen extends StatefulWidget {
  const RoleSelectorScreen({super.key});

  @override
  State<RoleSelectorScreen> createState() => _RoleSelectorScreenState();
}

class _RoleSelectorScreenState extends State<RoleSelectorScreen> {
  bool _isSeeding = false;

  void _navigateTo(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  /// Ejecuta la siembra determinista oficial en 1 clic para la sustentación.
  Future<void> _seedDemoScenario() async {
    setState(() => _isSeeding = true);

    try {
      final seedService = DemoSeedService();
      final result = await seedService.seedDefenseDemonstrationData(
        resetExisting: true,
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => _DefenseDemoResultDialog(
          result: result,
          onOpenTeacherCourse: () {
            Navigator.of(dialogCtx).pop();
            _navigateTo(CourseDetailScreen(course: result.course));
          },
          onOpenReports: () {
            Navigator.of(dialogCtx).pop();
            _navigateTo(CourseReportsScreen(course: result.course));
          },
          onOpenStudentWallet: () {
            Navigator.of(dialogCtx).pop();
            _navigateTo(const StudentCoursesScreen());
          },
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al sembrar escenario: $error'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSeeding = false);
      }
    }
  }

  /// Despliega el modal de diagnóstico de hardware en Android o Linux Desktop.
  Future<void> _showHardwareDiagnosticModal() async {
    if (Platform.isAndroid) {
      await showDialog<void>(
        context: context,
        builder: (_) => const _AndroidHardwareDiagnosticDialog(),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (_) => const _DesktopHardwareDiagnosticDialog(),
      );
    }
  }

  /// Despliega la ficha técnica y créditos institucionales del proyecto de grado.
  void _showAboutProjectDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
        title: const Row(
          children: <Widget>[
            Icon(Icons.school_rounded, color: uniguajiraBlue, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Acerca del Proyecto de Grado',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: uniguajiraBlue,
                ),
              ),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Universidad de La Guajira · Facultad de Ingeniería · Programa de Ingeniería de Sistemas.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: uniguajiraBlue,
                ),
              ),
              SizedBox(height: 16),
              _CreditItem(
                label: 'Autores',
                value:
                    'Yoner De Jesus Isaza Vides (0182120016) y Álvaro Luis Garrido Medina (0182110072).',
              ),
              SizedBox(height: 10),
              _CreditItem(
                label: 'Asignatura',
                value: 'Proyectos II',
              ),
              SizedBox(height: 10),
              _CreditItem(
                label: 'Docente',
                value: 'Miguel Humberto Romero Acuña',
              ),
              SizedBox(height: 10),
              _CreditItem(
                label: 'Directora',
                value: 'Lisseth Paola Castañeda Vega',
              ),
              Divider(height: 24),
              Text(
                'Resumen de Arquitectura',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Persistencia Offline-First SQLite v3, BLE Legacy Service UUID de 16 bytes (128 bits) sin GATT, rotación temporal HMAC-SHA256 cada 30s (±1 tick), Eco Docente con Mapa de Bits de 8 bytes (64 posiciones), Lista Invertida de excepción y exportación Excel .xlsx de 4 hojas con sincronización institucional @uniguajira.edu.co.',
                style: TextStyle(fontSize: 12, height: 1.45),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Universidad de La Guajira',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Diagnóstico de Permisos Hardware',
            icon: const Icon(Icons.build_circle_outlined),
            onPressed: _showHardwareDiagnosticModal,
          ),
          IconButton(
            tooltip: 'Acerca del Proyecto de Grado',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: _showAboutProjectDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // -----------------------------------------------------------
                  // 1. Tema e Identidad Institucional Material 3
                  // -----------------------------------------------------------
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: uniguajiraBlue.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                        border: Border.all(color: uniguajiraGold, width: 2.5),
                      ),
                      child: const Icon(
                        Icons.school_rounded,
                        size: 54,
                        color: uniguajiraBlue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Asistencia Multimodal Uniguajira',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: uniguajiraBlue,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Proximidad Criptográfica BLE (Bitmap 8B) + Lista Invertida Offline-First',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: uniguajiraBlue.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: uniguajiraBlue.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.verified_user_rounded,
                            size: 16,
                            color: uniguajiraBlue,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Costo de Servidor \$0 · Soberanía de Datos ${AppConstants.institutionalDomain}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: uniguajiraBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // -----------------------------------------------------------
                  // 2. Panel Destacado: Modo Sustentación frente al Jurado
                  // -----------------------------------------------------------
                  _DefenseDemoCard(
                    isSeeding: _isSeeding,
                    onStartDemo: _isSeeding ? null : _seedDemoScenario,
                  ),
                  const SizedBox(height: 24),

                  // -----------------------------------------------------------
                  // 3. Tarjetas Principales de Rol con Navegación Directa
                  // -----------------------------------------------------------
                  Text(
                    'ROLES OPERATIVOS DEL SISTEMA',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _RoleOptionCard(
                    title: 'Modo Docente',
                    subtitle:
                        'Control de cursos, radar BLE de aula, lista invertida y actas firmadas',
                    icon: Icons.co_present_rounded,
                    capabilities: const <String>[
                      'Ingesta CSV/XLSX',
                      'Radar BLE 16B',
                      'Lista Invertida 1-Toque',
                      'Excel Oficial 4 Hojas',
                    ],
                    accentColor: uniguajiraBlue,
                    onTap: () => _navigateTo(const CoursesDashboardScreen()),
                  ),
                  const SizedBox(height: 14),
                  _RoleOptionCard(
                    title: 'Modo Estudiante',
                    subtitle:
                        'Billetera de asignaturas enroladas, baliza BLE y confirmación criptográfica',
                    icon: Icons.badge_rounded,
                    capabilities: const <String>[
                      'Enrolamiento QR Offline',
                      'Token HMAC-SHA256 30s',
                      'PIN Verbal Anti-Pasillo',
                      'Sello Criptográfico Verde',
                    ],
                    accentColor: const Color(0xFF007A33),
                    onTap: () => _navigateTo(const StudentCoursesScreen()),
                  ),
                  const SizedBox(height: 24),

                  // -----------------------------------------------------------
                  // 4. Modal de Diagnóstico de Permisos Hardware
                  // -----------------------------------------------------------
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(
                      Icons.settings_input_antenna_rounded,
                      color: uniguajiraBlue,
                    ),
                    label: const Text(
                      'Diagnóstico de Permisos Hardware',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: uniguajiraBlue,
                      ),
                    ),
                    onPressed: _showHardwareDiagnosticModal,
                  ),
                  const SizedBox(height: 12),

                  // -----------------------------------------------------------
                  // 5. Botón Ficha Técnica y Créditos Oficiales
                  // -----------------------------------------------------------
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.info_outline_rounded, size: 18),
                    label: const Text(
                      'Acerca del Proyecto de Grado · Créditos y Arquitectura',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: _showAboutProjectDialog,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Componentes Visuales Auxiliares
// =============================================================================

/// Tarjeta destacada de lanzamiento del escenario de sustentación evaluativa.
class _DefenseDemoCard extends StatelessWidget {
  const _DefenseDemoCard({
    required this.isSeeding,
    required this.onStartDemo,
  });

  final bool isSeeding;
  final VoidCallback? onStartDemo;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: uniguajiraGold, width: 2),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: <Color>[
              const Color(0xFFFFFDF5),
              uniguajiraGold.withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: uniguajiraGold.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.stars_rounded,
                    color: Color(0xFF9E7000),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'MODO SUSTENTACIÓN ANTE EL JURADO',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: Color(0xFF8A6500),
                        ),
                      ),
                      Text(
                        'Demostración Oficial Evaluativa (1-Clic)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: uniguajiraBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Siembra determinista con 12 estudiantes en Bitmap, 4 sesiones históricas cerradas, actas con firma HMAC-SHA256 y credencial del expositor activa.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: uniguajiraBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: isSeeding
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_circle_filled_rounded),
                label: Text(
                  isSeeding
                      ? 'Sembrando Escenario Oficial...'
                      : 'Cargar / Reiniciar Escenario Oficial (${DemoSeedService.demoCourseCode})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                onPressed: onStartDemo,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de acceso a un rol institucional con sus capacidades listadas.
class _RoleOptionCard extends StatelessWidget {
  const _RoleOptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.capabilities,
    required this.accentColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> capabilities;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: accentColor, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade700,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: capabilities
                    .map((cap) => _CapabilityBadge(label: cap))
                    .toList(growable: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Etiqueta visual para una capacidad técnica de rol.
class _CapabilityBadge extends StatelessWidget {
  const _CapabilityBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF334155),
        ),
      ),
    );
  }
}

/// Modal con el resumen exacto del escenario de sustentación sembrado
/// y los 3 accesos directos para la demostración en vivo.
class _DefenseDemoResultDialog extends StatelessWidget {
  const _DefenseDemoResultDialog({
    required this.result,
    required this.onOpenTeacherCourse,
    required this.onOpenReports,
    required this.onOpenStudentWallet,
  });

  final DemoSeedResult result;
  final VoidCallback onOpenTeacherCourse;
  final VoidCallback onOpenReports;
  final VoidCallback onOpenStudentWallet;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: uniguajiraGold.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.verified_rounded,
              color: Color(0xFF9E7000),
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Escenario de Sustentación Listo',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: uniguajiraBlue,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'El motor determinista preparó con éxito la persistencia SQLite v3 con los siguientes parámetros oficiales:',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 14),
            _DefenseSummaryRow(
              icon: Icons.menu_book_rounded,
              title: 'Asignatura',
              content:
                  '${result.course.name} (${result.course.code} · Grupo ${result.course.groupCode} · Semestre ${result.course.semester})',
            ),
            const SizedBox(height: 10),
            _DefenseSummaryRow(
              icon: Icons.people_alt_rounded,
              title: 'Nómina',
              content:
                  '${result.studentsSeeded} estudiantes matriculados (Bits 00 al 11, incluyendo ${DemoSeedService.primaryStudentCode} y ${DemoSeedService.secondaryStudentCode})',
            ),
            const SizedBox(height: 10),
            _DefenseSummaryRow(
              icon: Icons.history_edu_rounded,
              title: 'Auditoría',
              content:
                  '${result.closedSessionsSeeded} sesiones históricas cerradas y ${result.signedActasCount} actas firmadas con HMAC-SHA256',
            ),
            const SizedBox(height: 10),
            _DefenseSummaryRow(
              icon: Icons.account_balance_wallet_rounded,
              title: 'Billetera Estudiante',
              content:
                  'Credencial Bit 0${result.enrolledBitIndex} (${result.enrolledStudentCode}) auto-enrolada y activa',
            ),
            const SizedBox(height: 18),
            Text(
              'ACCESOS DIRECTOS PARA LA DEMOSTRACIÓN:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: uniguajiraBlue,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.co_present_rounded, size: 20),
              label: const Text(
                'Ir al Curso Docente',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              onPressed: onOpenTeacherCourse,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: uniguajiraBlue,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.table_chart_rounded, size: 20),
              label: const Text(
                'Ir a Reportes y Excel (.xlsx)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              onPressed: onOpenReports,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF007A33),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.badge_rounded, size: 20),
              label: const Text(
                'Ir a Billetera Estudiante',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              onPressed: onOpenStudentWallet,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar Ventana'),
        ),
      ],
    );
  }
}

/// Fila estructurada de resumen dentro del diálogo de sustentación.
class _DefenseSummaryRow extends StatelessWidget {
  const _DefenseSummaryRow({
    required this.icon,
    required this.title,
    required this.content,
  });

  final IconData icon;
  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: uniguajiraBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Modal de diagnóstico de hardware en Android usando `permission_handler`.
class _AndroidHardwareDiagnosticDialog extends StatefulWidget {
  const _AndroidHardwareDiagnosticDialog();

  @override
  State<_AndroidHardwareDiagnosticDialog> createState() =>
      _AndroidHardwareDiagnosticDialogState();
}

class _AndroidHardwareDiagnosticDialogState
    extends State<_AndroidHardwareDiagnosticDialog> {
  bool _isLoading = true;
  Map<Permission, PermissionStatus> _statuses = <Permission, PermissionStatus>{};

  final List<MapEntry<Permission, String>> _permissions =
      const <MapEntry<Permission, String>>[
    MapEntry(Permission.bluetoothScan, 'Bluetooth Scan (Escaneo BLE en aula)'),
    MapEntry(
      Permission.bluetoothAdvertise,
      'Bluetooth Advertise (Emisión Eco y Baliza)',
    ),
    MapEntry(
      Permission.bluetoothConnect,
      'Bluetooth Connect (Conexión de proximidad BLE)',
    ),
    MapEntry(
      Permission.locationWhenInUse,
      'Ubicación en uso (Requisito BLE Android)',
    ),
    MapEntry(Permission.camera, 'Cámara (Escáner QR de enrolamiento)'),
  ];

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() => _isLoading = true);
    final results = <Permission, PermissionStatus>{};
    for (final entry in _permissions) {
      results[entry.key] = await entry.key.status;
    }
    if (mounted) {
      setState(() {
        _statuses = results;
        _isLoading = false;
      });
    }
  }

  Future<void> _requestPermissions() async {
    setState(() => _isLoading = true);
    final list = _permissions.map((e) => e.key).toList();
    await list.request();
    if (mounted) {
      await _checkPermissions();
    }
  }

  Widget _buildStatusChip(PermissionStatus? status) {
    if (status == null) {
      return const SizedBox.shrink();
    }
    if (status.isGranted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'Concedido',
          style: TextStyle(
            color: Color(0xFF15803D),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (status.isPermanentlyDenied) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'Bloqueado',
          style: TextStyle(
            color: Color(0xFFB91C1C),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Denegado',
        style: TextStyle(
          color: Color(0xFFB45309),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
      title: const Row(
        children: <Widget>[
          Icon(Icons.build_circle_rounded, color: uniguajiraBlue, size: 26),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Diagnóstico de Permisos Hardware',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Estado de los canales de hardware necesarios para proximidad BLE y escaneo QR en dispositivos Android:',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 14),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              ..._permissions.map((entry) {
                final status = _statuses[entry.key];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          status?.isGranted ?? false
                              ? Icons.check_circle_rounded
                              : Icons.warning_amber_rounded,
                          color: status?.isGranted ?? false
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFD97706),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildStatusChip(status),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: uniguajiraBlue,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.security_update_good_rounded, size: 18),
                    label: const Text(
                      'Solicitar Permisos',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                    onPressed: _isLoading ? null : _requestPermissions,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Reverificar permisos',
                  icon: const Icon(Icons.refresh_rounded, color: uniguajiraBlue),
                  onPressed: _isLoading ? null : _checkPermissions,
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: uniguajiraBlue,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text(
                'Abrir Ajustes del Sistema',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
              onPressed: () => openAppSettings(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

/// Modal de diagnóstico en entornos no Android (Linux Desktop / Pruebas FFI).
class _DesktopHardwareDiagnosticDialog extends StatelessWidget {
  const _DesktopHardwareDiagnosticDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
      title: const Row(
        children: <Widget>[
          Icon(Icons.desktop_windows_rounded, color: uniguajiraBlue, size: 26),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Diagnóstico de Permisos Hardware',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: const Row(
                children: <Widget>[
                  Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF15803D),
                    size: 22,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Entorno Linux Desktop / Prueba FFI Detectado — Simulación BLE Activa',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF14532D),
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'La aplicación está ejecutándose en un entorno de pruebas o escritorio Linux sin acceso a los servicios nativos de Android:\n\n'
              '• Persistencia SQLite v3: Operativa mediante driver C nativo (sqflite_common_ffi).\n'
              '• Motor Criptográfico: Generación determinista HMAC-SHA256 validada al 100%.\n'
              '• Simulación BLE y Cámara: Los canales dependientes de plataforma se omiten para garantizar estabilidad sin excepciones MissingPluginException.\n\n'
              'En dispositivos móviles Android físicos, este panel valida y solicita en tiempo de ejecución los permisos bluetoothScan, bluetoothAdvertise, bluetoothConnect, locationWhenInUse y camera.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Entendido'),
        ),
      ],
    );
  }
}

/// Fila estructurada de créditos y datos de la ficha técnica.
class _CreditItem extends StatelessWidget {
  const _CreditItem({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}
