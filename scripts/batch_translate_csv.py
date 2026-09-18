#!/usr/bin/env python3
"""
批量翻译 CSV 模板文件 - 使用 DeepL 或 Google Translate
支持继续翻译和断点续传
"""

import csv
import json
import time
import sys
from pathlib import Path
from googletrans import Translator

# 颜色输出
class Colors:
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    RED = '\033[91m'
    CYAN = '\033[96m'
    END = '\033[0m'

def load_translations(arb_file):
    """加载现有的 ARB 翻译文件"""
    try:
        with open(arb_file, 'r', encoding='utf-8') as f:
            return json.load(f)
    except:
        return {}

def main():
    csv_path = Path('translation_template.csv')
    if not csv_path.exists():
        print(f"{Colors.RED}❌ 未找到 translation_template.csv{Colors.END}")
        print("   请先运行: python3 scripts/generate_translation_template.py")
        return

    # 加载现有翻译
    existing_translations = {}
    arb_files = {
        'de': Path('lib/l10n/app_de.arb'),
        'fr': Path('lib/l10n/app_fr.arb'),
        'ru': Path('lib/l10n/app_ru.arb'),
        'zh_TW': Path('lib/l10n/app_zh_TW.arb')
    }

    for lang_code, arb_file in arb_files.items():
        if arb_file.exists():
            existing_translations[lang_code] = load_translations(arb_file)

    # 读取 CSV
    print(f"{Colors.CYAN}📂 正在读取 CSV 文件...{Colors.END}")
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    print(f"{Colors.BLUE}📊 总共有 {len(rows)} 条条目{Colors.END}")

    # 初始化翻译器
    print(f"{Colors.CYAN}🌐 初始化翻译器...{Colors.END}")
    translator = Translator()

    # 定义要翻译的语言
    languages = {
        'de': 'German (de)',
        'fr': 'French (fr)',
        'ru': 'Russian (ru)',
        'zh_TW': 'Traditional Chinese (zh_TW)'
    }

    # 统计
    stats = {lang: {'from_arb': 0, 'translated': 0, 'skipped': 0} for lang in languages.keys()}

    # 逐行翻译
    print(f"\n{Colors.YELLOW}开始翻译...{Colors.END}")
    print(f"{Colors.CYAN}{'='*70}{Colors.END}\n")

    for i, row in enumerate(rows, 1):
        key = row['Key']
        english = row['English']

        if not english:
            continue

        # 显示进度
        if i % 50 == 0:
            print(f"{Colors.CYAN}进度: [{i}/{len(rows)}]{Colors.END}")

        for lang_code, lang_name in languages.items():
            # 跳过已有翻译
            if row[lang_name]:
                stats[lang_code]['skipped'] += 1
                continue

            # 检查 ARB 文件中是否已有翻译
            if lang_code in existing_translations and key in existing_translations[lang_code]:
                existing_value = existing_translations[lang_code][key]
                if existing_value and existing_value !='':
                    row[lang_name] = existing_value
                    stats[lang_code]['from_arb'] += 1
                    continue

            # 使用 Google Translate 翻译
            try:
                # 简体中文直接从繁体中文转换
                if lang_code == 'zh_TW':
                    # 从简体中文翻译（因为简体中文已完整）
                    if existing_translations.get('zh') and key in existing_translations['zh']:
                        source_text = existing_translations['zh'][key]
                        if source_text:
                            result = translator.translate(source_text, dest='zh-TW', src='zh-cn')
                            row[lang_name] = result.text
                            stats[lang_code]['translated'] += 1
                    continue

                # 其他语言从英文翻译
                result = translator.translate(english, dest=lang_code)
                row[lang_name] = result.text
                stats[lang_code]['translated'] += 1

                # 避免请求过快
                time.sleep(0.05)

            except Exception as e:
                # 重试一次
                try:
                    time.sleep(1)
                    result = translator.translate(english, dest=lang_code)
                    row[lang_name] = result.text
                    stats[lang_code]['translated'] += 1
                except:
                    time.sleep(0.5)
                    continue

        # 每 100 行保存一次，防止数据丢失
        if i % 100 == 0:
            with open(csv_path, 'w', encoding='utf-8', newline='') as f:
                writer = csv.DictWriter(f, fieldnames=reader.fieldnames)
                writer.writeheader()
                writer.writerows(rows)
            print(f"{Colors.GREEN}✓ 已保存进度 ({i} 行){Colors.END}")

    # 最终保存
    print(f"\n{Colors.CYAN}正在保存最终结果...{Colors.END}")
    with open(csv_path, 'w', encoding='utf-8', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=reader.fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"\n{Colors.GREEN}{'='*70}{Colors.END}")
    print(f"{Colors.GREEN}✅ 翻译完成！{Colors.END}\n")

    print(f"{Colors.BLUE}📊 翻译统计:{Colors.END}")
    for lang_code, lang_name in languages.items():
        total = stats[lang_code]['from_arb'] + stats[lang_code]['translated']
        print(f"   {lang_name}:")
        print(f"      - 从 ARB 恢复: {stats[lang_code]['from_arb']} 条")
        print(f"      - 新翻译: {stats[lang_code]['translated']} 条")
        print(f"      - 已有翻译: {stats[lang_code]['skipped']} 条")
        print(f"      - 总计: {total} 条")

    print(f"\n{Colors.YELLOW}💡 下一步: 运行以下命令导入翻译{Colors.END}")
    print("   python3 scripts/import_translations.py translation_template.csv")
    print(f"\n{Colors.YELLOW}💡 验证翻译: 运行以下命令检查{Colors.END}")
    print("   flutter gen-l10n")

if __name__ == '__main__':
    main()
