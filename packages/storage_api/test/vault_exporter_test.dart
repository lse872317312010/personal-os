import 'dart:convert';

import 'package:personal_os_events/events.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  group('VaultExporter (Wave 17a)', () {
    final fixedTime = DateTime.utc(2026, 1, 1, 0, 0, 0);

    EventEnvelope makeEvent(String id) => EventEnvelope(
          eventId: id,
          eventType: 'test.event',
          eventVersion: 1,
          occurredAt: fixedTime,
          recordedAt: fixedTime,
          actor: const ActorRef(
            actorId: 'user-1',
            actorType: ActorType.user,
            authoritySource: 'local-vault',
          ),
          correlationId: 'corr-1',
          sensitivity: Sensitivity.d2,
          payload: <String, Object?>{'note': 'hello'},
          subjectRefs: <ObjectRef>[ObjectRef('subject-1')],
        );

    test('exportFromSnapshot produces valid envelope with sha256 + HMAC sig',
        () async {
      final exporter = VaultExporter();
      final envelope = await exporter.exportFromSnapshot(
        request: const VaultExportRequest(compositionMode: 'demo'),
        events: <EventEnvelope>[makeEvent('evt-1')],
        now: fixedTime,
      );

      expect(envelope.sha256Hex.length, 64);
      expect(envelope.signatureHex.length, 64);
      expect(envelope.sha256Hex, isNot(equals(envelope.signatureHex)));

      final doc = envelope.toJson();
      expect(doc['schema_version'], 1);
      expect(doc['composition_mode'], 'demo');
      expect(doc['event_count'], 1);
      expect(doc['blob_count'], 0);
      expect(doc['passphrase_challenge'], isNull);
      expect(doc['exported_at'], fixedTime.toIso8601String());

      // Round-trip through JSON
      final decoded =
          jsonDecode(utf8.decode(envelope.bytes)) as Map<String, Object?>;
      expect(decoded['event_count'], 1);
      expect((decoded['events'] as List).length, 1);
    });

    test('byte-deterministic for identical input', () async {
      final exporter = VaultExporter();
      final e1 = await exporter.exportFromSnapshot(
        request: const VaultExportRequest(compositionMode: 'demo'),
        events: <EventEnvelope>[makeEvent('evt-d')],
        now: fixedTime,
      );
      final e2 = await exporter.exportFromSnapshot(
        request: const VaultExportRequest(compositionMode: 'demo'),
        events: <EventEnvelope>[makeEvent('evt-d')],
        now: fixedTime,
      );

      expect(e1.bytes, equals(e2.bytes));
      expect(e1.sha256Hex, equals(e2.sha256Hex));
      expect(e1.signatureHex, equals(e2.signatureHex));
    });

    test('passphrase produces non-null challenge + different signature',
        () async {
      final exporter = VaultExporter();
      final event = makeEvent('evt-pass');

      final noPass = await exporter.exportFromSnapshot(
        request: const VaultExportRequest(compositionMode: 'demo'),
        events: <EventEnvelope>[event],
        now: fixedTime,
      );
      final withPass = await exporter.exportFromSnapshot(
        request: const VaultExportRequest(
            compositionMode: 'demo', passphrase: 'secret123'),
        events: <EventEnvelope>[event],
        now: fixedTime,
      );

      expect(noPass.toJson()['passphrase_challenge'], isNull);
      expect(withPass.toJson()['passphrase_challenge'], isNotNull);
      // Different signing key → different signature
      expect(noPass.signatureHex, isNot(equals(withPass.signatureHex)));
      // Same document body → same sha256
      expect(noPass.sha256Hex, equals(withPass.sha256Hex));
    });

    test('empty event list produces valid envelope', () async {
      final exporter = VaultExporter();
      final envelope = await exporter.exportFromSnapshot(
        request: const VaultExportRequest(compositionMode: 'demo'),
        events: const <EventEnvelope>[],
        now: fixedTime,
      );

      expect(envelope.toJson()['event_count'], 0);
      expect(envelope.sha256Hex.length, 64);
      expect(envelope.signatureHex.length, 64);
    });

    test('different events produce different sha256', () async {
      final exporter = VaultExporter();
      final e1 = await exporter.exportFromSnapshot(
        request: const VaultExportRequest(compositionMode: 'demo'),
        events: <EventEnvelope>[makeEvent('evt-a')],
        now: fixedTime,
      );
      final e2 = await exporter.exportFromSnapshot(
        request: const VaultExportRequest(compositionMode: 'demo'),
        events: <EventEnvelope>[makeEvent('evt-b')],
        now: fixedTime,
      );

      expect(e1.sha256Hex, isNot(equals(e2.sha256Hex)));
    });

    test('different composition mode label produces different sha256',
        () async {
      final exporter = VaultExporter();
      final e1 = await exporter.exportFromSnapshot(
        request: const VaultExportRequest(compositionMode: 'demo'),
        events: <EventEnvelope>[makeEvent('evt-m')],
        now: fixedTime,
      );
      final e2 = await exporter.exportFromSnapshot(
        request: const VaultExportRequest(compositionMode: 'prodEncrypted'),
        events: <EventEnvelope>[makeEvent('evt-m')],
        now: fixedTime,
      );

      expect(e1.sha256Hex, isNot(equals(e2.sha256Hex)));
    });
  });
}
