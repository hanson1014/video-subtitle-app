#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate
echo "啟動影片字幕翻譯工具..."
echo "打開瀏覽器: http://localhost:8899"
python main.py
