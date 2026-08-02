import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readRepoFile(String path) => File(path).readAsStringSync();

void main() {
  const primaryControlPlane = '72.56.32.197';
  const fallbackControlPlane = '176.113.81.35';
  const nl1DataPlane = '37.220.85.211';

  test('read-only server helpers default to the primary control plane', () {
    for (final path in <String>[
      'scripts/windows/check_external_services_readiness.ps1',
      'scripts/windows/check_payment_launch_safety.ps1',
      'scripts/windows/get_monitoring_probe_plan.ps1',
      'scripts/windows/get_owner_launch_packet.ps1',
    ]) {
      final source = readRepoFile(path);
      expect(source, contains('ControlPlaneHost = "$primaryControlPlane"'));
      expect(source, isNot(contains('ServerHost = "$nl1DataPlane"')));
    }
  });

  test('external readiness keeps control and VPN endpoint roles separate', () {
    final source = readRepoFile(
      'scripts/windows/check_external_services_readiness.ps1',
    );

    expect(source, contains('[Alias("ServerHost")]'));
    expect(source, contains('VpnEndpointHost = "$nl1DataPlane"'));
    expect(source, contains('root@\$ControlPlaneHost'));
    expect(source, isNot(contains('root@\$ServerHost')));
  });

  test('mutating backend wrappers require an explicit allowlisted host', () {
    for (final path in <String>[
      'scripts/windows/configure_backend_env_wsl.ps1',
      'scripts/windows/deploy_backend_wsl.ps1',
    ]) {
      final source = readRepoFile(path);
      expect(source, contains('ServerHost = ""'));
      expect(source, contains(primaryControlPlane));
      expect(source, contains(fallbackControlPlane));
      expect(source, contains('non-control-plane host'));
      expect(source, isNot(contains('ServerHost = "$nl1DataPlane"')));
    }

    for (final path in <String>[
      'scripts/configure_backend_env_wsl.sh',
      'scripts/deploy_backend_wsl.sh',
    ]) {
      final source = readRepoFile(path);
      expect(source, contains('SERVER_HOST="\${1:-}"'));
      expect(source, contains(primaryControlPlane));
      expect(source, contains(fallbackControlPlane));
      expect(source, contains('non-control-plane host'));
      expect(source, isNot(contains('SERVER_HOST="\${1:-$nl1DataPlane}"')));
    }
  });

  test('legacy Android cleanup is disabled unless explicitly enabled', () {
    final source = readRepoFile('scripts/windows/run_android_vpn_e2e.ps1');

    expect(source, contains('[switch]\$EnableServerCleanup'));
    expect(source, contains('-not \$EnableServerCleanup'));
    expect(source, contains('ControlPlaneHost = ""'));
    expect(source, contains(primaryControlPlane));
    expect(source, contains(fallbackControlPlane));
    expect(source, isNot(contains('ServerHost = "$nl1DataPlane"')));
  });

  test(
    'operator instructions and owner bundle use explicit control planes',
    () {
      for (final path in <String>[
        'docs/BACKEND_DEPLOY.md',
        'docs/CHATGPT_DOMAIN_EMAIL_HANDOFF_RU.md',
        'docs/EXTERNAL_SERVICES_CHECKLIST_RU.md',
        'docs/NEXT_OWNER_ACTIONS_RU.md',
        'docs/PAYMENTS_RU.md',
      ]) {
        final source = readRepoFile(path);
        final commands = RegExp(
          r'^powershell .*configure_backend_env_wsl\.ps1.*$',
          multiLine: true,
        ).allMatches(source);
        for (final command in commands) {
          expect(
            command.group(0),
            contains('-ServerHost $primaryControlPlane'),
          );
        }
      }

      final deployDoc = readRepoFile('docs/BACKEND_DEPLOY.md');
      expect(
        deployDoc,
        contains('deploy_backend_wsl.ps1 -ServerHost $primaryControlPlane'),
      );

      final androidDoc = readRepoFile('docs/MOBILE_APP_ANDROID_MVP_RU.md');
      for (final command in RegExp(
        r'^powershell .*run_android_vpn_e2e\.ps1.*$',
        multiLine: true,
      ).allMatches(androidDoc)) {
        expect(command.group(0), contains('-EnableServerCleanup'));
        expect(
          command.group(0),
          contains('-ControlPlaneHost $primaryControlPlane'),
        );
      }

      final backend = readRepoFile('backend_live/app/main.py');
      expect(
        backend,
        contains(
          'configure_backend_env_wsl.ps1 -ServerHost $primaryControlPlane',
        ),
      );
      expect(backend, contains('"serverHost": "$primaryControlPlane"'));
      expect(backend, contains('"controlPlaneHost": "$primaryControlPlane"'));
      expect(
        backend,
        contains('"fallbackControlPlaneHost": "$fallbackControlPlane"'),
      );
      expect(backend, contains('"vpnEndpointHost": "$nl1DataPlane"'));
      expect(backend, contains('только если monitoring readiness показывает'));

      final monitoringHelper = readRepoFile(
        'scripts/windows/get_monitoring_probe_plan.ps1',
      );
      expect(
        monitoringHelper,
        contains('No additional monitoring host is required'),
      );
      expect(
        monitoringHelper,
        contains('Provision or repair a separate monitoring VPS'),
      );
    },
  );
}
