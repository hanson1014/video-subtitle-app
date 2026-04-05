"""Local LLM translation using MLX — sentence-level translation with timestamp preservation."""

from typing import Dict, List, Tuple
import re

from mlx_lm import load, generate

SUPPORTED_LANGUAGES = {
    "zh-TW": "繁體中文",
    "zh-CN": "简体中文",
    "en": "English",
    "ja": "日本語",
    "ko": "한국어",
    "es": "Español",
    "fr": "Français",
    "de": "Deutsch",
    "pt": "Português",
    "vi": "Tiếng Việt",
    "th": "ไทย",
}

MODEL_NAME = "mlx-community/Qwen3.5-4B-4bit"

_model = None
_tokenizer = None


def load_model():
    global _model, _tokenizer
    if _model is None:
        print(f"Loading translation model: {MODEL_NAME}")
        _model, _tokenizer = load(MODEL_NAME)
        print("Model loaded.")
    return _model, _tokenizer


def _call_llm(prompt: str, max_tokens: int) -> str:
    model, tokenizer = load_model()

    if hasattr(tokenizer, "apply_chat_template"):
        messages = [{"role": "user", "content": prompt}]
        try:
            formatted = tokenizer.apply_chat_template(
                messages, tokenize=False, add_generation_prompt=True,
                enable_thinking=False,
            )
        except TypeError:
            formatted = tokenizer.apply_chat_template(
                messages, tokenize=False, add_generation_prompt=True,
            )
    else:
        formatted = prompt

    return generate(
        model,
        tokenizer,
        prompt=formatted,
        max_tokens=max_tokens,
    )


def _count_tokens(text: str) -> int:
    _, tokenizer = load_model()
    return len(tokenizer.encode(text))


def _merge_into_sentences(segments: List[Dict]) -> List[dict]:
    """Merge subtitle segments into complete sentences based on punctuation."""
    sentences = []
    current_segs = []

    for seg in segments:
        current_segs.append(seg)
        text = seg["text"].strip()
        # End of sentence if it ends with sentence-ending punctuation
        if text and text[-1] in ".!?。！？" or text.endswith('."') or text.endswith(".'"):
            sentences.append({
                "text": " ".join(s["text"].strip() for s in current_segs),
                "segments": current_segs,
                "start": current_segs[0]["start"],
                "end": current_segs[-1]["end"],
            })
            current_segs = []

    # Don't forget remaining segments
    if current_segs:
        sentences.append({
            "text": " ".join(s["text"].strip() for s in current_segs),
            "segments": current_segs,
            "start": current_segs[0]["start"],
            "end": current_segs[-1]["end"],
        })

    return sentences


def _distribute_translation(translation: str, original_segments: List[Dict]) -> List[Dict]:
    """Distribute a translated sentence back across original segment timestamps.

    Splits the translation proportionally based on original segment durations.
    """
    if len(original_segments) == 1:
        return [{"start": original_segments[0]["start"],
                 "end": original_segments[0]["end"],
                 "text": translation}]

    # Split translation into roughly equal parts by character count,
    # weighted by original segment duration
    total_duration = sum(s["end"] - s["start"] for s in original_segments)
    if total_duration == 0:
        total_duration = len(original_segments)

    # Try to split at natural break points (punctuation, spaces for CJK)
    chars = list(translation)
    total_chars = len(chars)

    result = []
    char_pos = 0

    for i, seg in enumerate(original_segments):
        seg_duration = seg["end"] - seg["start"]
        if i == len(original_segments) - 1:
            # Last segment gets the rest
            part = translation[char_pos:]
        else:
            # Proportional split
            ratio = seg_duration / total_duration if total_duration > 0 else 1 / len(original_segments)
            target_chars = max(1, int(total_chars * ratio))
            end_pos = min(char_pos + target_chars, total_chars)

            # Try to find a natural break point nearby (comma, space, etc.)
            best_break = end_pos
            search_range = min(5, total_chars - char_pos)
            for offset in range(search_range):
                check = end_pos + offset
                if 0 <= check < total_chars and translation[check] in "，、。；：！？ ,;:!? ":
                    best_break = check + 1
                    break
                check = end_pos - offset
                if 0 < check < total_chars and check > char_pos and translation[check] in "，、。；：！？ ,;:!? ":
                    best_break = check + 1
                    break

            part = translation[char_pos:best_break]
            char_pos = best_break

        result.append({
            "start": seg["start"],
            "end": seg["end"],
            "text": part.strip(),
        })

    return result


