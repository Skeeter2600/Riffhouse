import 'package:flutter_test/flutter_test.dart';
import 'package:riffhouse/services/update_service.dart';
import 'package:riffhouse/widgets/update_dialog.dart';

void main() {
  group('Version comparison', () {
    test('compares numerically, not alphabetically', () {
      expect(UpdateService.isNewer('1.10.0', '1.9.0'), isTrue);
      expect(UpdateService.isNewer('1.9.0', '1.10.0'), isFalse);
      expect(UpdateService.isNewer('2.0.0', '1.99.99'), isTrue);
    });

    test('ignores the v prefix, build numbers and missing parts', () {
      expect(UpdateService.compareVersions('v1.0.0', '1.0.0+1'), 0);
      expect(UpdateService.compareVersions('1.2', '1.2.0'), 0);
      expect(UpdateService.isNewer('v1.0.1', '1.0.0+7'), isTrue);
    });

    test('the same or an older release is not an update', () {
      expect(UpdateService.isNewer('v1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewer('v0.9.0', '1.0.0'), isFalse);
    });
  });

  group('GitHub release parsing', () {
    final json = <String, dynamic>{
      'tag_name': 'v1.2.0',
      'name': 'Release v1.2.0',
      'html_url': 'https://github.com/Skeeter2600/Riffhouse/releases/tag/v1.2.0',
      'body': '## Fixes\r\n- Shuffle\r\n',
      'assets': [
        {
          'name': 'Riffhouse-Windows-x64.zip',
          'browser_download_url': 'https://example.com/win.zip',
          'size': 10,
          'digest': 'sha256:ABCDEF',
        },
        {
          'name': 'Riffhouse-Linux-x64.tar.gz',
          'browser_download_url': 'https://example.com/linux.tar.gz',
          'size': 20,
        },
        {
          'name': 'Riffhouse-Android.apk',
          'browser_download_url': 'https://example.com/app.apk',
          'size': 1234,
        },
      ],
    };

    test('picks the APK asset and normalises version and notes', () {
      final release =
          UpdateService.parseRelease(json, target: UpdateTarget.android)!;
      expect(release.version, '1.2.0');
      expect(release.title, 'Release v1.2.0');
      expect(release.notes, '## Fixes\n- Shuffle');
      expect(release.downloadUrl, 'https://example.com/app.apk');
      expect(release.downloadName, 'Riffhouse-Android.apk');
      expect(release.downloadSizeBytes, 1234);
      expect(release.downloadSha256, isNull);
    });

    test('each platform gets its own asset', () {
      final windows =
          UpdateService.parseRelease(json, target: UpdateTarget.windows)!;
      expect(windows.downloadUrl, 'https://example.com/win.zip');
      expect(windows.downloadSha256, 'abcdef');

      final linux =
          UpdateService.parseRelease(json, target: UpdateTarget.linux)!;
      expect(linux.downloadUrl, 'https://example.com/linux.tar.gz');

      final other =
          UpdateService.parseRelease(json, target: UpdateTarget.none)!;
      expect(other.downloadUrl, isNull);
    });

    test('a release without an APK has no download URL', () {
      final release = UpdateService.parseRelease(
        {...json, 'assets': []},
        target: UpdateTarget.android,
      )!;
      expect(release.downloadUrl, isNull);
    });

    test('a payload without a tag is rejected', () {
      expect(UpdateService.parseRelease({'message': 'Not Found'}), isNull);
    });
  });

  group('Desktop update scripts', () {
    test('Windows script waits for the app, copies and restarts it', () {
      const script = UpdateService.windowsUpdateScript;
      final wait = script.indexOf(r'>>"%RIFF_DST%\%RIFF_EXE%" call');
      final copy = script.indexOf('robocopy "%RIFF_SRC%" "%RIFF_DST%"');
      final restart = script.indexOf(r'start "" "%RIFF_DST%\%RIFF_EXE%"');
      expect(wait, greaterThan(0));
      expect(copy, greaterThan(wait));
      expect(restart, greaterThan(copy));
    });

    test('Linux script quotes paths safely', () {
      final script = UpdateService.linuxUpdateScript(
        pid: 77,
        stagingDir: "/tmp/it's here/staging",
        installDir: '/opt/riff house',
        executableName: 'riffhouse',
      );
      expect(script, contains('kill -0 77'));
      expect(
        script,
        contains(r"""cp -af '/tmp/it'\''s here/staging'/. '/opt/riff house'/"""),
      );
      expect(script, contains("nohup '/opt/riff house/riffhouse'"));
    });
  });

  test('release notes drop inline Markdown markers but keep the text', () {
    expect(
      ReleaseNotesView.plainInline('Welcome to **Riffhouse**, see `Settings` and [the docs](https://x.y)'),
      'Welcome to Riffhouse, see Settings and the docs',
    );
  });
}
