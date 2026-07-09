#!/usr/bin/env python3
"""Probe an OpenAI-compatible LLM gateway (LiteLLM / vLLM): models + chat.

Reads from repo root `.env` (same loader as ocr-api):
  VLLM_BASE_URL, VLLM_API_KEY, VLLM_MODEL_NAME, VLLM_REASONING_EFFORT
  (falls back to LLM_BASE_URL / LLM_API_KEY)

Requires: pip install requests

Usage:
  python scripts/inspect_llm_endpoint.py
  python scripts/inspect_llm_endpoint.py --all-models
  python scripts/inspect_llm_endpoint.py --skip-embeddings
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path

import requests

DEFAULT_ROOT_URL = "http://192.168.2.134:31180"


@dataclass(frozen=True)
class EndpointConfig:
    api_base: str  # e.g. http://host:31180/v1
    root_url: str  # e.g. http://host:31180
    api_key: str
    model_name: str | None
    reasoning_effort: str | None


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _load_root_dotenv() -> None:
    env_file = _repo_root() / ".env"
    if not env_file.is_file():
        return
    for raw in env_file.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def _normalize_urls(raw_base: str) -> tuple[str, str]:
    """Return (api_base with /v1, root without /v1)."""
    base = raw_base.rstrip("/")
    if base.endswith("/v1"):
        return base, base[:-3]
    return f"{base}/v1", base


def _resolve_config(
    base_url: str | None,
    api_key: str | None,
    model_name: str | None,
    reasoning_effort: str | None,
) -> EndpointConfig:
    raw_base = (
        base_url
        or os.environ.get("VLLM_BASE_URL")
        or os.environ.get("LLM_BASE_URL")
        or DEFAULT_ROOT_URL
    )
    api_base, root_url = _normalize_urls(raw_base)
    key = api_key or os.environ.get("VLLM_API_KEY") or os.environ.get("LLM_API_KEY")
    if not key:
        key = input("API key: ").strip()
    if not key:
        print("An API key is required.", file=sys.stderr)
        sys.exit(1)

    model = model_name or os.environ.get("VLLM_MODEL_NAME")
    effort = reasoning_effort or os.environ.get("VLLM_REASONING_EFFORT")
    return EndpointConfig(
        api_base=api_base,
        root_url=root_url,
        api_key=key,
        model_name=model or None,
        reasoning_effort=effort or None,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Inspect an OpenAI-compatible LLM endpoint")
    parser.add_argument("--base-url", default=None, help="Override VLLM_BASE_URL / LLM_BASE_URL")
    parser.add_argument("--api-key", default=None, help="Override VLLM_API_KEY / LLM_API_KEY")
    parser.add_argument("--model", default=None, help="Override VLLM_MODEL_NAME")
    parser.add_argument(
        "--reasoning-effort",
        default=None,
        help="Override VLLM_REASONING_EFFORT (e.g. low, medium, high)",
    )
    parser.add_argument(
        "--all-models",
        action="store_true",
        help="Chat-test every listed model (default: only VLLM_MODEL_NAME when set)",
    )
    parser.add_argument(
        "--embeddings",
        action="store_true",
        help="Also probe embedding endpoints (off by default when VLLM_MODEL_NAME is set)",
    )
    parser.add_argument(
        "--skip-embeddings",
        action="store_true",
        help="Skip embedding probes",
    )
    parser.add_argument("--skip-chat", action="store_true", help="Skip chat completion")
    return parser.parse_args()


def auth_headers(api_key: str) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }


def check_models(cfg: EndpointConfig) -> list[str]:
    headers = auth_headers(cfg.api_key)
    paths = (
        f"{cfg.api_base}/models",
        f"{cfg.root_url}/v1/models",
        f"{cfg.root_url}/models",
        f"{cfg.root_url}/api/v1/models",
    )
    print(f"\n--- Checking for models (api_base={cfg.api_base}) ---")

    seen: set[str] = set()
    for url in paths:
        try:
            print(f"Trying GET {url} ...")
            response = requests.get(url, headers=headers, timeout=10)
            if response.status_code == 200:
                data = response.json()
                print("[OK] Models:")
                if "data" in data:
                    for item in data["data"]:
                        model_id = item.get("id", "unknown")
                        if model_id not in seen:
                            seen.add(model_id)
                            print(f"   - {model_id}")
                    return list(seen)
                print(json.dumps(data, indent=2))
                return []
            if response.status_code == 401:
                body = response.text[:300]
                print(f"[FAIL] 401 Unauthorized — {body}")
                if "sk-" in body.lower():
                    print("   Hint: LiteLLM expects a virtual key starting with sk-")
                return []
            print(f"[FAIL] HTTP {response.status_code}: {response.text[:200]}")
        except requests.RequestException as exc:
            print(f"[FAIL] {exc}")

    return []


def is_embedding_model(model_id: str) -> bool:
    return "embed" in model_id.lower()


def test_chat(cfg: EndpointConfig, model_name: str) -> None:
    url = f"{cfg.api_base}/chat/completions"
    payload: dict[str, object] = {
        "model": model_name,
        "messages": [{"role": "user", "content": "Hello, are you working? Reply in one short sentence."}],
        "max_tokens": 100,
    }
    if cfg.reasoning_effort:
        payload["reasoning_effort"] = cfg.reasoning_effort

    print(f"\n--- Chat completion: {model_name} ---")
    if cfg.reasoning_effort:
        print(f"   reasoning_effort={cfg.reasoning_effort}")
    print(f"POST {url}")
    try:
        response = requests.post(
            url, headers=auth_headers(cfg.api_key), json=payload, timeout=120
        )
        if response.status_code == 200:
            print("[OK] Response:")
            print(json.dumps(response.json(), indent=2))
        else:
            print(f"[FAIL] HTTP {response.status_code}")
            print(response.text)
    except requests.RequestException as exc:
        print(f"[FAIL] {exc}")


def test_embedding(cfg: EndpointConfig, model_name: str) -> None:
    url = f"{cfg.api_base}/embeddings"
    payload = {
        "model": model_name,
        "input": "The food was delicious and the waiter...",
    }

    print(f"\n--- Embeddings: {model_name} ---")
    print(f"POST {url}")
    try:
        response = requests.post(
            url, headers=auth_headers(cfg.api_key), json=payload, timeout=30
        )
        if response.status_code == 200:
            data = response.json()
            if (
                "data" in data
                and data["data"]
                and "embedding" in data["data"][0]
            ):
                vec = data["data"][0]["embedding"]
                print(f"[OK] vector length={len(vec)}, first 5={vec[:5]}")
            else:
                print("[OK] Response:")
                print(json.dumps(data, indent=2))
        else:
            print(f"[FAIL] HTTP {response.status_code}")
            print(response.text)
    except requests.RequestException as exc:
        print(f"[FAIL] {exc}")


def detect_provider(root_url: str) -> None:
    print(f"\n--- Detecting provider at {root_url} ---")
    try:
        resp = requests.get(root_url, timeout=5)
        print(f"GET / status: {resp.status_code}")
        snippet = resp.text[:100].replace("\n", " ")
        print(f"GET / content: {snippet}...")
        if "Ollama is running" in resp.text:
            print("Detected: Ollama")
        elif "Swagger UI" in resp.text or "FastAPI" in resp.text:
            print("Detected: FastAPI-based (LiteLLM / vLLM / LocalAI)")

        health = requests.get(f"{root_url}/health", timeout=5)
        if health.status_code == 200:
            print(f"GET /health: {health.json()}")
    except requests.RequestException as exc:
        print(f"Could not connect to root: {exc}")


def main() -> None:
    _load_root_dotenv()
    args = parse_args()
    cfg = _resolve_config(
        args.base_url, args.api_key, args.model, args.reasoning_effort
    )

    print("LLM Endpoint Inspector")
    print("----------------------")
    print(f"api_base: {cfg.api_base}")
    if cfg.model_name:
        print(f"configured model: {cfg.model_name}")
    detect_provider(cfg.root_url)

    models = check_models(cfg)

    run_embeddings = args.embeddings and not args.skip_embeddings
    if not args.skip_embeddings and not cfg.model_name:
        run_embeddings = True

    if run_embeddings:
        print("\n--- Hunting for embedding models ---")
        targets = models or ["text-embedding-ada-002"]
        for model in targets:
            test_embedding(cfg, model)

    if args.skip_chat:
        return

    if cfg.model_name and not args.all_models:
        test_chat(cfg, cfg.model_name)
        return

    chat_targets = [m for m in models if not is_embedding_model(m)]
    if chat_targets:
        for model in chat_targets:
            test_chat(cfg, model)
    elif cfg.model_name:
        test_chat(cfg, cfg.model_name)
    else:
        print("\nCould not list models and no VLLM_MODEL_NAME set.")
        manual = input("Try a manual model name? [y/N]: ").strip()
        if manual.lower() == "y":
            name = input("Model name: ").strip()
            if name:
                test_chat(cfg, name)


if __name__ == "__main__":
    main()
