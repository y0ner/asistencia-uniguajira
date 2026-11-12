import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/services/attendance_session_controller.dart';
import '../../ui/ui.dart';

/// Diálogo modal con el acta firmada de la sesión.
///
/// Muestra las métricas de llegada (por Bluetooth, a mano y ausentes),
/// la lista de estudiantes con su estado de asistencia y los detalles
/// de la firma para verificación.
class SignedActaDialog extends StatelessWidget {
  const SignedActaDialog({
    super.key,
    required this.acta,
    this.courseSecretHex,
  });

  /// Acta firmada que se va a visualizar.
  final SignedSessionActa acta;

  /// Clave secreta opcional para verificar la firma de la sesión.
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

  /// Parsea un texto canónico previamente guardado y muestra el modal.
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

  @override
  Widget build(BuildContext context) {
    final colors = UiColors.of(context);
    final closedDate = DateTime.tryParse(acta.closedAtIso) ??
        DateTime.tryParse(acta.startedAtIso) ??
        DateTime.now();
    final formattedDate =
        '${UiFormat.longDate(closedDate)} · ${UiFormat.time(closedDate)}';

    final isSignatureValid =
        courseSecretHex != null && courseSecretHex!.isNotEmpty
            ? acta.verifySignature(courseSecretHex!)
            : null;

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UiRadius.xl),
        side: BorderSide(color: colors.line),
      ),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: UiSpace.md,
        vertical: UiSpace.lg,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                UiSpace.lg,
                UiSpace.lg,
                UiSpace.lg,
                UiSpace.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sesión firmada',
                    style: UiText.h2.copyWith(color: colors.ink),
                  ),
                  const SizedBox(height: UiSpace.xs),
                  Text(
                    formattedDate,
                    style: UiText.caption.copyWith(color: colors.muted),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: colors.line),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(UiSpace.lg),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: UiStatTile(
                          value: '${acta.presentBleCount}',
                          label: 'llegaron',
                        ),
                      ),
                      const SizedBox(width: UiSpace.sm),
                      Expanded(
                        child: UiStatTile(
                          value: '${acta.presentManualCount}',
                          label: 'a mano',
                        ),
                      ),
                      const SizedBox(width: UiSpace.sm),
                      Expanded(
                        child: UiStatTile(
                          value: '${acta.absentCount}',
                          label: 'faltaron',
                          tone: acta.absentCount > 0 ? UiTone.absent : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: UiSpace.lg),
                  if (isSignatureValid == false) ...[
                    const UiBanner(
                      tone: UiBannerTone.error,
                      message:
                          'La firma de esta sesión no coincide. Puede haber sido modificada.',
                    ),
                    const SizedBox(height: UiSpace.md),
                  ],
                  Material(
                    color: colors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(UiRadius.lg),
                      side: BorderSide(color: colors.line),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < acta.records.length; i++) ...[
                          _buildStudentRecord(context, acta.records[i]),
                          if (i < acta.records.length - 1)
                            Divider(height: 1, thickness: 1, color: colors.line),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: UiSpace.lg),
                  Material(
                    color: colors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(UiRadius.lg),
                      side: BorderSide(color: colors.line),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        dividerColor: Colors.transparent,
                      ),
                      child: ExpansionTile(
                        initiallyExpanded: false,
                        title: Text(
                          'Detalles de la firma',
                          style: UiText.bodyStrong.copyWith(color: colors.ink),
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          UiSpace.md,
                          0,
                          UiSpace.md,
                          UiSpace.md,
                        ),
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(UiSpace.sm),
                            decoration: BoxDecoration(
                              color: colors.background,
                              borderRadius: BorderRadius.circular(UiRadius.sm),
                              border: Border.all(color: colors.line),
                            ),
                            child: SelectableText(
                              acta.actaHmacSignature,
                              style: UiText.caption.copyWith(
                                color: colors.muted,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          const SizedBox(height: UiSpace.sm),
                          Align(
                            alignment: Alignment.centerRight,
                            child: UiButton(
                              label: 'Copiar',
                              icon: Icons.copy_rounded,
                              variant: UiButtonVariant.tonal,
                              compact: true,
                              expand: false,
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: acta.actaHmacSignature),
                                );
                                showUiSnack(
                                  context,
                                  'Firma copiada al portapapeles.',
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: colors.line),
            Padding(
              padding: const EdgeInsets.all(UiSpace.md),
              child: UiButton(
                label: 'Cerrar',
                variant: UiButtonVariant.primary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentRecord(BuildContext context, SessionActaRecord record) {
    final statusStr = record.status.toUpperCase();
    final methodStr = record.method?.toUpperCase();

    final UiStatus status;
    if (statusStr == 'ABSENT') {
      status = UiStatus.absent;
    } else if (methodStr == 'MANUAL_INVERTED' || methodStr == 'MANUAL') {
      status = UiStatus.manual;
    } else {
      status = UiStatus.present;
    }

    final avatarTone = switch (status) {
      UiStatus.present => UiTone.tint,
      UiStatus.manual => UiTone.manual,
      UiStatus.absent => UiTone.absent,
      UiStatus.pending => UiTone.neutral,
    };

    return UiPersonRow(
      name: record.fullName,
      subtitle: record.studentCode,
      avatarTone: avatarTone,
      trailing: UiStatusChip(status: status),
    );
  }
}
