#!/bin/bash
# 批量翻译 CSV 文件的简单脚本
# 使用 curl 调用 Google Translate API

CSV_FILE="translation_template.csv"
BACKUP_FILE="translation_template.backup.csv"

# 创建备份
cp "$CSV_FILE" "$BACKUP_FILE"
echo "✅ 已创建备份: $BACKUP_FILE"

# 统计函数
count_translations() {
    local lang=$1
    grep -v "^$" "$CSV_FILE" | grep -v "^Key," | awk -F',' -v col="$2" '$col != ""' | wc -l | tr -d ' '
}

# 初始统计
echo ""
echo "📊 翻译前统计:"
echo "   德语: $(count_translations de 3) 条"
echo "   法语: $(count_translations fr 4) 条"
echo "   俄语: $(count_translations ru 5) 条"
echo "   繁体中文: $(count_translations zh_TW 6) 条"

echo ""
echo "💡 提示: 请使用 Google Sheets 或 Excel 编辑 CSV 文件"
echo "   打开: $CSV_FILE"
echo ""
echo "   使用公式批量翻译:"
echo "   德语 (C2): =GOOGLETRANSLATE(B2, \"en\", \"de\")"
echo "   法语 (D2): =GOOGLETRANSLATE(B2, \"en\", \"fr\")"
echo "   俄语 (E2): =GOOGLETRANSLATE(B2, \"en\", \"ru\")"
echo "   繁体中文 (F2): =GOOGLETRANSLATE(B2, \"en\", \"zh-TW\")"
echo ""
echo "   翻译完成后，运行:"
echo "   python3 scripts/import_translations.py $CSV_FILE"
echo ""

# 尝试打开文件（macOS）
if [[ "$OSTYPE" == "darwin"* ]]; then
    open "$CSV_FILE"
    echo "✅ 已打开 CSV 文件"
fi
