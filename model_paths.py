import os
from pathlib import Path


def _modelscope_cache() -> Path:
    return Path(os.getenv("MODELSCOPE_CACHE", "/root/.cache/modelscope"))


def _candidate_dirs(model_id: str, env_var: str, legacy_dir: str | None = None) -> list[Path]:
    candidates: list[Path] = []

    explicit = os.getenv(env_var)
    if explicit:
        candidates.append(Path(explicit))

    namespace, name = model_id.split("/", 1)
    root_from_env = _modelscope_cache()
    roots = [
        root_from_env,
        Path("/root/.cache/modelscope"),
        Path.home() / ".cache" / "modelscope",
    ]

    for root in roots:
        candidates.extend(
            [
                root / "hub" / "models" / namespace / name,
                root / "hub" / namespace / name,
                root / namespace / name,
                root / name,
            ]
        )

    if legacy_dir:
        candidates.append(Path(legacy_dir))

    seen: set[str] = set()
    unique: list[Path] = []
    for path in candidates:
        key = str(path)
        if key not in seen:
            unique.append(path)
            seen.add(key)
    return unique


def _resolve_model_dir(model_id: str, env_var: str, required_files: tuple[str, ...], legacy_dir: str | None = None) -> str:
    checked = []
    for path in _candidate_dirs(model_id, env_var, legacy_dir):
        checked.append(str(path))
        if path.is_dir() and any((path / required_file).exists() for required_file in required_files):
            return str(path)

    raise FileNotFoundError(
        f"Cannot find {model_id}. Set {env_var} to the model directory, or mount the ModelScope cache "
        f"to {root_from_env}. Checked: {', '.join(checked)}"
    )


def resolve_tts_model_dir(model_dir: str | None = None) -> str:
    if model_dir:
        return model_dir
    return _resolve_model_dir(
        "FunAudioLLM/Fun-CosyVoice3-0.5B-2512",
        "MODEL_DIR",
        ("cosyvoice3.yaml", "cosyvoice2.yaml", "cosyvoice.yaml"),
        "pretrained_models/Fun-CosyVoice3-0.5B",
    )


def resolve_asr_model_dir() -> str:
    return _resolve_model_dir(
        "FunAudioLLM/Fun-ASR-Nano-2512",
        "ASR_MODEL_DIR",
        ("configuration.json", "config.yaml", "config.json", "model.pt", "model.py"),
    )
