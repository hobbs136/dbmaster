#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DbMaster 测试翻译脚本 - 翻译前 10 条消息
"""
import json
import os
import urllib.request
import urllib.parse
import time

def translate_google(text, target_lang):
    """使用 Google Translate API"""
    try:
        url = f"https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl={target_lang}&dt=t&q={urllib.parse.quote(text)}"
        with urllib.request.urlopen(url, timeout=10) as response:
            result = json.loads(response.read().decode())
        if result and len(result) > 0:
            return result[0][0][0]
        return text
    except Exception as e:
        print(f"⚠️  翻译失败: {e}")
        return text

def main():
    print("=" * 80)
    print("DbMaster 测试翻译 (前 10 条消息)")
    print("=" * 80)
    print()
    
    # 加载英文模板
    with open('lib/l10n/app_en.arb', 'r', encoding='utf-8') as f:
        en_data = json.load(f)
    
    # 获取前 10 条消息
    messages = []
    for key, value in en_data.items():
        if key.startswith('@'):
            continue
        messages.append((key, value))
        if len(messages) >= 10:
            break
    
    # 测试翻译
    languages = [
        ('de', '德语'),
        ('fr', '法语'),
        ('ru', '俄语')
    ]
    
    for lang_code, lang_name in languages:
        print(f"\n{'='*80}")
        print(f"🌐 测试 {lang_name} ({lang_code})")
        print(f"{'='*80}")
        
        # 加载现有翻译
        filename = f'lib/l10n/app_{lang_code}.arb'
        if os.path.exists(filename):
            with open(filename, 'r', encoding='utf-8') as f:
                existing_data = json.load(f)
        else:
            existing_data = {}
        
        # 翻译前 10 条
        for i, (key, value) in enumerate(messages, 1):
            print(f"[{i}/10] {key[:30]}...", end='\r')
            
            translated = translate_google(value, lang_code)
            existing_data[key] = translated
            
            time.sleep(0.5)  # 避免请求过快
        
        # 保存
        with open(filename, 'w', encoding='utf-8') as f:
            json.dump(existing_data, f, ensure_ascii=False, indent=2)
        
        print(f"\n✅ 已保存 {len(messages)} 条到 {filename}")
    
    print("\n" + "=" * 80)
    print("✅ 测试翻译完成！")
    print("=" * 80)
    print()
    print("📋 查看翻译:")
    print("   cat lib/l10n/app_de.arb")
    print()
    print("💡 如果翻译质量可以，运行完整翻译:")
    print("   python3 scripts/simple_translate.py")

if __name__ == '__main__':
    main()
