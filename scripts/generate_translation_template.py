#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DbMaster 翻译模板生成器
生成翻译模板文件，方便后续使用翻译工具批量翻译
"""
import json
import os
from datetime import datetime

def generate_translation_template():
    """生成翻译模板文件"""
    
    print("=" * 80)
    print("DbMaster 翻译模板生成器")
    print("=" * 80)
    print()
    
    base_dir = 'lib/l10n'
    template_file = f'{base_dir}/app_en.arb'
    
    # 读取英文模板
    with open(template_file, 'r', encoding='utf-8') as f:
        en_data = json.load(f)
    
    # 定义要翻译的语言
    languages = {
        'de': {'name': '德语', 'file': 'app_de.arb'},
        'fr': {'name': '法语', 'file': 'app_fr.arb'},
        'ru': {'name': '俄语', 'file': 'app_ru.arb'},
        'zh_TW': {'name': '繁体中文', 'file': 'app_zh-TW.arb'}
    }
    
    # 生成翻译 CSV 文件
    csv_file = 'translation_template.csv'
    
    with open(csv_file, 'w', encoding='utf-8') as csv:
        # 写入表头
        csv.write('Key,English,German (de),French (fr),Russian (ru),Traditional Chinese (zh_TW)\n')
        
        # 写入数据
        for key in sorted(en_data.keys()):
            if key.startswith('@'):
                continue
            
            # 获取英文值，处理引号和换行
            en_value = en_data[key].replace('"', '""').replace('\n', '\\n')
            
            # 写入行
            csv.write(f'"{key}","{en_value}",,,,\n')
    
    print(f"✅ 翻译模板已生成: {csv_file}")
    print(f"   共 {len([k for k in en_data.keys() if not k.startswith('@')])} 条消息")
    print()
    
    # 为每个语言生成缺失的键
    for lang_code, lang_info in languages.items():
        translation_file = f'{base_dir}/{lang_info["file"]}'
        
        # 检查文件是否存在
        if not os.path.exists(translation_file):
            print(f"⚠️  文件不存在: {translation_file}")
            print(f"   将创建空白模板...")
            
            # 创建空白模板
            blank_data = {}
            with open(translation_file, 'w', encoding='utf-8') as f:
                json.dump(blank_data, f, ensure_ascii=False, indent=2)
            
            print(f"   ✅ 已创建: {translation_file}")
        else:
            # 读取现有翻译
            with open(translation_file, 'r', encoding='utf-8') as f:
                existing_data = json.load(f)
            
            # 找出缺失的键
            missing_keys = []
            for key in en_data:
                if key.startswith('@'):
                    continue
                if key not in existing_data:
                    missing_keys.append(key)
            
            if missing_keys:
                print(f"\n📋 {lang_info['name']} ({lang_code})")
                print(f"   缺失 {len(missing_keys)} 个键")
                
                # 显示前 20 个缺失的键
                for i, key in enumerate(missing_keys[:20], 1):
                    print(f"   {i:3d}. {key}")
                
                if len(missing_keys) > 20:
                    print(f"   ... 还有 {len(missing_keys) - 20} 个键")
            else:
                print(f"✅ {lang_info['name']} ({lang_code}) 已完整")
    
    print()
    print("=" * 80)
    print("📝 使用说明")
    print("=" * 80)
    print()
    print("1. 使用生成的 CSV 文件进行翻译:")
    print("   - 打开 translation_template.csv")
    print("   - 使用 Google Sheets 或 Excel 编辑")
    print("   - 使用 Google Translate 或 DeepL 翻译英文列")
    print("   - 填充对应语言的列")
    print()
    print("2. 或者使用在线翻译工具:")
    print("   - https://translate.google.com")
    print("   - https://www.deepl.com")
    print()
    print("3. 翻译完成后，运行翻译导入脚本:")
    print("   python3 scripts/import_translations.py translation_template.csv")
    print()
    print("💡 提示:")
    print("   - 保留专业术语不翻译 (SQL, Database, Query 等)")
    print("   - 检查占位符 {count} 保持不变")
    print("   - 运行 'flutter gen-l10n' 验证翻译")

if __name__ == '__main__':
    generate_translation_template()
