import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import '../../data/services/attendance_session_controller.dart';
import '../../theme/theme.dart';

/// Diálogo modal con el Acta Criptográfica de Sesión Firmada (HMAC-SHA256).
///
/// Permite visualizar el resumen oficial, el mapa de bits consolidado,
/// la firma criptográfica inmutable, la lista detallada de estudiantes
/// y copiar el JSON completo al portapapeles para auditoría externa.
class SignedActaDialog extends StatelessWidget {
  const SignedActaDialog({
    super.key,
    required this.acta,
    this.courseSecretHex,
  });

  /// Acta firmada que se va a visualizar.
  final SignedSessionActa acta;

  /// Clave secreta opcional para verificar la firma HMAC in situ.
  final String? courseSecretHex;

  /// Muestra el modal con el acta firmada.
  static Future<void> show(
    BuildContext context, {
    required SignedSessionActa acta,
    String? courseSecretHex,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => SignedActaDialog(
        acta: acta,
        courseSecretHex: courseSecretHex,
      ),
    );
  }

  /// Parsea un JSON de acta previamente guardado en SQLite y muestra el modal.
  static Future<void> showFromJson(
    BuildContext context, {
    required String actaJson,
    String? courseSecretHex,
  }) {
    final Map<String, dynamic> map =
        jsonDecode(actaJson) as Map<String, dynamic>;
    final List<dynamic> rawRecords =
        (map['records'] as List<dynamic>?) ?? <dynamic>[];

    final records = rawRecords.map((dynamic item) {
      final r = item as Map<String, dynamic>;
      return SessionActaRecord(
        bitIndex: r['bitIndex'] as int,
        studentCode: r['studentCode'] as String,
        fullName: r['fullName'] as String,
        status: r['status'] as String,
        method: r['method'] as String?,
        verifyCode: r['verifyCode'] as String?,
        rssi: (r['rssi'] as num?)?.toInt(),
      );
    }).toList(growable: false);

    final parsedActa = SignedSessionActa(
      sessionId: map['sessionId'] as String,
      courseId: map['courseId'] as String,
      courseCode: map['courseCode'] as String,
      courseName: map['courseName'] as String,
      sessionPin: map['sessionPin'] as String,
      startedAtIso: map['startedAtIso'] as String,
      closedAtIso: map['closedAtIso'] as String,
      totalEnrolled: map['totalEnrolled'] as int,
      presentBleCount: map['presentBleCount'] as int,
      presentManualCount: map['presentManualCount'] as int,
      absentCount: map['absentCount'] as int,
      bitmapHex: map['bitmapHex'] as String,
      records: records,
      actaHmacSignature: map['actaHmacSignature'] as String? ?? '',
    );

    return show(
      context,
      acta: parsedActa,
      courseSecretHex: courseSecretHex,
    );
  }