BATCH_SIZE = 30


def translate_segments(segments: List[Dict], target_lang: str) -> List[Dict]:
    """Translate segments: merge into sentences, translate, redistribute to original timestamps."""
    lang_name = SUPPORTED_LANGUAGES.get(target_lang, target_lang)

    # Step 1: Merge into sentences
    sentences = _merge_into_sentences(segments)
    print(f"Merged {len(segments)} segments into {len(sentences)} sentences")

    # Step 2: Translate sentences in batches
    translated_sentences = []
    num_batches = (len(sentences) + BATCH_SIZE - 1) // BATCH_SIZE

    for batch_start in range(0, len(sentences), BATCH_SIZE):
        batch = sentences[batch_start:batch_start + BATCH_SIZE]
        batch_num = batch_start // BATCH_SIZE + 1
        print(f"  Translating batch {batch_num}/{num_batches} ({len(batch)} sentences)...")

        lines = []
        for i, sent in enumerate(batch):
            lines.append(f"{i}|{sent['text']}")
        input_block = "\n".join(lines)

        prompt = f"""Translate these sentences to {lang_name}.

Rules:
- Each line has format: NUMBER|TEXT
- Output EXACTLY {len(batch)} lines, one translation per input line
- Output format: NUMBER|TRANSLATED_TEXT
- Do NOT skip, merge, or reorder lines

{input_block}"""

        prompt_tokens = _count_tokens(prompt)
        response = _call_llm(prompt, max_tokens=int(prompt_tokens * 2.5))

        # Parse response
        translated_map = {}
        for line in response.strip().split("\n"):
            line = line.strip()
            if "|" in line:
                parts = line.split("|", 1)
                try:
                    idx = int(parts[0].strip())
                    text = parts[1].strip()
                    if text:
                        translated_map[idx] = text
                except (ValueError, IndexError):
                    continue

        for i, sent in enumerate(batch):
            translated_sentences.append(
                translated_map.get(i, sent["text"])
            )

    # Step 3: Map translations to sentence-level timestamps,
    # splitting long subtitles at natural punctuation breaks
    result = []
    for sent_idx, sentence in enumerate(sentences):
        translation = translated_sentences[sent_idx].strip()
        duration = sentence["end"] - sentence["start"]

        if len(translation) <= MAX_SUBTITLE_CHARS:
            result.append({
                "start": sentence["start"],
                "end": sentence["end"],
                "text": translation,
            })
        else:
            # Split at natural Chinese/English punctuation
            parts = _split_long_subtitle(translation)
            total_chars = sum(len(p) for p in parts)
            t = sentence["start"]
            for i, part in enumerate(parts):
                ratio = len(part) / total_chars if total_chars > 0 else 1 / len(parts)
                part_duration = duration * ratio
                end_t = t + part_duration if i < len(parts) - 1 else sentence["end"]
                result.append({
                    "start": round(t, 3),
                    "end": round(end_t, 3),
                    "text": part,
                })
                t = end_t

    print(f"Output: {len(result)} translated segments")
    return result


# Max characters per subtitle line before splitting
MAX_SUBTITLE_CHARS = 30


def _split_long_subtitle(text: str) -> List[str]:
    """Split long subtitle text at natural punctuation breaks."""
    # Split at Chinese/English clause-level punctuation
    split_chars = "，、；。！？,;!?"
    parts = []
    current = ""

    for char in text:
        current += char
        if char in split_chars and len(current) >= 8:
            parts.append(current.strip())
            current = ""

    if current.strip():
        if parts and len(current.strip()) < 8:
            # Too short — merge with previous part
            parts[-1] += current.strip()
        else:
            parts.append(current.strip())

    # If still too long after splitting, just return as-is (don't cut mid-word)
    if len(parts) == 1 and len(parts[0]) > MAX_SUBTITLE_CHARS:
        # Try splitting at any comma-like character regardless of min length
        result = []
        curr = ""
        for char in text:
            curr += char
            if char in split_chars:
                result.append(curr.strip())
                curr = ""
        if curr.strip():
            if result:
                result[-1] += curr.strip()
            else:
                result.append(curr.strip())
        if len(result) > 1:
            return result

    return parts
