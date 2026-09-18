import os
import re
import sys

# Replacement rules for migrating from AppTheme to AppDesignSystem
REPLACEMENTS = [
    (r'AppTheme\.accentRed\b', 'AppDesignSystem.error'),
    (r'AppTheme\.accentBlue\b', 'AppDesignSystem.accentPrimary'),
    (r'AppTheme\.accentGreen\b', 'AppDesignSystem.success'),
    (r'AppTheme\.accentOrange\b', 'AppDesignSystem.warning'),
    (r'AppTheme\.accentPurple\b', 'AppDesignSystem.accentPurple'),
    (r'AppTheme\.accentYellow\b', 'AppDesignSystem.warning'),
    (r'AppTheme\.accentCyan\b', 'AppDesignSystem.info'),
    (r'AppTheme\.accentPink\b', 'AppDesignSystem.error'),
    (r'AppTheme\.spacingXs\b', 'AppDesignSystem.space1'),
    (r'AppTheme\.spacingSm\b', 'AppDesignSystem.space2'),
    (r'AppTheme\.spacingMd\b', 'AppDesignSystem.space3'),
    (r'AppTheme\.spacingLg\b', 'AppDesignSystem.space4'),
    (r'AppTheme\.spacingXl\b', 'AppDesignSystem.space6'),
    (r'AppTheme\.spacing2xl\b', 'AppDesignSystem.space8'),
    (r'AppTheme\.radiusSm\b', 'AppDesignSystem.radiusSm'),
    (r'AppTheme\.radiusMd\b', 'AppDesignSystem.radiusMd'),
    (r'AppTheme\.radiusLg\b', 'AppDesignSystem.radiusMd'),
    (r'AppTheme\.radiusXl\b', 'AppDesignSystem.radiusMd'),
    (r'AppTheme\.bgPrimary\b', 'AppDesignSystem.bgPrimary'),
    (r'AppTheme\.bgSecondary\b', 'AppDesignSystem.bgSecondary'),
    (r'AppTheme\.bgTertiary\b', 'AppDesignSystem.bgTertiary'),
    (r'AppTheme\.bgHover\b', 'AppDesignSystem.bgTertiary'),
    (r'AppTheme\.bgActive\b', 'AppDesignSystem.bgTertiary'),
    (r'AppTheme\.textPrimary\b', 'AppDesignSystem.textPrimary'),
    (r'AppTheme\.textSecondary\b', 'AppDesignSystem.textSecondary'),
    (r'AppTheme\.textMuted\b', 'AppDesignSystem.textTertiary'),
    (r'AppTheme\.borderColor\b', 'AppDesignSystem.borderDefault'),
    (r'AppTheme\.borderLight\b', 'AppDesignSystem.borderLight'),
    (r'AppTheme\.dividerColor\b', 'AppDesignSystem.divider'),
    (r'AppTheme\.sidebarWidth\b', 'AppDesignSystem.sidebarWidth'),
    (r'AppTheme\.aiPanelWidth\b', 'AppDesignSystem.aiPanelWidth'),
    (r'AppTheme\.toolbarHeight\b', 'AppDesignSystem.toolbarHeight'),
    (r'AppTheme\.statusHeight\b', 'AppDesignSystem.statusHeight'),
]

# Files to exclude from replacement
EXCLUDE_FILES = {
    'lib/theme/app_theme.dart',
    'lib/theme/design_system.dart',
}

def process_file(filepath):
    """Process a single Dart file."""
    try:
        with open(filepath, 'rb') as f:
            raw = f.read()
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return False

    # Try to decode as UTF-8, fallback to UTF-8 with errors ignored
    try:
        content = raw.decode('utf-8')
    except UnicodeDecodeError:
        content = raw.decode('utf-8', errors='replace')

    original = content
    replaced = False

    for pattern, replacement in REPLACEMENTS:
        if re.search(pattern, content):
            content = re.sub(pattern, replacement, content)
            replaced = True

    if replaced:
        try:
            with open(filepath, 'wb') as f:
                f.write(content.encode('utf-8'))
            print(f"Updated: {filepath}")
            return True
        except Exception as e:
            print(f"Error writing {filepath}: {e}")
            return False
    return False

def main():
    lib_dir = 'lib'
    updated_count = 0

    for root, dirs, files in os.walk(lib_dir):
        for filename in files:
            if not filename.endswith('.dart'):
                continue
            filepath = os.path.join(root, filename).replace('\\', '/')
            if filepath in EXCLUDE_FILES:
                continue
            if process_file(filepath):
                updated_count += 1

    print(f"\nTotal files updated: {updated_count}")

if __name__ == '__main__':
    main()