  void _copyToClipboard(BuildContext context) {
    final colors = AppColors.of(context);
    final prettyJson = const JsonEncoder.withIndent('  ').convert(acta.toJson());
    Clipboard.setData(ClipboardData(text: prettyJson));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Acta criptográfica copiada al portapapeles en formato JSON.'),
        backgroundColor: colors.primary,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    final totalPresent = acta.presentBleCount + acta.presentManualCount;
    final double attendancePercent = acta.totalEnrolled == 0
        ? 0.0
        : (totalPresent / acta.totalEnrolled) * 100.0;

    final isSignatureValid = courseSecretHex != null && courseSecretHex!.isNotEmpty
        ? acta.verifySignature(courseSecretHex!)
        : null;

    return Dialog(
      shape: radii.dialogShape(),
      insetPadding: spacing.symmetric(horizontal: spacing.md, vertical: spacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 720),
        child: Column(
          children: <Widget>[
            // Cabecera institucional del Acta
            Container(
              padding: spacing.insetsCard,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: radii.borderTopXl,
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    padding: spacing.insetsXs,
                    decoration: BoxDecoration(
                      color: colors.onPrimary.withValues(alpha: 0.15),
                      borderRadius: radii.borderMd,
                    ),
                    child: Icon(
                      Icons.verified_user_rounded,
                      color: colors.onPrimary,
                      size: 28,
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Acta Criptográfica de Sesión',
                          style: TextStyle(
                            color: colors.onPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: spacing.xxs / 2),
                        Text(
                          '${acta.courseName} (${acta.courseCode})',
                          style: TextStyle(
                            color: colors.onPrimary.withValues(alpha: 0.85),
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: spacing.symmetric(
                      horizontal: spacing.xs,
                      vertical: spacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: colors.onPrimary.withValues(alpha: 0.2),
                      borderRadius: radii.borderSm,
                    ),
                    child: Text(
                      'PIN: ${acta.sessionPin}',
                      style: TextStyle(
                        color: colors.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Cuerpo del Acta
            Expanded(
              child: ListView(
                padding: spacing.insetsCard,
                children: <Widget>[
                  // Resumen de Métricas
                  _buildMetricsRow(context, totalPresent, attendancePercent),
                  SizedBox(height: spacing.md),

                  // Caja de Seguridad y Firma Criptográfica
                  _buildCryptoCard(context, isSignatureValid),
                  SizedBox(height: spacing.md),

                  // Título de la lista de asistencia
                  Row(
                    children: <Widget>[
                      Icon(Icons.people_alt_outlined, size: 20, color: colors.onSurface),
                      SizedBox(width: spacing.xs),
                      Text(
                        'Roster Oficial de la Sesión (${acta.records.length})',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.onSurface,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: spacing.xs),

                  // Lista de estudiantes del acta
                  ...acta.records.map((SessionActaRecord record) {
                    return _buildStudentRecordTile(context, record);
                  }),
                ],
              ),
            ),

            // Barra inferior con acciones
            Container(
              padding: spacing.insetsCard,
              decoration: BoxDecoration(
                color: colors.surfaceContainer,
                borderRadius: BorderRadius.vertical(bottom: radii.radiusXl),
                border: Border(
                  top: BorderSide(
                    color: colors.outlineVariant,
                  ),
                ),
              ),
              child: Row(
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () => _copyToClipboard(context),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar JSON'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      padding: spacing.symmetric(
                        horizontal: spacing.lg,
                        vertical: spacing.sm,
                      ),
                      shape: radii.buttonShape(),
                    ),
                    child: const Text('Aceptar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsRow(
    BuildContext context,
    int totalPresent,
    double attendancePercent,
  ) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    return Container(
      padding: spacing.insetsSm,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: radii.borderMd,
        border: Border.all(
          color: colors.outlineVariant,
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _buildMetricItem(
                context: context,
                label: 'Presentes BLE',
                value: '${acta.presentBleCount}',
                color: colors.statusNormal,
                icon: Icons.bluetooth_connected,
              ),
              _buildMetricItem(
                context: context,
                label: 'Manual',
                value: '${acta.presentManualCount}',
                color: colors.manualAccent,
                icon: Icons.touch_app,
              ),
              _buildMetricItem(
                context: context,
                label: 'Ausentes',
                value: '${acta.absentCount}',
                color: colors.statusPerdida,
                icon: Icons.person_off,
              ),
              _buildMetricItem(
                context: context,
                label: 'Asistencia',
                value: '${attendancePercent.toStringAsFixed(0)}%',
                color: colors.primary,
                icon: Icons.pie_chart,
              ),
            ],
          ),
          Divider(height: spacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                'Total Matriculados: ${acta.totalEnrolled}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.onSurface,
                ),
              ),
              Text(
                'Presentes: $totalPresent / ${acta.totalEnrolled}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: totalPresent > 0 ? colors.statusNormal : colors.onSurfaceMuted,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem({
    required BuildContext context,
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);

    return Column(
      children: <Widget>[
        Icon(icon, color: color, size: 20),
        SizedBox(height: spacing.xxs),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colors.onSurfaceMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildCryptoCard(BuildContext context, bool? isSignatureValid) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    return Container(
      padding: spacing.insetsSm,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: radii.borderMd,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.lock_outline,
                size: 18,
                color: colors.primary,
              ),
              SizedBox(width: spacing.xxs + 2),
              Text(
                'Sello Digital y Firma Inmutable',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: colors.onSurface,
                ),
              ),
              const Spacer(),
              if (isSignatureValid != null)
                Container(
                  padding: spacing.symmetric(
                    horizontal: spacing.xxs + 2,
                    vertical: spacing.xxs / 2,
                  ),
                  decoration: BoxDecoration(
                    color: isSignatureValid
                        ? colors.statusNormalContainer
                        : colors.statusPerdidaContainer,
                    borderRadius: radii.borderXs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        isSignatureValid ? Icons.check_circle : Icons.error,
                        size: 12,
                        color: isSignatureValid
                            ? colors.onStatusNormalContainer
                            : colors.onStatusPerdidaContainer,
                      ),
                      SizedBox(width: spacing.xxs),
                      Text(
                        isSignatureValid ? 'VÁLIDA' : 'INVÁLIDA',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isSignatureValid
                              ? colors.onStatusNormalContainer
                              : colors.onStatusPerdidaContainer,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(height: spacing.xs),
          Row(
            children: <Widget>[
              Text(
                'Bitmap Final: ',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: colors.onSurfaceMuted,
                ),
              ),
              Expanded(
                child: Text(
                  '0x${acta.bitmapHex}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    letterSpacing: 0.5,
                    color: colors.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.xxs),
          Text(
            'Firma HMAC-SHA256:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: colors.onSurfaceMuted,
            ),
          ),
          Container(
            width: double.infinity,
            margin: spacing.only(top: spacing.xxs / 2),
            padding: spacing.all(spacing.xxs + 2),
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: radii.borderXs,
              border: Border.all(color: colors.outlineVariant),
            ),
            child: SelectableText(
              acta.actaHmacSignature,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentRecordTile(
    BuildContext context,
    SessionActaRecord record,
  ) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    final isPresent = record.isPresent;
    final isBle = record.method == AppConstants.attendanceMethodBleHmac;
    final bitStr = record.bitIndex.toString().padLeft(2, '0');

    return Card(
      margin: spacing.only(bottom: spacing.xxs + 2),
      elevation: 0,
      shape: radii.cardShape(
        side: BorderSide(
          color: isPresent
              ? colors.statusNormal.withValues(alpha: 0.4)
              : colors.outlineVariant,
        ),
      ),
      color: isPresent ? colors.statusNormalContainer.withValues(alpha: 0.4) : null,
      child: Padding(
        padding: spacing.symmetric(horizontal: spacing.sm, vertical: spacing.xs),
        child: Row(
          children: <Widget>[
            Container(
              padding: spacing.symmetric(horizontal: spacing.xxs + 2, vertical: spacing.xxs / 2),
              decoration: BoxDecoration(
                color: isPresent
                    ? colors.statusNormal
                    : colors.outline,
                borderRadius: radii.borderXs,
              ),
              child: Text(
                '#$bitStr',
                style: TextStyle(
                  color: isPresent ? colors.onStatusNormal : colors.surface,
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(width: spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    record.fullName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: colors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Cód: ${record.studentCode}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (isPresent)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Container(
                    padding: spacing.symmetric(
                      horizontal: spacing.xxs + 2,
                      vertical: spacing.xxs / 2,
                    ),
                    decoration: BoxDecoration(
                      color: isBle
                          ? colors.bleAccentContainer
                          : colors.manualAccentContainer,
                      borderRadius: radii.borderXs,
                    ),
                    child: Text(
                      isBle ? 'BLE' : 'MANUAL',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isBle
                            ? colors.onBleAccentContainer
                            : colors.onManualAccentContainer,
                      ),
                    ),
                  ),
                  if (record.verifyCode != null)
                    Padding(
                      padding: spacing.only(top: spacing.xxs / 2),
                      child: Text(
                        record.verifyCode!,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurfaceMuted,
                        ),
                      ),
                    ),
                ],
              )
            else
              Container(
                padding: spacing.symmetric(
                  horizontal: spacing.xxs + 2,
                  vertical: spacing.xxs / 2,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: radii.borderXs,
                ),
                child: Text(
                  'AUSENTE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: colors.onSurfaceMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
