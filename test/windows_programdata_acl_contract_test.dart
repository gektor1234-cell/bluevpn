import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

String _functionBody(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0));
  expect(endIndex, greaterThan(startIndex));
  return source.substring(startIndex, endIndex);
}

void main() {
  test(
    'Windows installers apply inheritable ACLs only to ProgramData roots',
    () {
      final production = _read('scripts/windows/build_installer.ps1');
      final beta = _read('scripts/windows/install_paid_beta_side_by_side.ps1');

      final productionAcl = _functionBody(
        production,
        'function Ensure-GreenVpnProgramDataAcl',
        'function Ensure-GreenVpnServiceToken',
      );
      final betaAcl = _functionBody(
        beta,
        'function Ensure-BetaProgramData',
        'function Install-BetaService',
      );

      for (final body in [productionAcl, betaAcl]) {
        expect(body, contains('/reset /T /C'));
        expect(body, isNot(contains("'*S-1-5-32-544:(OI)(CI)F' /T /C")));
        expect(
          body,
          isNot(
            contains("/remove:g '*S-1-1-0' '*S-1-5-11' '*S-1-5-32-545' /T /C"),
          ),
        );
      }
    },
  );

  test('Windows auth log repairs an inaccessible file and retries once', () {
    final main = _read('lib/main.dart');

    expect(main, contains('repairSharedStateFileAcl'));
    expect(main, contains('on FileSystemException'));
    expect(main, contains('if (!existedBeforeWrite && !repairedExistingAcl)'));
    expect(main, contains('await _appendGreenVpnAuthLogLineNow(line);'));
    expect(main, contains('await appendGreenVpnAuthLogLine(text);'));
  });

  test('installer package audit rejects the old recursive ACL contract', () {
    final audit = _read('scripts/windows/test_public_installer_package.ps1');

    expect(audit, contains("(Join-Path `\$root '*') /reset /T /C"));
    expect(audit, contains("(Join-Path `\$programDataRoot '*') /reset /T /C"));
    expect(
      audit,
      contains("/remove:g '*S-1-1-0' '*S-1-5-11' '*S-1-5-32-545' /T /C"),
    );
  });

  test(
    'Fusion acceptance treats cached proof as optional only on fresh run',
    () {
      final runner = _read(
        'scripts/windows/run_windows_fusion_paid_beta_acceptance_smoke.ps1',
      );

      expect(runner, contains("PSObject.Properties['cachedRouteConfirmed']"));
      expect(
        runner,
        contains('if (\$RequireCachedRoute -and -not \$cachedRouteConfirmed)'),
      );
      expect(runner, contains('cachedRouteConfirmed = \$cachedRouteConfirmed'));
    },
  );
}
