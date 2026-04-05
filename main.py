"""Video Subtitle App - 本地影片字幕翻譯工具"""

import asyncio
import json
import os
import subprocess
import tempfile
import uuid
from pathlib import Path
from typing import Optional, List, Dict

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from transcriber import transcribe_audio
from translator import translate_segments, load_model, SUPPORTED_LANGUAGES

app = FastAPI()

BASE_DIR = Path(__file__).parent
OUTPUT_DIR = BASE_DIR / "output"
TEMP_DIR = BASE_DIR / "temp"
OUTPUT_DIR.mkdir(exist_ok=True)
TEMP_DIR.mkdir(exist_ok=True)

app.mount("/static", StaticFiles(directory=str(BASE_DIR / "static")), name="static")



@app.get("/")
async def index():
    return FileResponse(str(BASE_DIR / "static" / "index.html"))


@app.get("/api/languages")
async def get_languages():
    return {"languages": SUPPORTED_LANGUAGES}


@app.websocket("/ws/process")
async def process_video(ws: WebSocket):
    await ws.accept()
    try:
        data = await ws.receive_json()
        url = data["url"]
        target_lang = data.get("target_lang", "zh-TW")
        whisper_model = data.get("whisper_model", "medium")

        job_id = str(uuid.uuid4())[:8]
        job_dir = OUTPUT_DIR / job_id
        job_dir.mkdir(exist_ok=True)

        # Step 1: Download video
        await ws.send_json({"step": "download", "status": "started", "message": "正在下載影片..."})
        video_path = await download_video(url, job_dir)
        if not video_path:
            await ws.send_json({"step": "download", "status": "error", "message": "下載失敗，請檢查網址是否正確"})
            return
        await ws.send_json({"step": "download", "status": "done", "message": "影片下載完成"})

        # Step 2: Extract audio
        await ws.send_json({"step": "extract", "status": "started", "message": "正在提取音頻..."})
        audio_path = await extract_audio(video_path, job_dir)
        await ws.send_json({"step": "extract", "status": "done", "message": "音頻提取完成"})

        # Step 3: Transcribe
        await ws.send_json({"step": "transcribe", "status": "started", "message": f"正在轉錄語音（模型: {whisper_model}）..."})
        segments = await asyncio.to_thread(transcribe_audio, str(audio_path), whisper_model)
        original_srt = generate_srt(segments)
        srt_orig_path = job_dir / "original.srt"
        srt_orig_path.write_text(original_srt, encoding="utf-8")
        await ws.send_json({
            "step": "transcribe",
            "status": "done",
            "message": f"轉錄完成，共 {len(segments)} 段",
            "segments": segments,
            "srt_preview": original_srt[:2000],
        })

        # Step 4: Translate
        if target_lang:
            await ws.send_json({"step": "translate", "status": "started", "message": f"正在翻譯字幕到 {target_lang}（共 {len(segments)} 段）..."})
            translated = await asyncio.to_thread(translate_segments, segments, target_lang)
            await ws.send_json({
                "step": "translate",
                "status": "progress",
                "message": f"翻譯完成: {len(translated)}/{len(segments)} 段",
                "progress": 100,
            })

            translated_srt = generate_srt(translated)
            srt_trans_path = job_dir / "translated.srt"
            srt_trans_path.write_text(translated_srt, encoding="utf-8")

            # Generate dual subtitle SRT (original + translated)
            dual_srt = generate_dual_srt(segments, translated)
            srt_dual_path = job_dir / "dual.srt"
            srt_dual_path.write_text(dual_srt, encoding="utf-8")

            await ws.send_json({
                "step": "translate",
                "status": "done",
                "message": "翻譯完成",
                "translated_segments": translated,
                "srt_preview": translated_srt[:2000],
            })

        # Step 5: Burn subtitles into video
        await ws.send_json({"step": "burn", "status": "started", "message": "正在將字幕燒錄到影片..."})
        srt_to_burn = srt_trans_path if target_lang else srt_orig_path
        output_video = job_dir / "output.mp4"
        await burn_subtitles(video_path, srt_to_burn, output_video)
        await ws.send_json({"step": "burn", "status": "done", "message": "字幕燒錄完成"})

        # Done - send download links
        await ws.send_json({
            "step": "complete",
            "status": "done",
            "message": "全部完成！",
            "downloads": {
                "video": f"/api/download/{job_id}/output.mp4",
                "original_srt": f"/api/download/{job_id}/original.srt",
                "translated_srt": f"/api/download/{job_id}/translated.srt" if target_lang else None,
                "dual_srt": f"/api/download/{job_id}/dual.srt" if target_lang else None,
            },
        })

    except WebSocketDisconnect:
        pass
    except Exception as e:
        await ws.send_json({"step": "error", "status": "error", "message": str(e)})


