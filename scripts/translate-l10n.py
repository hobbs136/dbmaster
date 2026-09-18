#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DbMaster 自动化翻译脚本
支持多种翻译服务：Google Translate, DeepL, Azure Translator 等
"""
import json
import sys
import os
from typing import Dict, List

# 支持的翻译服务
TRANSLATORS = {
    'google': 'Google Translate (免费)',
    'deepl': 'DeepL (需要 API Key)',
    'azure': 'Azure Translator (需要 API Key)',
    'manual': '手动翻译 (生成模板)'
}

# 语言映射
LANGUAGES = {
    'de': {'name': '德语', 'code': 'de'},
    'fr': {'name': '法语', 'code': 'fr'},
    'ru': {'name': '俄语', 'code': 'ru'},
    'zh_TW': {'name': '繁体中文', 'code': 'zh-TW'}
}

class Translator:
    """翻译器基类"""
    
    def translate(self, text: str, source_lang: str, target_lang: str) -> str:
        raise NotImplementedError

class GoogleTranslator(Translator):
    """Google Translate (使用 free googletrans 库)"""
    
    def __init__(self):
        try:
            from googletrans import Translator
            self.translator = Translator()
        except ImportError:
            print("⚠️  googletrans 未安装，请运行: pip install googletrans")
            sys.exit(1)
    
    def translate(self, text: str, source_lang: str, target_lang: str) -> str:
        try:
            result = self.translator.translate(text, src=source_lang, dest=target_lang)
            return result.text
        except Exception as e:
            print(f"⚠️  翻译失败: {e}")
            return text

class ManualTranslator(Translator):
    """手动翻译器 - 生成翻译模板"""
    
    def translate(self, text: str, source_lang: str, target_lang: str) -> str:
        return f"[需要翻译: {target_lang}] {text}"

def get_untranslated_keys(template_file: str, translation_file: str) -> List[Dict]:
    """获取未翻译的键"""
    with open(template_file, 'r', encoding='utf-8') as f:
        template_data = json.load(f)
    
    if os.path.exists(translation_file):
        with open(translation_file, 'r', encoding='utf-8') as f:
            translation_data = json.load(f)
    else:
        translation_data = {}
    
    untranslated = []
    for key in template_data:
        if key.startswith('@'):
            continue
        if key not in translation_data:
            untranslated.append({
                'key': key,
                'value': template_data[key]
            })
    
    return untranslated

def translate_language(
    template_file: str,
    output_file: str,
    target_lang: str,
    translator: Translator,
    batch_size: int = 10
):
    """翻译整个语言文件"""
    print(f"\n🔄 正在翻译 {LANGUAGES[target_lang]['name']}...")
    print(f"   目标文件: {output_file}")
    
    # 获取现有翻译
    if os.path.exists(output_file):
        with open(output_file, 'r', encoding='utf-8') as f:
            translated_data = json.load(f)
    else:
        translated_data = {}
    
    # 获取未翻译的键
    untranslated = get_untranslated_keys(template_file, output_file)
    total = len(untranslated)
    
    if total == 0:
        print("   ✅ 所有消息已翻译")
        return
    
    print(f"   未翻译数量: {total}")
    
    # 批量翻译
    success_count = 0
    for i, item in enumerate(untranslated, 1):
        key = item['key']
        value = item['value']
        
        print(f"   [{i}/{total}] 翻译: {key[:40]}...", end='\r')
        
        try:
            translated_value = translator.translate(value, 'en', LANGUAGES[target_lang]['code'])
            translated_data[key] = translated_value
            success_count += 1
            
            # 每翻译 batch_size 个保存一次
            if i % batch_size == 0:
                with open(output_file, 'w', encoding='utf-8') as f:
                    json.dump(translated_data, f, ensure_ascii=False, indent=2)
                print(f"\n   💾 已保存 {i} 条翻译")
        except Exception as e:
            print(f"\n   ⚠️  翻译失败: {key} - {e}")
            continue
    
    # 保存最终结果
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(translated_data, f, ensure_ascii=False, indent=2)
    
    print(f"\n   ✅ 翻译完成: {success_count}/{total}")

def main():
    print("=" * 80)
    print("DbMaster 自动化翻译工具")
    print("=" * 80)
    
    # 读取配置
    config_file = 'translate_config.json'
    if os.path.exists(config_file):
        with open(config_file, 'r', encoding='utf-8') as f:
            config = json.load(f)
    else:
        config = {
            'translator': 'google',
            'languages': ['de', 'fr', 'ru'],
            'batch_size': 10
        }
        with open(config_file, 'w', encoding='utf-8') as f:
            json.dump(config, f, ensure_ascii=False, indent=2)
        print(f"\n📝 已创建配置文件: {config_file}")
        print("   请修改配置文件后重新运行")
        return
    
    # 初始化翻译器
    translator_name = config.get('translator', 'google')
    
    print(f"\n🌐 使用翻译器: {translator_name}")
    
    if translator_name == 'google':
        translator = GoogleTranslator()
    elif translator_name == 'manual':
        translator = ManualTranslator()
    else:
        print(f"⚠️  暂不支持 {translator_name} 翻译器")
        print("   请使用 'google' 或 'manual'")
        return
    
    # 获取要翻译的语言
    languages = config.get('languages', ['de', 'fr', 'ru'])
    batch_size = config.get('batch_size', 10)
    
    print(f"📋 翻译语言: {', '.join([LANGUAGES[lang]['name'] for lang in languages])}")
    print(f"📦 批量大小: {batch_size}")
    
    base_dir = 'lib/l10n'
    template_file = f'{base_dir}/app_en.arb'
    
    # 翻译每个语言
    for lang in languages:
        if lang not in LANGUAGES:
            print(f"⚠️  不支持的语言: {lang}")
            continue
        
        output_file = f'{base_dir}/app_{lang.replace("_TW", "-TW")}.arb'
        translate_language(template_file, output_file, lang, translator, batch_size)
    
    print("\n" + "=" * 80)
    print("✅ 所有翻译完成！")
    print("=" * 80)
    print("\n💡 提示:")
    print("   1. 请检查生成的翻译文件")
    print("   2. 运行 'flutter gen-l10n' 验证翻译")
    print("   3. 如有专业术语错误，请手动修正")

if __name__ == '__main__':
    main()
