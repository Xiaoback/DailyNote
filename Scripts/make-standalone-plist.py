"""Bundle metadata for the standalone public beta."""
import pathlib
import plistlib
import sys

app = pathlib.Path(sys.argv[1])
info = {
    'CFBundleIdentifier': 'io.github.Xiaoback.DailyNote',
    'CFBundleName': 'DailyNote',
    'CFBundleDisplayName': '今日便笺',
    'CFBundleExecutable': 'DailyNote',
    'CFBundleIconFile': 'AppIcon',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '0.1.0',
    'CFBundleVersion': '20',
    'LSMinimumSystemVersion': '14.0',
    'NSHighResolutionCapable': True,
    'NSPrincipalClass': 'NSApplication',
}
with (app / 'Contents/Info.plist').open('wb') as file:
    plistlib.dump(info, file)
