#!/usr/bin/env python3

import argparse
import json
import os
import shutil
import subprocess
import sys
import venv
from pathlib import Path


SUPPORTED_MODELS = [
    "tiny",
    "tiny.en",
    "base",
    "base.en",
    "small",
    "small.en",
    "medium",
    "medium.en",
    "large",
    "large-v1",
    "large-v2",
    "large-v3",
    "large-v3-turbo",
    "turbo",
]


def emit(kind, phase=None, message=None, fraction=None, payload=None):
    event = {"kind": kind}
    if phase is not None:
        event["phase"] = phase
    if message is not None:
        event["message"] = message
    if fraction is not None:
        event["fraction"] = fraction
    if payload is not None:
        event["payload"] = payload
    print("WFM_EVENT\t" + json.dumps(event), flush=True)


def pip_path(venv_dir: Path) -> Path:
    return venv_dir / "bin" / "pip"


def python_path(venv_dir: Path) -> Path:
    return venv_dir / "bin" / "python"


def import_whisper():
    import whisper
    from whisper.utils import get_writer

    return whisper, get_writer


def known_model_filename(model_id: str):
    try:
        whisper, _ = import_whisper()
        url = whisper._MODELS.get(model_id)
        if not url:
            return None
        return Path(url).name
    except Exception:
        return None


def inspect(args):
    ffmpeg = shutil.which("ffmpeg")
    env_python = python_path(Path(args.venv_dir))
    result = {
        "pythonPath": sys.executable,
        "ffmpegPath": ffmpeg,
        "whisperInstalled": False,
        "environmentPath": str(env_python),
        "models": [],
        "error": None,
    }

    installed = {}
    for model_id in SUPPORTED_MODELS:
        filename = known_model_filename(model_id)
        size = None
        is_installed = False
        if filename:
            model_path = Path(args.models_dir) / filename
            if model_path.exists():
                is_installed = True
                size = model_path.stat().st_size
        installed[model_id] = {"id": model_id, "installed": is_installed, "sizeBytes": size}

    try:
        import_whisper()
        result["whisperInstalled"] = env_python.exists()
    except Exception as exc:
        result["error"] = str(exc)

    result["models"] = [installed[model_id] for model_id in SUPPORTED_MODELS]
    print(json.dumps(result), flush=True)


def setup_environment(args):
    venv_dir = Path(args.venv_dir)
    models_dir = Path(args.models_dir)
    models_dir.mkdir(parents=True, exist_ok=True)

    emit("status", phase="preparing", message="Creating Python environment", fraction=0.05)
    builder = venv.EnvBuilder(with_pip=True, clear=False)
    builder.create(venv_dir)

    pip = pip_path(venv_dir)
    commands = [
        [str(pip), "install", "--upgrade", "pip", "wheel", "setuptools"],
        [str(pip), "install", "openai-whisper"],
    ]

    for index, command in enumerate(commands, start=1):
        emit("status", phase="installing", message="Installing Whisper dependencies", fraction=0.2 * index)
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in process.stdout or []:
            emit("status", phase="installing", message=line.strip() or "Installing dependencies")
        return_code = process.wait()
        if return_code != 0:
            emit("error", phase="failed", message=f"Dependency installation failed with exit code {return_code}.")
            sys.exit(return_code)

    emit("result", phase="ready", message="Managed environment is ready.")


def install_model(args):
    whisper, _ = import_whisper()
    models_dir = Path(args.models_dir)
    models_dir.mkdir(parents=True, exist_ok=True)
    emit("status", phase="downloading_model", message=f"Downloading model {args.model}", fraction=0.25)
    whisper.load_model(args.model, download_root=str(models_dir))
    emit("result", phase="ready", message=f"Model {args.model} is ready.")


def remove_model(args):
    model_file = known_model_filename(args.model)
    if not model_file:
        emit("error", phase="failed", message=f"Unknown model {args.model}.")
        sys.exit(2)
    path = Path(args.models_dir) / model_file
    if path.exists():
        path.unlink()
    emit("result", phase="ready", message=f"Removed model {args.model}.")


def transcribe(args):
    whisper, get_writer = import_whisper()
    input_path = Path(args.input)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    formats = [item for item in args.formats.split(",") if item]
    options = {"task": args.task}
    if args.language != "auto":
        options["language"] = args.language

    emit("status", phase="preparing", message="Validating input file", fraction=0.05)
    if not input_path.exists():
        emit("error", phase="failed", message="The selected file no longer exists.")
        sys.exit(2)

    emit("status", phase="loading_model", message=f"Loading model {args.model}", fraction=0.15)
    model = whisper.load_model(args.model, download_root=args.models_dir)

    emit("status", phase="transcribing", message="Running Whisper transcription", fraction=0.6)
    result = model.transcribe(str(input_path), **options)

    write_options = {"max_line_width": 50, "max_line_count": 2, "highlight_words": False}
    payload = {}

    emit("status", phase="writing_outputs", message="Writing transcript files", fraction=0.9)
    for format_name in formats:
        writer = get_writer(format_name, str(output_dir))
        options_for_writer = write_options if format_name == "vtt" else {}
        writer(result, str(input_path), options_for_writer)
        output_file = output_dir / f"{input_path.stem}.{format_name}"
        payload[format_name] = str(output_file)

    emit("result", phase="completed", message="Transcription completed.", payload=payload)


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    inspect_parser = subparsers.add_parser("inspect")
    inspect_parser.add_argument("--venv-dir", required=True)
    inspect_parser.add_argument("--models-dir", required=True)
    inspect_parser.set_defaults(func=inspect)

    setup_parser = subparsers.add_parser("setup-environment")
    setup_parser.add_argument("--venv-dir", required=True)
    setup_parser.add_argument("--models-dir", required=True)
    setup_parser.set_defaults(func=setup_environment)

    install_parser = subparsers.add_parser("install-model")
    install_parser.add_argument("--model", required=True)
    install_parser.add_argument("--models-dir", required=True)
    install_parser.set_defaults(func=install_model)

    remove_parser = subparsers.add_parser("remove-model")
    remove_parser.add_argument("--model", required=True)
    remove_parser.add_argument("--models-dir", required=True)
    remove_parser.set_defaults(func=remove_model)

    transcribe_parser = subparsers.add_parser("transcribe")
    transcribe_parser.add_argument("--input", required=True)
    transcribe_parser.add_argument("--model", required=True)
    transcribe_parser.add_argument("--task", required=True)
    transcribe_parser.add_argument("--language", required=True)
    transcribe_parser.add_argument("--output-dir", required=True)
    transcribe_parser.add_argument("--formats", required=True)
    transcribe_parser.add_argument("--models-dir", required=True)
    transcribe_parser.set_defaults(func=transcribe)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
