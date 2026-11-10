import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'core/constants/app_constants.dart';
import 'data/services/demo_seed_service.dart';
import 'features/student/student_courses_screen.dart';
import 'features/teacher/course_detail_screen.dart';
import 'features/teacher/course_reports_screen.dart';
import 'features/teacher/courses_dashboard_screen.dart';
import 'theme/theme.dart';

void main() {
  runApp(const AsistenciaUniguajiraApp());
}

/// Raíz de la aplicación institucional de Asistencia Uniguajira.
class AsistenciaUniguajiraApp extends StatelessWidget {
  const AsistenciaUniguajiraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildLightTheme(),
      darkTheme: AppTheme.buildDarkTheme(),
      themeMode: ThemeMode.system,
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
      final colors = AppColors.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al sembrar escenario: $error'),
          backgroundColor: colors.statusPerdida,
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
    final colors = AppColors.of(context);
    final radii = AppRadii.of(context);
    final spacing = AppSpacing.of(context);

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: radii.dialogShape(),
        title: Row(
          children: <Widget>[
            Icon(Icons.school_rounded, color: colors.primary, size: 28),
            SizedBox(width: spacing.sm),
            Expanded(
              child: Text(
                'Acerca del Proyecto de Grado',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: colors.primary,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Universidad de La Guajira · Facultad de Ingeniería · Programa de Ingeniería de Sistemas.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: colors.primary,
                ),
              ),
              SizedBox(height: spacing.md),
              const _CreditItem(
                label: 'Autores',
                value:
                    'Yoner De Jesus Isaza Vides (0182120016) y Álvaro Luis Garrido Medina (0182110072).',
              ),
              SizedBox(height: spacing.xs),
              const _CreditItem(
                label: 'Asignatura',
                value: 'Proyectos II',
              ),
              SizedBox(height: spacing.xs),
              const _CreditItem(
                label: 'Docente',
                value: 'Miguel Humberto Romero Acuña',
              ),
              SizedBox(height: spacing.xs),
              const _CreditItem(
                label: 'Directora',
                value: 'Lisseth Paola Castañeda Vega',
              ),
              Divider(height: spacing.lg),
              Text(
                'Resumen de Arquitectura',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: colors.onSurface,
                ),
              ),
              SizedBox(height: spacing.xxs),
              Text(
                'Persistencia Offline-First SQLite v3, BLE Legacy Service UUID de 16 bytes (128 bits) sin GATT, rotación temporal HMAC-SHA256 cada 30s (±1 tick), Eco Docente con Mapa de Bits de 8 bytes (64 posiciones), Lista Invertida de excepción y exportación Excel .xlsx de 4 hojas con sincronización institucional ${AppConstants.institutionalDomain}.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: colors.onSurfaceMuted,
                ),
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
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

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
            padding: spacing.symmetric(horizontal: spacing.md, vertical: spacing.lg),
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
                      padding: spacing.insetsMd,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.secondary, width: 2.5),
                      ),
                      child: Icon(
                        Icons.school_rounded,
                        size: 54,
                        color: colors.primary,
                      ),
                    ),
                  ),
                  SizedBox(height: spacing.sm),
                  Text(
                    'Asistencia Multimodal Uniguajira',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.primary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: spacing.xxs),
                  Text(
                    'Proximidad Criptográfica BLE (Bitmap 8B) + Lista Invertida Offline-First',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: spacing.sm),
                  Center(
                    child: Container(
                      padding: spacing.symmetric(
                        horizontal: spacing.sm,
                        vertical: spacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.06),
                        borderRadius: radii.borderPill,
                        border: Border.all(
                          color: colors.primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.verified_user_rounded,
                            size: 16,
                            color: colors.primary,
                          ),
                          SizedBox(width: spacing.xs),
                          Flexible(
                            child: Text(
                              'Costo de Servidor \$0 · Soberanía de Datos ${AppConstants.institutionalDomain}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: colors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: spacing.lg),

                  // -----------------------------------------------------------
                  // 2. Panel Destacado: Modo Sustentación frente al Jurado
                  // -----------------------------------------------------------
                  _DefenseDemoCard(
                    isSeeding: _isSeeding,
                    onStartDemo: _isSeeding ? null : _seedDemoScenario,
                  ),
                  SizedBox(height: spacing.lg),

                  // -----------------------------------------------------------
                  // 3. Tarjetas Principales de Rol con Navegación Directa
                  // -----------------------------------------------------------
                  Text(
                    'ROLES OPERATIVOS DEL SISTEMA',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                  SizedBox(height: spacing.xs),
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
                    accentColor: colors.primary,
                    onTap: () => _navigateTo(const CoursesDashboardScreen()),
                  ),
                  SizedBox(height: spacing.sm),
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
                    accentColor: colors.statusNormal,
                    onTap: () => _navigateTo(const StudentCoursesScreen()),
                  ),
                  SizedBox(height: spacing.lg),

                  // -----------------------------------------------------------
                  // 4. Modal de Diagnóstico de Permisos Hardware
                  // -----------------------------------------------------------
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: spacing.symmetric(
                        horizontal: spacing.md,
                        vertical: spacing.sm,
                      ),
                      shape: radii.buttonShape(),
                    ),
                    icon: Icon(
                      Icons.settings_input_antenna_rounded,
                      color: colors.primary,
                    ),
                    label: Text(
                      'Diagnóstico de Permisos Hardware',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colors.primary,
                      ),
                    ),
                    onPressed: _showHardwareDiagnosticModal,
                  ),
                  SizedBox(height: spacing.xs),

                  // -----------------------------------------------------------
                  // 5. Botón Ficha Técnica y Créditos Oficiales
                  // -----------------------------------------------------------
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: colors.onSurfaceMuted,
                      padding: spacing.symmetric(vertical: spacing.xs),
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
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    return Card(
      elevation: 2,
      shape: radii.cardShape(side: BorderSide(color: colors.secondary, width: 2)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radii.borderLg,
          gradient: LinearGradient(
            colors: <Color>[
              colors.surfaceContainer,
              colors.secondaryContainer.withValues(alpha: 0.15),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: spacing.insetsCard,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: spacing.insetsXs,
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer.withValues(alpha: 0.4),
                    borderRadius: radii.borderSm,
                  ),
                  child: Icon(
                    Icons.stars_rounded,
                    color: colors.onSecondaryContainer,
                    size: 24,
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'MODO SUSTENTACIÓN ANTE EL JURADO',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: colors.onSecondaryContainer,
                        ),
                      ),
                      Text(
                        'Demostración Oficial Evaluativa (1-Clic)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.sm),
            Text(
              'Siembra determinista con 12 estudiantes en Bitmap, 4 sesiones históricas cerradas, actas con firma HMAC-SHA256 y credencial del expositor activa.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: colors.onSurfaceMuted,
              ),
            ),
            SizedBox(height: spacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  padding: spacing.symmetric(
                    horizontal: spacing.md,
                    vertical: spacing.sm,
                  ),
                  shape: radii.buttonShape(),
                ),
                icon: isSeeding
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onPrimary,
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
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    return Card(
      elevation: 1,
      shape: radii.cardShape(side: BorderSide(color: colors.outlineVariant)),
      child: InkWell(
        onTap: onTap,
        borderRadius: radii.borderLg,
        child: Padding(
          padding: spacing.insetsCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    padding: spacing.insetsSm,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: radii.borderMd,
                    ),
                    child: Icon(icon, color: accentColor, size: 28),
                  ),
                  SizedBox(width: spacing.sm),
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
                        SizedBox(height: spacing.xxs),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colors.onSurfaceMuted,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: spacing.xs),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: colors.outline,
                  ),
                ],
              ),
              SizedBox(height: spacing.sm),
              Wrap(
                spacing: spacing.xs,
                runSpacing: spacing.xs,
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
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    return Container(
      padding: spacing.symmetric(horizontal: spacing.xs, vertical: spacing.xxs),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: radii.borderXs,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
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
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    return AlertDialog(
      shape: radii.dialogShape(),
      titlePadding: spacing.only(
        left: spacing.lg,
        top: spacing.lg,
        right: spacing.lg,
        bottom: spacing.xs,
      ),
      contentPadding: spacing.symmetric(
        horizontal: spacing.lg,
        vertical: spacing.sm,
      ),
      actionsPadding: spacing.only(
        left: spacing.lg,
        top: spacing.xs,
        right: spacing.lg,
        bottom: spacing.md,
      ),
      title: Row(
        children: <Widget>[
          Container(
            padding: spacing.insetsXs,
            decoration: BoxDecoration(
              color: colors.secondaryContainer.withValues(alpha: 0.3),
              borderRadius: radii.borderSm,
            ),
            child: Icon(
              Icons.verified_rounded,
              color: colors.onSecondaryContainer,
              size: 26,
            ),
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Text(
              'Escenario de Sustentación Listo',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: colors.primary,
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
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceMuted),
            ),
            SizedBox(height: spacing.sm),
            _DefenseSummaryRow(
              icon: Icons.menu_book_rounded,
              title: 'Asignatura',
              content:
                  '${result.course.name} (${result.course.code} · Grupo ${result.course.groupCode} · Semestre ${result.course.semester})',
            ),
            SizedBox(height: spacing.xs),
            _DefenseSummaryRow(
              icon: Icons.people_alt_rounded,
              title: 'Nómina',
              content:
                  '${result.studentsSeeded} estudiantes matriculados (Bits 00 al 11, incluyendo ${DemoSeedService.primaryStudentCode} y ${DemoSeedService.secondaryStudentCode})',
            ),
            SizedBox(height: spacing.xs),
            _DefenseSummaryRow(
              icon: Icons.history_edu_rounded,
              title: 'Auditoría',
              content:
                  '${result.closedSessionsSeeded} sesiones históricas cerradas y ${result.signedActasCount} actas firmadas con HMAC-SHA256',
            ),
            SizedBox(height: spacing.xs),
            _DefenseSummaryRow(
              icon: Icons.account_balance_wallet_rounded,
              title: 'Billetera Estudiante',
              content:
                  'Credencial Bit 0${result.enrolledBitIndex} (${result.enrolledStudentCode}) auto-enrolada y activa',
            ),
            SizedBox(height: spacing.md),
            Text(
              'ACCESOS DIRECTOS PARA LA DEMOSTRACIÓN:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: colors.onSurfaceMuted,
              ),
            ),
            SizedBox(height: spacing.xs),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                alignment: Alignment.centerLeft,
                padding: spacing.symmetric(
                  horizontal: spacing.sm,
                  vertical: spacing.xs,
                ),
                shape: radii.buttonShape(),
              ),
              icon: const Icon(Icons.co_present_rounded, size: 20),
              label: const Text(
                'Ir al Curso Docente',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              onPressed: onOpenTeacherCourse,
            ),
            SizedBox(height: spacing.xs),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.primary,
                alignment: Alignment.centerLeft,
                padding: spacing.symmetric(
                  horizontal: spacing.sm,
                  vertical: spacing.xs,
                ),
                shape: radii.buttonShape(),
              ),
              icon: const Icon(Icons.table_chart_rounded, size: 20),
              label: const Text(
                'Ir a Reportes y Excel (.xlsx)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              onPressed: onOpenReports,
            ),
            SizedBox(height: spacing.xs),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.statusNormal,
                side: BorderSide(color: colors.statusNormal, width: colors.hairlineWidth),
                alignment: Alignment.centerLeft,
                padding: spacing.symmetric(
                  horizontal: spacing.sm,
                  vertical: spacing.xs,
                ),
                shape: radii.buttonShape(),
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
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    return Container(
      padding: spacing.insetsSm,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: radii.borderSm,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: colors.primary),
          SizedBox(width: spacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurfaceMuted,
                  ),
                ),
                SizedBox(height: spacing.xxs),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
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

  Widget _buildStatusChip(BuildContext context, PermissionStatus? status) {
    if (status == null) {
      return const SizedBox.shrink();
    }
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    if (status.isGranted) {
      return Container(
        padding: spacing.symmetric(horizontal: spacing.xs, vertical: spacing.xxs),
        decoration: BoxDecoration(
          color: colors.statusNormalContainer,
          borderRadius: radii.borderXs,
        ),
        child: Text(
          'Concedido',
          style: TextStyle(
            color: colors.onStatusNormalContainer,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (status.isPermanentlyDenied) {
      return Container(
        padding: spacing.symmetric(horizontal: spacing.xs, vertical: spacing.xxs),
        decoration: BoxDecoration(
          color: colors.statusPerdidaContainer,
          borderRadius: radii.borderXs,
        ),
        child: Text(
          'Bloqueado',
          style: TextStyle(
            color: colors.onStatusPerdidaContainer,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return Container(
      padding: spacing.symmetric(horizontal: spacing.xs, vertical: spacing.xxs),
      decoration: BoxDecoration(
        color: colors.statusAlertaContainer,
        borderRadius: radii.borderXs,
      ),
      child: Text(
        'Denegado',
        style: TextStyle(
          color: colors.onStatusAlertaContainer,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    return AlertDialog(
      shape: radii.dialogShape(),
      title: Row(
        children: <Widget>[
          Icon(Icons.build_circle_rounded, color: colors.primary, size: 26),
          SizedBox(width: spacing.xs),
          const Expanded(
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
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceMuted),
            ),
            SizedBox(height: spacing.sm),
            if (_isLoading)
              Center(
                child: Padding(
                  padding: spacing.insetsLg,
                  child: const CircularProgressIndicator(),
                ),
              )
            else
              ..._permissions.map((entry) {
                final status = _statuses[entry.key];
                return Padding(
                  padding: spacing.only(bottom: spacing.xs),
                  child: Container(
                    padding: spacing.insetsSm,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: radii.borderSm,
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          status?.isGranted ?? false
                              ? Icons.check_circle_rounded
                              : Icons.warning_amber_rounded,
                          color: status?.isGranted ?? false
                              ? colors.statusNormal
                              : colors.statusAlerta,
                          size: 20,
                        ),
                        SizedBox(width: spacing.xs),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(width: spacing.xxs),
                        _buildStatusChip(context, status),
                      ],
                    ),
                  ),
                );
              }),
            SizedBox(height: spacing.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      padding: spacing.symmetric(vertical: spacing.sm),
                      shape: radii.buttonShape(),
                    ),
                    icon: const Icon(Icons.security_update_good_rounded, size: 18),
                    label: const Text(
                      'Solicitar Permisos',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                    onPressed: _isLoading ? null : _requestPermissions,
                  ),
                ),
                SizedBox(width: spacing.xs),
                IconButton(
                  tooltip: 'Reverificar permisos',
                  icon: Icon(Icons.refresh_rounded, color: colors.primary),
                  onPressed: _isLoading ? null : _checkPermissions,
                ),
              ],
            ),
            SizedBox(height: spacing.xs),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.primary,
                padding: spacing.symmetric(vertical: spacing.sm),
                shape: radii.buttonShape(),
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
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    return AlertDialog(
      shape: radii.dialogShape(),
      title: Row(
        children: <Widget>[
          Icon(Icons.desktop_windows_rounded, color: colors.primary, size: 26),
          SizedBox(width: spacing.xs),
          const Expanded(
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
              padding: spacing.insetsSm,
              decoration: BoxDecoration(
                color: colors.statusNormalContainer,
                borderRadius: radii.borderSm,
                border: Border.all(color: colors.statusNormal.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.check_circle_rounded,
                    color: colors.statusNormal,
                    size: 22,
                  ),
                  SizedBox(width: spacing.xs),
                  Expanded(
                    child: Text(
                      'Entorno Linux Desktop / Prueba FFI Detectado — Simulación BLE Activa',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: colors.onStatusNormalContainer,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.sm),
            Text(
              'La aplicación está ejecutándose en un entorno de pruebas o escritorio Linux sin acceso a los servicios nativos de Android:\n\n'
              '• Persistencia SQLite v3: Operativa mediante driver C nativo (sqflite_common_ffi).\n'
              '• Motor Criptográfico: Generación determinista HMAC-SHA256 validada al 100%.\n'
              '• Simulación BLE y Cámara: Los canales dependientes de plataforma se omiten para garantizar estabilidad sin excepciones MissingPluginException.\n\n'
              'En dispositivos móviles Android físicos, este panel valida y solicita en tiempo de ejecución los permisos bluetoothScan, bluetoothAdvertise, bluetoothConnect, locationWhenInUse y camera.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: colors.onSurfaceMuted,
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
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: colors.onSurfaceMuted,
          ),
        ),
        SizedBox(height: spacing.xxs),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
        ),
      ],
    );
  }
}
