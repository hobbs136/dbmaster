#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DbMaster 翻译导入脚本
从 CSV 文件导入翻译到 ARB 文件
"""
import json
import csv
import os
import sys
from datetime import datetime

def import_translations(csv_file: str):
    """从 CSV 导入翻译"""
    
    print("=" * 80)
    print("DbMaster 翻译导入工具")
    print("=" * 80)
    print()
    
    if not os.path.exists(csv_file):
        print(f"⚠️  文件不存在: {csv_file}")
        return
    
    base_dir = 'lib/l10n'
    
    # 语言列映射
    lang_columns = {
        'de': 'German (de)',
        'fr': 'French (fr)',
        'ru': 'Russian (ru)',
        'zh_TW': 'Traditional Chinese (zh_TW)'
    }
    
    lang_files = {
        'de': f'{base_dir}/app_de.arb',
        'fr': f'{base_dir}/app_fr.arb',
        'ru': f'{base_dir}/app_ru.arb',
        'zh_TW': f'{base_dir}/app_zh-TW.arb'
    }
    
    # 读取 CSV 文件
    translations = {lang: {} for lang in lang_columns}
    
    with open(csv_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        
        for row in reader:
            key = row.get('Key', '').strip()
            if not key or key.startswith('@'):
                continue
            
            english_value = row.get('English', '').strip().replace('\\n', '\n')
            
            # 提取每个语言的翻译
            for lang, col_name in lang_columns.items():
                translated_value = row.get(col_name, '').strip().replace('\\n', '\n')
                
                if translated_value and translated_value != english_value:
                    translations[lang][key] = translated_value
    
    # 写入 ARB 文件
    for lang, trans_data in translations.items():
        if not trans_data:
            print(f"⏭️  跳过 {lang} (无翻译)")
            continue
        
        output_file = lang_files[lang]
        
        # 读取现有翻译
        if os.path.exists(output_file):
            with open(output_file, 'r', encoding='utf-8') as f:
                existing_data = json.load(f)
        else:
            existing_data = {}
        
        # 合并翻译
        existing_data.update(trans_data)
        
        # 写入文件
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(existing_data, f, ensure_ascii=False, indent=2)
        
        print(f"✅ {lang} ({len(trans_data)} 条)")
        print(f"   文件: {output_file}")
    
    print()
    print("=" * 80)
    print("✅ 翻译导入完成！")
    print("=" * 80)
    print()
    print("💡 下一步:")
    print("   1. 运行 'flutter gen-l10n' 验证翻译")
    print("   2. 运行 'flutter build' 测试应用")
    print("   3. 检查应用中的翻译是否正确")

if __name__ == '__main__':
    if len(sys.argv) > 1:
        csv_file = sys.argv[1]
    else:
        csv_file = 'translation_template.csv'
    
    import_translations(csv_file)
