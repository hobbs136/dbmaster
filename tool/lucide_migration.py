# C07 Lucide 切换脚本：Material Icons → LucideIcons 全局替换
# 用法：python tool/lucide_migration.py --validate | --apply
# 映射表 = D9 图标映射清单（一次性切换，2026-08-18 拍板）
import re, sys, pathlib, subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
LUCIDE_NAMES = set()
CACHE = pathlib.Path.home() / "AppData/Local/Pub/Cache/hosted/pub.dev"
for d in CACHE.glob("lucide_icons_flutter-*/lib"):
    src = (d / "lucide_icons.dart").read_text(encoding="utf-8")
    LUCIDE_NAMES |= set(re.findall(r"static const IconData (\w+)", src))

# ---- Material → Lucide 映射（语义策展；_outlined/_rounded 变体走基值归一） ----
M = {
  "abc": "caseSensitive", "access_time": "clock", "account_tree": "network",
  "add": "plus", "add_alert": "bellPlus", "add_circle": "circlePlus",
  "add_circle_outline": "circlePlus", "add_link": "link2", "admin_panel_settings": "shieldCheck",
  "analytics": "chartColumn", "archive": "archive", "arrow_back": "arrowLeft",
  "arrow_downward": "arrowDown", "arrow_drop_down": "chevronDown",
  "arrow_forward": "arrowRight", "arrow_forward_ios": "chevronRight",
  "arrow_upward": "arrowUp", "article": "fileText", "assessment": "chartColumn",
  "assignment": "clipboardList", "assignment_turned_in": "clipboardCheck", "attach_money": "dollarSign",
  "auto_awesome": "sparkles", "auto_fix_high": "wandSparkles", "av_timer": "timer",
  "backup": "databaseBackup", "balance": "scale", "bar_chart": "chartColumn",
  "bedtime": "moon", "block": "ban", "bolt": "zap", "bookmark": "bookmark",
  "bookmark_border": "bookmark", "brightness_auto": "sunMoon",
  "broken_image": "imageOff", "bug_report": "bug", "build": "wrench",
  "build_circle": "wrench", "cable": "cable", "calculate": "calculator",
  "calendar_today": "calendar", "call_split": "gitFork", "camera": "camera",
  "camera_alt": "camera", "cancel": "circleX", "category": "shapes",
  "chat_bubble": "messageCircle", "chat_bubble_outline": "messageCircle", "check": "check", "check_box": "squareCheckBig",
  "check_box_outline_blank": "square", "check_circle": "circleCheckBig",
  "chevron_left": "chevronLeft", "chevron_right": "chevronRight",
  "circle": "circle", "cleaning_services": "sprayCan", "clear": "x",
  "clear_all": "eraser", "close": "x", "cloud": "cloud", "cloud_done": "cloudCheck",
  "cloud_download": "cloudDownload", "cloud_off": "cloudOff", "cloud_queue": "cloud",
  "cloud_upload": "cloudUpload", "code": "code", "collections": "images",
  "compare_arrows": "arrowRightLeft", "computer": "monitor", "content_copy": "copy",
  "content_cut": "scissors", "content_paste": "clipboardPaste", "copy": "copy",
  "copy_all": "copy", "create_new_folder": "folderPlus", "dark_mode": "moon",
  "data_array": "brackets", "data_object": "braces", "data_usage": "chartPie",
  "database": "database", "dataset": "database", "delete": "trash2",
  "delete_forever": "trash2", "delete_sweep": "brushCleaning", "description": "fileText",
  "dns": "server", "dock": "panelBottom", "download": "download",
  "drive_file_rename": "pencilLine", "drive_file_rename_outline": "pencilLine", "edit": "pencil",
  "edit_calendar": "calendarClock", "edit_document": "filePen", "edit_note": "notebookPen",
  "email": "mail", "error": "circleAlert", "ev_station": "zapOff",
  "event": "calendar", "event_note": "calendar", "expand_less": "chevronUp", "expand_more": "chevronDown",
  "extension": "puzzle", "fact_check": "clipboardCheck", "fast_forward": "fastForward",
  "file_download": "fileDown", "file_open": "folderOpen", "file_upload": "fileUp",
  "filter_alt": "funnel", "filter_list": "listFilter", "fingerprint": "fingerprint",
  "first": "skipBack", "first_page": "chevronsLeft", "fit_screen": "maximize2",
  "flag": "flag", "flash_on": "zap", "folder": "folder", "folder_open": "folderOpen",
  "folder_shared": "folderSymlink", "folder_special": "folderBookmark",
  "format_align_left": "alignLeft", "format_list_bulleted": "list",
  "format_list_numbered": "listOrdered", "format_shapes": "shapes",
  "fullscreen": "maximize", "fullscreen_exit": "minimize", "functions": "functionSquare",
  "gavel": "gavel", "graphic_eq": "audioLines", "grid_on": "grid3x3",
  "grid_view": "layoutGrid", "group": "users", "group_add": "userPlus",
  "group_work": "users", "groups": "users", "help": "circleHelp", "history": "history",
  "history_toggle_off": "history", "hourglass_empty": "hourglass",
  "hourglass_top": "hourglass", "hub": "share2", "image": "image", "inbox": "inbox",
  "indexes": "listOrdered", "info": "info", "input": "logIn",
  "insert_drive_file": "file", "insights": "chartLine", "inventory": "package",
  "inventory_2": "package", "join_inner": "gitMerge", "key": "keyRound",
  "key_off": "keyRound", "keyboard": "keyboard", "keyboard_arrow_down": "chevronDown",
  "keyboard_arrow_right": "chevronRight", "keyboard_arrow_up": "chevronUp", "label": "tag",
  "language": "languages", "last": "skipForward", "last_page": "chevronsRight",
  "light_mode": "sun", "lightbulb": "lightbulb", "link": "link",
  "link_off": "unlink", "list": "list", "list_alt": "clipboardList",
  "lock": "lock", "lock_open": "lockOpen", "login": "logIn", "logout": "logOut",
  "manage_search": "textSearch", "map": "map", "memory": "memoryStick",
  "menu": "menu", "menu_book": "bookOpen", "menu_open": "panelLeftClose",
  "merge": "gitMerge", "message": "messageCircle", "monitor_heart": "heartPulse",
  "more_horiz": "ellipsis", "more_vert": "ellipsisVertical",
  "network_check": "activity", "notifications_active": "bellRing",
  "notifications_none": "bell", "notifications_off": "bellOff", "numbers": "hash",
  "opacity": "droplet", "open_in_new": "externalLink", "output": "squareTerminal",
  "palette": "palette", "password": "keyRound", "paste": "clipboardPaste",
  "pause_circle": "circlePause", "people": "users", "performance": "gauge",
  "person": "user", "person_add": "userPlus", "person_remove": "userMinus",
  "photo_library": "images", "pie_chart": "chartPie", "pin": "pin",
  "place": "mapPin", "play_arrow": "play", "play_circle": "circlePlay",
  "preview": "eye", "psychology": "brain", "push_pin": "pin",
  "query_stats": "chartLine", "radio_button_checked": "circleDot",
  "radio_button_off": "circle", "radio_button_unchecked": "circle",
  "raw_on": "code", "redo": "redo", "refresh": "refreshCw",
  "remove_circle": "circleMinus", "replay": "rotateCcw", "restore": "history",
  "rule": "listChecks", "save": "save", "save_as": "saveAll",
  "scatter_plot": "chartScatter", "schedule": "clock", "schema": "network",
  "search": "search", "search_off": "searchX", "security": "shield",
  "select_all": "textSelect", "send": "send", "server": "server",
  "settings": "settings", "settings_ethernet": "network", "shield": "shield",
  "show_chart": "trendingUp", "skip_next": "skipForward", "smart_toy": "bot",
  "sort": "arrowUpDown", "speed": "gauge", "splitscreen": "columns2",
  "star": "star", "star_border": "star", "stop": "square",
  "stop_circle": "circleStop", "storage": "database", "straighten": "ruler",
  "stream": "waves", "subscriptions": "rss", "swap_horiz": "arrowRightLeft",
  "swap_vert": "arrowUpDown", "switch_access_shortcut": "split", "sync": "refreshCw",
  "sync_alt": "arrowRightLeft", "sync_problem": "refreshCcw",
  "system_update_alt": "cloudDownload", "tab": "appWindow",
  "table_chart": "table2", "table_rows": "rows3", "table_view": "table",
  "tables": "table", "tag": "tag", "terminal": "terminal",
  "text_fields": "type", "thumb_up": "thumbsUp", "timeline": "activity",
  "timer": "timer", "toggle_on": "toggleRight", "touch_app": "pointer",
  "transform": "replace", "trending_up": "trendingUp", "trigger": "zap",
  "triggers": "zap", "trip_origin": "circleDot", "tune": "slidersHorizontal",
  "undo": "undo", "unfold_less": "chevronsDownUp", "unfold_more": "chevronsUpDown",
  "update": "rotateCw", "update_disabled": "infinity", "users": "users",
  "verified": "badgeCheck", "view": "eye", "view_agenda": "rows2",
  "view_column": "columns2", "view_list": "list", "view_module": "layoutGrid",
  "views": "eye", "visibility": "eye", "visibility_off": "eyeOff",
  "vpn_key": "keyRound", "warning": "triangleAlert", "warning_amber": "triangleAlert",
  "webhook": "webhook", "wifi": "wifi", "wifi_off": "wifiOff",
  "workspaces": "group", "zoom_in": "zoomIn", "zoom_out": "zoomOut",
  "zoom_out_map": "scan",
}

