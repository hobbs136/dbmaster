#!/usr/bin/env python3
"""
批量翻译 CSV 模板文件
使用 Google Translate API 翻译法语和俄语
"""

import csv
import json
import time
from pathlib import Path
from googletrans import Translator

# 颜色输出
class Colors:
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    RED = '\033[91m'
    END = '\033[0m'

def load_translations(arb_file):
    """加载现有的 ARB 翻译文件"""
    with open(arb_file, 'r', encoding='utf-8') as f:
        return json.load(f)

def main():
    csv_path = Path('translation_template.csv')
    if not csv_path.exists():
        print(f"{Colors.RED}❌ 未找到 translation_template.csv{Colors.END}")
        return

    # 加载现有翻译
    de_file = Path('lib/l10n/app_de.arb')
    fr_file = Path('lib/l10n/app_fr.arb')
    ru_file = Path('lib/l10n/app_ru.arb')
    zh_tw_file = Path('lib/l10n/app_zh_TW.arb')

    existing_translations = {}
    if de_file.exists():
        existing_translations['de'] = load_translations(de_file)
    if fr_file.exists():
        existing_translations['fr'] = load_translations(fr_file)
    if ru_file.exists():
        existing_translations['ru'] = load_translations(ru_file)
    if zh_tw_file.exists():
        existing_translations['zh_TW'] = load_translations(zh_tw_file)

    # 读取 CSV
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    print(f"{Colors.BLUE}📊 总共有 {len(rows)} 条消息待翻译{Colors.END}")

    # 初始化翻译器
    translator = Translator()

    # 定义要翻译的语言
    languages = {
        'fr': 'French (fr)',
        'ru': 'Russian (ru)',
    }

    # 统计
    stats = {lang: 0 for lang in languages.keys()}

    # 逐行翻译
    for i, row in enumerate(rows, 1):
        key = row['Key']
        english = row['English']

        if not english:
            continue

        print(f"{Colors.BLUE}[{i}/{len(rows)}]{Colors.END} 翻译: {key[:50]}...")

        for lang_code, lang_name in languages.items():
            # 跳过已有翻译
            if row[lang_name]:
                continue

            # 检查 ARB 文件中是否已有翻译
            if lang_code in existing_translations and key in existing_translations[lang_code]:
                existing_value = existing_translations[lang_code][key]
                if existing_value and existing_value != english:
                    row[lang_name] = existing_value
                    stats[lang_code] += 1
                    print(f"  {Colors.GREEN}✓{Colors.END} {lang_name}: 从 ARB 文件恢复")
                    continue

            # 使用 Google Translate 翻译
            try:
                result = translator.translate(english, dest=lang_code)
                row[lang_name] = result.text
                stats[lang_code] += 1
                print(f"  {Colors.GREEN}✓{Colors.END} {lang_name}: {result.text[:50]}...")

                # 避免请求过快
                time.sleep(0.1)

            except Exception as e:
                print(f"  {Colors.RED}✗{Colors.END} {lang_name}: 翻译失败 - {str(e)}")
                time.sleep(2)

    # 写回 CSV
    with open(csv_path, 'w', encoding='utf-8', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=reader.fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"\n{Colors.GREEN}✅ 翻译完成！{Colors.END}")
    print(f"\n{Colors.BLUE}📊 翻译统计:{Colors.END}")
    for lang_code, lang_name in languages.items():
        print(f"   {lang_name}: {stats[lang_code]} 条")

    print(f"\n{Colors.YELLOW}💡 下一步: 运行以下命令导入翻译{Colors.END}")
    print("   python3 scripts/import_translations.py translation_template.csv")

if __name__ == '__main__':
    main()
