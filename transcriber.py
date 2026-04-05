"""MLX Whisper-based audio transcription with GPU acceleration on Apple Silicon."""

from typing import Dict, List

import mlx_whisper


def transcribe_audio(audio_path: str, model_size: str = "medium") -> List[Dict]:
    """Transcribe audio file using MLX Whisper (Apple GPU accelerated).

    Returns list of {"start": float, "end": float, "text": str}
    """
    model_map = {
        "tiny": "mlx-community/whisper-tiny-mlx",
        "base": "mlx-community/whisper-base-mlx-q4",
        "small": "mlx-community/whisper-small-mlx",
        "medium": "mlx-community/whisper-medium-mlx-q4",
        "large-v3": "mlx-community/whisper-large-v3-mlx",
    }

    model_name = model_map.get(model_size, model_map["medium"])

    result = mlx_whisper.transcribe(
        audio_path,
        path_or_hf_repo=model_name,
        word_timestamps=True,
        verbose=False,
    )

    segments = []
    for seg in result["segments"]:
        segments.append({
            "start": round(seg["start"], 3),
            "end": round(seg["end"], 3),
            "text": seg["text"].strip(),
        })

    return segments