def normalize(name):
    # Material 变体后缀 → 基值（Lucide 全描边风格，无变体概念）
    for suf in ("_outlined", "_outline", "_rounded", "_sharp"):
        if name.endswith(suf):
            return name[: -len(suf)]
    return name

def resolve(name):
    n = normalize(name)
    return M.get(n)

# ---- 校验 ----
if "--validate" in sys.argv:
    ok = True
    for mat, luc in sorted(M.items()):
        if luc not in LUCIDE_NAMES:
            print(f"BAD-TARGET {mat} -> {luc}")
            ok = False
    used = set()
    for scope in ("lib", "test", "integration_test"):
        for f in (ROOT / scope).rglob("*.dart"):
            used |= set(re.findall(r"\bIcons\.(\w+)", f.read_text(encoding="utf-8")))
    for name in sorted(used):
        if resolve(name) is None:
            print(f"UNMAPPED {name}")
            ok = False
    print(f"lucide icons available: {len(LUCIDE_NAMES)}; material used: {len(used)}; mapped: {len(M)}")
    sys.exit(0 if ok else 1)

# ---- 替换 ----
assert "--apply" in sys.argv
pat = re.compile(r"\bIcons\.(\w+)")
IMPORT_LINE = "import 'package:lucide_icons_flutter/lucide_icons.dart';"
changed = 0
for scope in ("lib", "test", "integration_test"):
    for f in (ROOT / scope).rglob("*.dart"):
        text = orig = f.read_text(encoding="utf-8")
        def sub(m):
            r = resolve(m.group(1))
            assert r is not None, f"{f}: unmapped {m.group(1)}"
            return f"LucideIcons.{r}"
        text = pat.sub(sub, text)
        if text == orig:
            continue
        if "lucide_icons" not in text:
            lines = text.splitlines(keepends=True)
            last_pkg = max(
                (i for i, ln in enumerate(lines) if ln.startswith("import 'package:")),
                default=None,
            )
            if last_pkg is None:
                last_pkg = max(
                    (i for i, ln in enumerate(lines) if ln.startswith("import ")),
                    default=-1,
                )
            lines.insert(last_pkg + 1, IMPORT_LINE + "\n")
            text = "".join(lines)
        f.write_text(text, encoding="utf-8", newline="\n")
        changed += 1
print(f"rewrote {changed} files")
