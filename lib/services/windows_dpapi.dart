import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

const int _cryptProtectUiForbidden = 0x1;
const int _cryptProtectLocalMachine = 0x4;
const String _greenVpnDpapiEntropy = 'BlueVPN-Machine-v1';

class WindowsDpapi {
  const WindowsDpapi._();

  static String? protectString(String plain) {
    final input = Uint8List.fromList(utf8.encode(plain));
    try {
      final protected = _transform(
        input,
        protect: true,
        flags: _cryptProtectUiForbidden | _cryptProtectLocalMachine,
      );
      return protected == null ? null : base64Encode(protected);
    } catch (_) {
      return null;
    } finally {
      input.fillRange(0, input.length, 0);
    }
  }

  static String? unprotectString(String encrypted) {
    Uint8List? input;
    Uint8List? plain;
    try {
      input = base64Decode(encrypted.trim());
      plain = _transform(
        input,
        protect: false,
        flags: _cryptProtectUiForbidden,
      );
      return plain == null ? null : utf8.decode(plain);
    } catch (_) {
      return null;
    } finally {
      input?.fillRange(0, input.length, 0);
      plain?.fillRange(0, plain.length, 0);
    }
  }

  static Uint8List? _transform(
    Uint8List input, {
    required bool protect,
    required int flags,
  }) {
    final entropy = Uint8List.fromList(utf8.encode(_greenVpnDpapiEntropy));
    final inputBlob = _allocateBlob(input);
    final entropyBlob = _allocateBlob(entropy);
    final outputBlob = calloc<CRYPT_INTEGER_BLOB>();

    try {
      final success = protect
          ? CryptProtectData(
              inputBlob,
              nullptr.cast<Utf16>(),
              entropyBlob,
              nullptr,
              nullptr.cast<CRYPTPROTECT_PROMPTSTRUCT>(),
              flags,
              outputBlob,
            )
          : CryptUnprotectData(
              inputBlob,
              nullptr.cast<Pointer<Utf16>>(),
              entropyBlob,
              nullptr,
              nullptr.cast<CRYPTPROTECT_PROMPTSTRUCT>(),
              flags,
              outputBlob,
            );
      if (success == 0 || outputBlob.ref.pbData.address == 0) return null;

      final outputLength = outputBlob.ref.cbData;
      return Uint8List.fromList(
        outputBlob.ref.pbData.asTypedList(outputLength),
      );
    } finally {
      entropy.fillRange(0, entropy.length, 0);
      _freeInputBlob(inputBlob);
      _freeInputBlob(entropyBlob);
      if (outputBlob.ref.pbData.address != 0) {
        final output = outputBlob.ref.pbData.asTypedList(outputBlob.ref.cbData);
        output.fillRange(0, output.length, 0);
        LocalFree(outputBlob.ref.pbData.cast());
      }
      calloc.free(outputBlob);
    }
  }

  static Pointer<CRYPT_INTEGER_BLOB> _allocateBlob(Uint8List bytes) {
    final blob = calloc<CRYPT_INTEGER_BLOB>();
    final data = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    if (bytes.isNotEmpty) {
      data.asTypedList(bytes.length).setAll(0, bytes);
    }
    blob.ref
      ..cbData = bytes.length
      ..pbData = data;
    return blob;
  }

  static void _freeInputBlob(Pointer<CRYPT_INTEGER_BLOB> blob) {
    if (blob.ref.pbData.address != 0) {
      final data = blob.ref.pbData.asTypedList(blob.ref.cbData);
      data.fillRange(0, data.length, 0);
      calloc.free(blob.ref.pbData);
    }
    calloc.free(blob);
  }
}
