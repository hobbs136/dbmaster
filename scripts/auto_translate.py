#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DbMaster Google Translate 自动翻译脚本
使用 googletrans 库自动翻译缺失的翻译
"""
import json
import os
import sys
import time

try:
    from googletrans import Translator
except ImportError:
    print("⚠️  googletrans 未安装")
    print("请运行: pip3 install googletrans")
    sys.exit(1)

# 语言映射
LANGUAGES = {
    'de': {'name': '德语', 'code': 'de'},
    'fr': {'name': '法语', 'code': 'fr'},
    'ru': {'name': '俄语', 'code': 'ru'},
    'zh_TW': {'name': '繁体中文', 'code': 'zh-TW'}
}

def translate_text(translator, text: str, target_lang: str, retry_count: int = 3) -> str:
    """翻译文本，带重试机制"""
    for attempt in range(retry_count):
        try:
            result = translator.translate(text, src='en', dest=target_lang)
            return result.text
        except Exception as e:
            if attempt < retry_count - 1:
                print(f"⚠️  翻译失败，重试 {attempt + 1}/{retry_count}...")
                time.sleep(1)
            else:
                print(f"❌ 翻译失败: {e}")
                return text

def load_translation_file(filename: str) -> dict:
    """加载翻译文件"""
    if os.path.exists(filename):
        with open(filename, 'r', encoding='utf-8') as f:
            return json.load(f)
    return {}

def save_translation_file(filename: str, data: dict):
    """保存翻译文件"""
    with open(filename, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def get_untranslated_keys(template_data: dict, existing_data: dict) -> list:
    """获取未翻译的键"""
    untranslated = []
    for key, value in template_data.items():
        if key.startswith('@'):
            continue
        if key not in existing_data:
            untranslated.append({'key': key, 'value': value})
    return untranslated

def translate_language(translator, lang_code: str, template_data: dict, batch_size: int = 10):
    """翻译单个语言"""
    if lang_code not in LANGUAGES:
        print(f"⚠️  不支持的语言: {lang_code}")
        return
    
    lang_info = LANGUAGES[lang_code]
    filename = f'lib/l10n/app_{lang_code.replace("_TW", "-TW")}.arb'
    
    print(f"\n{'='*80}")
    print(f"🌐 正在翻译 {lang_info['name']} ({lang_code})")
    print(f"{'='*80}")
    
    # 加载现有翻译
    existing_data = load_translation_file(filename)
    
    # 获取未翻译的键
    untranslated = get_untranslated_keys(template_data, existing_data)
    total = len(untranslated)
    
    if total == 0:
        print("✅ 所有消息已翻译")
        return
    
    print(f"📋 未翻译数量: {total}")
    print(f"📦 批量大小: {batch_size}")
    print()
    
    # 批量翻译
    success_count = 0
    fail_count = 0
    
    for i, item in enumerate(untranslated, 1):
        key = item['key']
        value = item['value']
        
        # 显示进度
        print(f"[{i}/{total}] 翻译: {key[:40]}{'...' if len(key) > 40 else ''}", end='\r')
        
        try:
            # 翻译文本
            translated_value = translate_text(translator, value, lang_info['code'])
            
            # 保存翻译
            existing_data[key] = translated_value
            success_count += 1
            
            # 每翻译 batch_size 个保存一次
            if i % batch_size == 0:
                save_translation_file(filename, existing_data)
                print(f"\n💾 已保存 {i} 条翻译 ({success_count} 成功, {fail_count} 失败)")
        
        except KeyboardInterrupt:
            print(f"\n\n⏸️  用户中断，已保存 {i-1} 条翻译")
            save_translation_file(filename, existing_data)
            sys.exit(0)
        except Exception as e:
            fail_count += 1
            print(f"\n❌ 翻译失败: {key} - {e}")
            continue
    
    # 保存最终结果
    save_translation_file(filename, existing_data)
    
    print(f"\n\n{'='*80}")
    print(f"✅ 翻译完成!")
    print(f"{'='*80}")
    print(f"📊 统计:")
    print(f"   总数: {total}")
    print(f"   成功: {success_count}")
    print(f"   失败: {fail_count}")
    print(f"   文件: {filename}")

def main():
    print("=" * 80)
    print("DbMaster Google Translate 自动翻译工具")
    print("=" * 80)
    print()
    
    # 初始化翻译器
    print("🔄 初始化 Google Translator...")
    translator = Translator()
    print("✅ Translator 已初始化")
    
    # 加载英文模板
    template_file = 'lib/l10n/app_en.arb'
    print(f"\n📖 加载英文模板: {template_file}")
    
    with open(template_file, 'r', encoding='utf-8') as f:
        template_data = json.load(f)
    
    print(f"✅ 已加载 {len([k for k in template_data.keys() if not k.startswith('@')])} 条消息")
    
    # 翻译语言列表
    languages_to_translate = ['de', 'fr', 'ru', 'zh_TW']
    
    print(f"\n🌍 将翻译以下语言:")
    for lang in languages_to_translate:
        if lang in LANGUAGES:
            print(f"   - {LANGUAGES[lang]['name']} ({lang})")
    
    # 批量大小
    batch_size = 10
    
    print(f"\n📦 批量大小: {batch_size}")
    print("\n⚡ 开始翻译...")
    print()
    
    # 翻译每个语言
    for lang in languages_to_translate:
        translate_language(translator, lang, template_data, batch_size)
        time.sleep(2)  # 避免请求过快
    
    print("\n" + "=" * 80)
    print("🎉 所有翻译完成！")
    print("=" * 80)
    print()
    print("💡 下一步:")
    print("   1. 运行 'flutter gen-l10n' 验证翻译")
    print("   2. 运行 'flutter build' 测试应用")
    print("   3. 手动检查专业术语翻译是否正确")

if __name__ == '__main__':
    main()
