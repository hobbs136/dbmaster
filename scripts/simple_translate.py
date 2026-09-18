#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DbMaster 简化版自动翻译脚本
直接翻译并保存
"""
import json
import os
import sys

def translate_simple_google(text, target_lang):
    """使用免费的 Google Translate API（简化版）"""
    try:
        import urllib.request
        import urllib.parse
        
        # Google Translate API (免费版，无需API Key)
        url = f"https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl={target_lang}&dt=t&q={urllib.parse.quote(text)}"
        
        with urllib.request.urlopen(url, timeout=10) as response:
            result = json.loads(response.read().decode())
        
        if result and len(result) > 0:
            return result[0][0][0]
        
        return text
    except Exception as e:
        print(f"⚠️  翻译失败: {e}")
        return text

def translate_language(lang_code, target_lang, template_data, existing_data, max_translations=50):
    """翻译单个语言（限制数量演示）"""
    print(f"\n{'='*80}")
    print(f"🌐 翻译 {target_lang} ({lang_code})")
    print(f"{'='*80}")
    
    # 找出未翻译的键
    untranslated = []
    for key, value in template_data.items():
        if key.startswith('@'):
            continue
        if key not in existing_data:
            untranslated.append({'key': key, 'value': value})
    
    total = len(untranslated)
    
    if total == 0:
        print("✅ 所有消息已翻译")
        return
    
    print(f"📋 未翻译数量: {total}")
    print(f"⚡ 本次翻译: {min(total, max_translations)} (演示模式)")
    print()
    
    # 翻译前 max_translations 个
    success = 0
    for i, item in enumerate(untranslated[:max_translations], 1):
        key = item['key']
        value = item['value']
        
        print(f"[{i}/{min(total, max_translations)}] {key[:40]}...", end='\r')
        
        # 翻译
        translated = translate_simple_google(value, target_lang)
        
        # 保存
        existing_data[key] = translated
        success += 1
        
        # 显示进度
        if i % 10 == 0:
            print(f"\n💾 已翻译 {i} 条")
    
    # 保存文件
    filename = f'lib/l10n/app_{lang_code.replace("_TW", "-TW")}.arb'
    with open(filename, 'w', encoding='utf-8') as f:
        json.dump(existing_data, f, ensure_ascii=False, indent=2)
    
    print(f"\n\n✅ 已保存到: {filename}")
    print(f"📊 本次翻译: {success} 条")
    print(f"📊 剩余未翻译: {total - success} 条")

def main():
    print("=" * 80)
    print("DbMaster 简化版自动翻译工具")
    print("=" * 80)
    print()
    print("💡 提示: 此脚本使用 Google Translate 免费API")
    print("   每次运行最多翻译 50 条消息（演示模式）")
    print()
    
    # 加载英文模板
    template_file = 'lib/l10n/app_en.arb'
    print(f"📖 加载英文模板: {template_file}")
    
    with open(template_file, 'r', encoding='utf-8') as f:
        template_data = json.load(f)
    
    # 计算实际消息数量（排除 @ 开头的键）
    message_count = len([k for k in template_data.keys() if not k.startswith('@')])
    print(f"✅ 已加载 {message_count} 条消息")
    
    # 定义要翻译的语言
    languages = [
        ('de', 'de'),
        ('fr', 'fr'),
        ('ru', 'ru')
    ]
    
    # 翻译每个语言
    for lang_code, target_lang in languages:
        filename = f'lib/l10n/app_{lang_code.replace("_TW", "-TW")}.arb'
        
        # 加载现有翻译
        if os.path.exists(filename):
            with open(filename, 'r', encoding='utf-8') as f:
                existing_data = json.load(f)
        else:
            existing_data = {}
        
        translate_language(lang_code, target_lang, template_data, existing_data)
    
    print("\n" + "=" * 80)
    print("✅ 翻译完成！")
    print("=" * 80)
    print()
    print("可以多次运行此脚本来翻译所有消息")
    print()
    print("💡 下一步:")
    print("   1. 运行 'flutter gen-l10n' 验证翻译")
    print("   2. 手动检查专业术语翻译")
    print("   3. 运行 'flutter build' 测试应用")

if __name__ == '__main__':
    main()
