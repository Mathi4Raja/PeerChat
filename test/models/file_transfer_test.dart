import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerchat_secure/src/models/file_transfer.dart';

void main() {
  group('FileMetadata', () {
    test('toMap and fromMap roundtrip', () {
      final meta = FileMetadata(
        fileId: 'f1',
        name: 'file.bin',
        size: 123,
        type: 'application/bin',
        totalChunks: 3,
        hash: 'abc',
      );
      final rebuilt = FileMetadata.fromMap(meta.toMap());
      expect(rebuilt.fileId, meta.fileId);
      expect(rebuilt.name, meta.name);
      expect(rebuilt.size, meta.size);
      expect(rebuilt.type, meta.type);
      expect(rebuilt.totalChunks, meta.totalChunks);
      expect(rebuilt.hash, meta.hash);
    });

    test('fromMap provides default mime type when missing', () {
      final rebuilt = FileMetadata.fromMap({
        'fileId': 'f1',
        'name': 'x',
        'size': 1,
        'totalChunks': 1,
        'hash': 'h',
      });
      expect(rebuilt.type, 'application/octet-stream');
    });
  });

  group('FileTransferPayload', () {
    test('toBytes and fromBytes roundtrip', () {
      final payload = FileTransferPayload(
        fileId: 'file123',
        typeIndicator: FileTransferPayload.typeChunk,
        data: Uint8List.fromList([4, 5, 6]),
      );
      final decoded = FileTransferPayload.fromBytes(payload.toBytes());
      expect(decoded.fileId, 'file123');
      expect(decoded.typeIndicator, FileTransferPayload.typeChunk);
      expect(decoded.data, Uint8List.fromList([4, 5, 6]));
    });

    test('fromBytes throws for malformed payload', () {
      expect(
        () => FileTransferPayload.fromBytes(Uint8List.fromList([1, 2])),
        throwsException,
      );
      expect(
        () => FileTransferPayload.fromBytes(Uint8List.fromList([5, 1, 2])),
        throwsException,
      );
    });
  });

  group('FileChunk', () {
    test('toBytes and fromBytes roundtrip with data', () {
      final chunk = FileChunk(index: 7, data: Uint8List.fromList([10, 11]));
      final decoded = FileChunk.fromBytes(chunk.toBytes());
      expect(decoded.index, 7);
      expect(decoded.data, Uint8List.fromList([10, 11]));
    });

    test('fromBytes handles empty data and malformed index', () {
      final onlyIndexBytes = Uint8List.fromList([0, 0, 0, 9]);
      final decoded = FileChunk.fromBytes(onlyIndexBytes);
      expect(decoded.index, 9);
      expect(decoded.data, isEmpty);
      expect(
        () => FileChunk.fromBytes(Uint8List.fromList([1, 2, 3])),
        throwsException,
      );
    });
  });
}

