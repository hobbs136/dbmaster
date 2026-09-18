#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DbMaster 翻译总结报告
生成当前翻译状态总结
"""
import json
import os
from datetime import datetime

def get_translation_status():
    """获取翻译状态"""
    base_dir = 'lib/l10n'
    
    # 加载英文模板
    with open(f'{base_dir}/app_en.arb', 'r', encoding='utf-8') as f:
        en_data = json.load(f)
    
    # 定义语言
    languages = {
        'zh': {'name': '简体中文', 'file': 'app_zh.arb'},
        'de': {'name': '德语', 'file': 'app_de.arb'},
        'fr': {'name': '法语', 'file': 'app_fr.arb'},
        'ru': {'name': '俄语', 'file': 'app_ru.arb'},
        'zh_TW': {'name': '繁体中文', 'file': 'app_zh-TW.arb'}
    }
    
    # 计算统计
    total_messages = len([k for k in en_data.keys() if not k.startswith('@')])
    
    report = {
        'total_messages': total_messages,
        'languages': {}
    }
    
    for lang_code, lang_info in languages.items():
        filepath = f'{base_dir}/{lang_info["file"]}'
        
        if os.path.exists(filepath):
            with open(filepath, 'r', encoding='utf-8') as f:
                lang_data = json.load(f)
            
            translated_count = len([k for k in en_data.keys() if not k.startswith('@') and k in lang_data])
            untranslated_count = total_messages - translated_count
            completion = (translated_count / total_messages) * 100 if total_messages > 0 else 0
            
            report['languages'][lang_code] = {
                'name': lang_info['name'],
                'translated': translated_count,
                'untranslated': untranslated_count,
                'completion': round(completion, 2),
                'exists': True
            }
        else:
            report['languages'][lang_code] = {
                'name': lang_info['name'],
                'translated': 0,
                'untranslated': total_messages,
                'completion': 0,
                'exists': False
            }
    
    return report

def main():
    print("=" * 80)
    print("DbMaster 翻译状态报告")
    print("=" * 80)
    print()
    
    # 获取翻译状态
    report = get_translation_status()
    
    # 总体统计
    print(f"📊 总体统计")
    print(f"   英文模板消息总数: {report['total_messages']}")
    print()
    
    # 每个语言的统计
    print(f"🌍 各语言翻译状态:")
    print()
    
    for lang_code, lang_data in report['languages'].items():
        name = lang_data['name']
        translated = lang_data['translated']
        untranslated = lang_data['untranslated']
        completion = lang_data['completion']
        exists = lang_data['exists']
        
        if not exists:
            print(f"   {name:15s} | ⚠️  文件不存在")
        elif completion == 100:
            print(f"   {name:15s} | ✅  完整 ({translated}/{report['total_messages']})")
        elif completion > 80:
            print(f"   {name:15s} | 🟢  {completion}% ({translated}/{report['total_messages']})")
        elif completion > 50:
            print(f"   {name:15s} | 🟡  {completion}% ({translated}/{report['total_messages']})")
        elif completion > 20:
            print(f"   {name:15s} | 🟠  {completion}% ({translated}/{report['total_messages']})")
        else:
            print(f"   {name:15s} | 🔴  {completion}% ({translated}/{report['total_messages']})")
    
    print()
    print("=" * 80)
    print()
    
    # 未翻译的键
    print("📋 未翻译的消息:")
    print()
    
    for lang_code, lang_data in report['languages'].items():
        if lang_data['untranslated'] > 0:
            print(f"   {lang_data['name']}: {lang_data['untranslated']} 条未翻译")
    
    print()
    print("=" * 80)
    print()
    
    # 翻译建议
    print("💡 建议:")
    print()
    
    needs_translation = any(l['untranslated'] > 0 for l in report['languages'].values())
    
    if needs_translation:
        print("   使用以下方式完成翻译:")
        print()
        print("   1. CSV 模板方式 (推荐）:")
        print("      python3 scripts/generate_translation_template.py")
        print("      # 编辑 translation_template.csv")
        print("      python3 scripts/import_translations.py translation_template.csv")
        print()
        print("   2. 查看未翻译报告:")
        print("      cat docs/untranslated-messages-report.md")
        print()
        print("   3. 手动翻译 ARB 文件:")
        print("      编辑 lib/l10n/app_*.arb 文件")
    else:
        print("   ✅ 所有翻译已完成！")
        print()
        print("   下一步:")
        print("      flutter gen-l10n")
        print("      flutter build")
    
    print()

if __name__ == '__main__':
    main()