@app.get("/api/download/{job_id}/{filename}")
async def download_file(job_id: str, filename: str):
    file_path = OUTPUT_DIR / job_id / filename
    if not file_path.exists():
        return {"error": "File not found"}
    return FileResponse(str(file_path), filename=filename)


async def download_video(url: str, job_dir: Path) -> Optional[Path]:
    output_template = str(job_dir / "video.%(ext)s")
    cmd = [
        "yt-dlp",
        "-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
        "--merge-output-format", "mp4",
        "-o", output_template,
        "--no-playlist",
        url,
    ]
    proc = await asyncio.create_subprocess_exec(
        *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
    )
    await proc.wait()

    # Find the downloaded video file
    for f in job_dir.iterdir():
        if f.suffix in (".mp4", ".mkv", ".webm"):
            return f
    return None


async def extract_audio(video_path: Path, job_dir: Path) -> Path:
    audio_path = job_dir / "audio.wav"
    cmd = [
        "ffmpeg", "-i", str(video_path),
        "-vn", "-acodec", "pcm_s16le", "-ar", "16000", "-ac", "1",
        "-y", str(audio_path),
    ]
    proc = await asyncio.create_subprocess_exec(
        *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
    )
    await proc.wait()
    return audio_path


async def burn_subtitles(video_path: Path, srt_path: Path, output_path: Path):
    srt_escaped = str(srt_path).replace("\\", "/").replace(":", "\\:").replace("'", "\\'")
    vf = f"scale=-2:1080,subtitles={srt_escaped}:force_style='FontSize=22,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,Outline=2'"
    cmd = [
        "ffmpeg", "-i", str(video_path),
        "-vf", vf,
        "-c:v", "h264_videotoolbox", "-b:v", "5M",
        "-c:a", "aac", "-b:a", "128k",
        "-async", "1",
        "-y", str(output_path),
    ]
    proc = await asyncio.create_subprocess_exec(
        *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
    )
    await proc.wait()


def format_timestamp(seconds: float) -> str:
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    ms = int((seconds - int(seconds)) * 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def generate_srt(segments: List[Dict]) -> str:
    lines = []
    for i, seg in enumerate(segments, 1):
        start = format_timestamp(seg["start"])
        end = format_timestamp(seg["end"])
        lines.append(f"{i}")
        lines.append(f"{start} --> {end}")
        lines.append(seg["text"].strip())
        lines.append("")
    return "\n".join(lines)


def generate_dual_srt(original: List[Dict], translated: List[Dict]) -> str:
    """Generate dual SRT with translated text on top and original below.
    Handles different segment counts (sentence-level translation vs word-level original).
    """
    lines = []
    for i, trans in enumerate(translated, 1):
        start = format_timestamp(trans["start"])
        end = format_timestamp(trans["end"])
        # Find matching original segments in this time range
        orig_texts = [s["text"].strip() for s in original
                      if s["start"] >= trans["start"] - 0.1 and s["end"] <= trans["end"] + 0.1]
        orig_combined = " ".join(orig_texts) if orig_texts else ""
        lines.append(f"{i}")
        lines.append(f"{start} --> {end}")
        lines.append(trans["text"].strip())
        if orig_combined:
            lines.append(f"<i>{orig_combined}</i>")
        lines.append("")
    return "\n".join(lines)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8899, reload=True,
                ws_ping_interval=30, ws_ping_timeout=300)
