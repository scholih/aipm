# Sidecar Development Guide

Building the Python sidecar system for Reflex BV. This guide is for the Tech Developer persona who will build the core sidecar and create targeted versions for other personas.

---

## Part 1: Core Sidecar Architecture

The sidecar is a set of standalone Python scripts invoked by Claude Code or Copilot via `uv run`. Each script handles one domain (fetching, LLM, data, diagrams, PDF). They share a `core/` package for configuration, Ollama access, and output formatting.

### Directory Layout

```
shared/sidecar/
├── pyproject.toml
├── core/
│   ├── __init__.py
│   ├── config.py           # Load ~/.aipm/config.toml, env var fallbacks
│   ├── ollama_client.py    # Thin wrapper around Ollama API
│   └── output.py           # JSON / markdown / plain output formatting
├── fetch.py                # Web fetching (httpx + BeautifulSoup)
├── llm.py                  # Local LLM tasks via Ollama
├── data.py                 # DuckDB queries on CSV/Excel/Parquet
├── diagram.py              # Mermaid, Graphviz, simple charts
└── pdf.py                  # Markdown/HTML to PDF
```

### Design Principles

1. **No frameworks for CLI.** `argparse` only. These are scripts, not applications.
2. **Every script is independently runnable.** No shared state between scripts.
3. **`uv run` is the only entry point.** Never assume a venv is activated.
4. **Output goes to stdout.** Errors go to stderr. Exit codes are meaningful.
5. **Config is optional.** Every setting has a sensible default.
6. **Type hints everywhere.** Every function signature, every return type.

### Dependencies (pyproject.toml)

```toml
[project]
name = "reflex-sidecar"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = [
    "httpx>=0.27",
    "beautifulsoup4>=4.12",
    "lxml>=5.0",
    "ollama>=0.4",
    "duckdb>=1.0",
    "pandas>=2.2",
    "graphviz>=0.20",
    "tomli>=2.0; python_version < '3.11'",
]

[project.optional-dependencies]
pdf = ["weasyprint>=62"]
```

---

## Part 2: Building Each Core Script

### 2.1 The Config System (Build First)

Before any script, build `core/config.py`. Everything else depends on it.

**Config file location:** `~/.aipm/config.toml`

```toml
[ollama]
host = "localhost"
port = 11434

[models]
fast = "llama3.2:3b"
default = "llama3.1:8b"
deep = "llama3.1:70b"
code = "deepseek-coder-v2:16b"
extract = "mistral:7b"
embed = "nomic-embed-text"

[sidecar]
path = "~/.claude/sidecar"

[knowledge_base]
vault_path = "~/reflex-kb"
```

#### core/config.py

```python
"""
Configuration loader.

Priority: env vars > config file > defaults.
Env var format: AIPM_OLLAMA_HOST, AIPM_MODELS_FAST, etc.
"""
from __future__ import annotations

import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

if sys.version_info >= (3, 11):
    import tomllib
else:
    import tomli as tomllib


@dataclass(frozen=True)
class OllamaConfig:
    host: str = "localhost"
    port: int = 11434

    @property
    def base_url(self) -> str:
        return f"http://{self.host}:{self.port}"


@dataclass(frozen=True)
class ModelConfig:
    fast: str = "llama3.2:3b"
    default: str = "llama3.1:8b"
    deep: str = "llama3.1:70b"
    code: str = "deepseek-coder-v2:16b"
    extract: str = "mistral:7b"
    embed: str = "nomic-embed-text"

    def get(self, tier: str) -> str:
        """Return model name for a tier, raising ValueError for unknown tiers."""
        if not hasattr(self, tier):
            valid = ", ".join(f.__name__ for f in self.__dataclass_fields__)
            raise ValueError(f"Unknown model tier '{tier}'. Valid: {valid}")
        return getattr(self, tier)


@dataclass(frozen=True)
class KnowledgeBaseConfig:
    vault_path: Path = field(default_factory=lambda: Path.home() / "reflex-kb")


@dataclass(frozen=True)
class Config:
    ollama: OllamaConfig = field(default_factory=OllamaConfig)
    models: ModelConfig = field(default_factory=ModelConfig)
    kb: KnowledgeBaseConfig = field(default_factory=KnowledgeBaseConfig)


def _env(section: str, key: str) -> str | None:
    """Check for AIPM_{SECTION}_{KEY} environment variable."""
    return os.environ.get(f"AIPM_{section.upper()}_{key.upper()}")


def _config_path() -> Path:
    """Return config file path. Windows: %USERPROFILE%\\.aipm\\config.toml"""
    return Path.home() / ".aipm" / "config.toml"


def load_config() -> Config:
    """Load config from file with env var overrides."""
    raw: dict = {}
    config_file = _config_path()

    if config_file.exists():
        with open(config_file, "rb") as f:
            raw = tomllib.load(f)

    # Ollama
    ollama_raw = raw.get("ollama", {})
    ollama = OllamaConfig(
        host=_env("ollama", "host") or ollama_raw.get("host", "localhost"),
        port=int(_env("ollama", "port") or ollama_raw.get("port", 11434)),
    )

    # Models
    models_raw = raw.get("models", {})
    model_defaults = ModelConfig()
    models = ModelConfig(**{
        tier: _env("models", tier) or models_raw.get(tier, getattr(model_defaults, tier))
        for tier in model_defaults.__dataclass_fields__
    })

    # Knowledge base
    kb_raw = raw.get("knowledge_base", {})
    vault = _env("knowledge_base", "vault_path") or kb_raw.get("vault_path")
    kb = KnowledgeBaseConfig(
        vault_path=Path(vault).expanduser() if vault else Path.home() / "reflex-kb"
    )

    return Config(ollama=ollama, models=models, kb=kb)


# Module-level singleton — import and use directly
config = load_config()
```

#### core/ollama_client.py

```python
"""Thin wrapper around the Ollama Python client."""
from __future__ import annotations

from ollama import Client

from core.config import config


def get_client() -> Client:
    """Return an Ollama client configured from config."""
    return Client(host=config.ollama.base_url)


def generate(prompt: str, model: str | None = None, system: str = "") -> str:
    """Generate a completion. Returns the response text."""
    model = model or config.models.default
    client = get_client()
    response = client.generate(model=model, prompt=prompt, system=system)
    return response["response"]


def chat(
    messages: list[dict[str, str]],
    model: str | None = None,
) -> str:
    """Chat completion. Returns the assistant's message content."""
    model = model or config.models.default
    client = get_client()
    response = client.chat(model=model, messages=messages)
    return response["message"]["content"]


def embed(text: str) -> list[float]:
    """Generate embeddings for text."""
    client = get_client()
    response = client.embed(model=config.models.embed, input=text)
    return response["embeddings"][0]


def is_available() -> bool:
    """Check if Ollama is reachable."""
    try:
        client = get_client()
        client.list()
        return True
    except Exception:
        return False
```

#### core/output.py

```python
"""Consistent output formatting for all sidecar scripts."""
from __future__ import annotations

import json
import sys
from enum import Enum
from typing import Any


class Format(Enum):
    JSON = "json"
    MARKDOWN = "markdown"
    PLAIN = "plain"


def emit(data: Any, fmt: Format = Format.PLAIN) -> None:
    """Write data to stdout in the requested format."""
    if fmt == Format.JSON:
        if isinstance(data, str):
            data = {"result": data}
        print(json.dumps(data, indent=2, default=str, ensure_ascii=False))
    elif fmt == Format.MARKDOWN:
        print(str(data))
    else:
        print(str(data))


def error(message: str, exit_code: int = 1) -> None:
    """Write error to stderr and exit."""
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(exit_code)


def warn(message: str) -> None:
    """Write warning to stderr (does not exit)."""
    print(f"WARN: {message}", file=sys.stderr)
```

#### core/\_\_init\_\_.py

```python
"""Sidecar core utilities."""
from core.config import config
from core.output import Format, emit, error

__all__ = ["config", "emit", "error", "Format"]
```

---

### 2.2 fetch.py — Web Fetching

**Purpose:** Fetch web pages and return clean text or raw HTML. Handles encoding, SSL quirks, and batch fetching. Used whenever Claude would otherwise read a URL into its context window.

**When to use:** Competitor research, documentation lookups, scraping product pages.

#### CLI Interface

```
fetch.py <url>                  Fetch URL, return clean text
fetch.py <url> --raw            Return raw HTML
fetch.py <url> --json           Return JSON with metadata (title, text, links)
fetch.py --batch <urls.txt>     Fetch all URLs from file (one per line)
fetch.py --batch <urls.txt> --json  Batch fetch with JSON output
```

#### Implementation

```python
#!/usr/bin/env python3
"""Fetch web pages and return clean text or raw HTML."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import httpx
from bs4 import BeautifulSoup


def fetch_url(url: str, timeout: float = 30.0) -> httpx.Response:
    """Fetch a URL with sensible defaults for Windows environments."""
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        )
    }
    # verify=False is a last resort for corporate proxies with MITM certs.
    # Prefer installing the corporate CA cert into the system trust store.
    return httpx.get(url, headers=headers, timeout=timeout, follow_redirects=True)


def extract_text(html: str) -> str:
    """Strip HTML and return readable text."""
    soup = BeautifulSoup(html, "lxml")

    # Remove script, style, nav, footer
    for tag in soup(["script", "style", "nav", "footer", "header", "aside"]):
        tag.decompose()

    text = soup.get_text(separator="\n", strip=True)
    # Collapse multiple blank lines
    lines = [line for line in text.splitlines() if line.strip()]
    return "\n".join(lines)


def extract_metadata(html: str, url: str) -> dict:
    """Extract structured metadata from HTML."""
    soup = BeautifulSoup(html, "lxml")
    title = soup.title.string.strip() if soup.title and soup.title.string else ""
    text = extract_text(html)
    links = [
        {"text": a.get_text(strip=True), "href": a.get("href", "")}
        for a in soup.find_all("a", href=True)
        if a.get("href", "").startswith("http")
    ][:50]  # Cap at 50 links
    return {
        "url": url,
        "title": title,
        "text": text[:5000],  # First 5000 chars
        "text_length": len(text),
        "link_count": len(links),
        "links": links,
    }


def fetch_single(url: str, raw: bool = False, as_json: bool = False) -> str:
    """Fetch a single URL and return formatted output."""
    response = fetch_url(url)
    response.raise_for_status()
    html = response.text

    if raw:
        return html
    if as_json:
        return json.dumps(extract_metadata(html, url), indent=2, ensure_ascii=False)
    return extract_text(html)


def fetch_batch(urls_file: Path, as_json: bool = False) -> str:
    """Fetch multiple URLs from a file."""
    urls = [
        line.strip()
        for line in urls_file.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    ]
    results: list[dict] = []

    for url in urls:
        try:
            response = fetch_url(url)
            response.raise_for_status()
            if as_json:
                results.append(extract_metadata(response.text, url))
            else:
                text = extract_text(response.text)
                results.append({"url": url, "text": text[:3000], "status": "ok"})
        except Exception as e:
            results.append({"url": url, "error": str(e), "status": "error"})

    return json.dumps(results, indent=2, ensure_ascii=False)


def main() -> None:
    parser = argparse.ArgumentParser(description="Fetch web pages")
    parser.add_argument("url", nargs="?", help="URL to fetch")
    parser.add_argument("--raw", action="store_true", help="Return raw HTML")
    parser.add_argument("--json", action="store_true", dest="as_json",
                        help="Return JSON with metadata")
    parser.add_argument("--batch", type=Path, help="File with URLs (one per line)")

    args = parser.parse_args()

    if args.batch:
        if not args.batch.exists():
            print(f"ERROR: File not found: {args.batch}", file=sys.stderr)
            sys.exit(1)
        print(fetch_batch(args.batch, args.as_json))
    elif args.url:
        try:
            print(fetch_single(args.url, args.raw, args.as_json))
        except httpx.HTTPStatusError as e:
            print(f"ERROR: HTTP {e.response.status_code} for {args.url}",
                  file=sys.stderr)
            sys.exit(1)
        except httpx.ConnectError as e:
            print(f"ERROR: Connection failed for {args.url}: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
```

**Windows Tips:**
- Corporate proxies often use MITM certificates. If you get SSL errors, set `REQUESTS_CA_BUNDLE` or `SSL_CERT_FILE` to the corporate CA bundle path.
- Encoding issues are common. `httpx` handles most cases, but some pages serve invalid encodings. The `lxml` parser in BeautifulSoup is more forgiving than `html.parser`.
- If `lxml` fails to install, fall back to `html.parser` (built-in, slower but no C dependency).

---

### 2.3 llm.py — Local LLM Tasks

**Purpose:** Run LLM tasks locally via Ollama instead of using Claude API tokens. Handles model selection, prompt construction, and output parsing.

**When to use:** Summarization, classification, structured extraction, code review, freeform questions.

#### CLI Interface

```
llm.py summarize <file>                          Summarize a file
llm.py extract <file> --schema "f1,f2,f3"        Extract structured JSON
llm.py classify <file> --labels "a,b,c"          Classify text
llm.py review <file>                              Code review
llm.py ask "question" --context <file>            Freeform question
      --model fast|default|deep|code|extract      Override model tier
      --json                                      Force JSON output
```

#### Model Selection Logic

| Command | Default Tier | Why |
|---------|-------------|-----|
| summarize | default (8b) | Good balance of quality and speed |
| extract | extract (mistral:7b) | Mistral excels at structured JSON output |
| classify | fast (3b) | Simple task, speed matters |
| review | code (deepseek-coder-v2:16b) | Code-specific model |
| ask | default (8b) | General purpose |

#### Implementation

```python
#!/usr/bin/env python3
"""Local LLM tasks via Ollama."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from core.config import config
from core.ollama_client import generate, is_available


# Default model tier per command
COMMAND_TIERS: dict[str, str] = {
    "summarize": "default",
    "extract": "extract",
    "classify": "fast",
    "review": "code",
    "ask": "default",
}

SYSTEM_PROMPTS: dict[str, str] = {
    "summarize": (
        "You are a concise summarizer. Provide a clear summary of the input text. "
        "Use bullet points for key takeaways. Keep it under 500 words."
    ),
    "extract": (
        "You are a data extraction engine. Extract the requested fields from the "
        "input text and return ONLY valid JSON. No explanations, no markdown fences."
    ),
    "classify": (
        "You are a text classifier. Classify the input into exactly one of the "
        "provided labels. Return ONLY the label, nothing else."
    ),
    "review": (
        "You are a senior code reviewer. Review the code for bugs, security issues, "
        "performance problems, and style. Be specific and actionable. "
        "Format: list issues by severity (critical, warning, suggestion)."
    ),
    "ask": "You are a helpful assistant. Answer the question based on the provided context.",
}


def read_input(file_path: Path) -> str:
    """Read a file, handling common Windows encoding issues."""
    for encoding in ("utf-8", "utf-8-sig", "cp1252", "latin-1"):
        try:
            return file_path.read_text(encoding=encoding)
        except (UnicodeDecodeError, UnicodeError):
            continue
    raise ValueError(f"Cannot decode {file_path} with any known encoding")


def resolve_model(command: str, override: str | None) -> str:
    """Resolve the Ollama model to use."""
    if override:
        return config.models.get(override)
    tier = COMMAND_TIERS[command]
    return config.models.get(tier)


def cmd_summarize(file_path: Path, model: str) -> str:
    """Summarize a file."""
    text = read_input(file_path)
    # Truncate to avoid overwhelming small models
    if len(text) > 15000:
        text = text[:15000] + "\n\n[... truncated ...]"
    return generate(
        prompt=f"Summarize the following text:\n\n{text}",
        model=model,
        system=SYSTEM_PROMPTS["summarize"],
    )


def cmd_extract(file_path: Path, schema: str, model: str) -> str:
    """Extract structured data from a file."""
    text = read_input(file_path)
    fields = [f.strip() for f in schema.split(",")]
    prompt = (
        f"Extract these fields from the text: {json.dumps(fields)}\n\n"
        f"Return a JSON object with these keys.\n\nText:\n{text[:10000]}"
    )
    result = generate(prompt=prompt, model=model, system=SYSTEM_PROMPTS["extract"])
    # Try to parse and re-format as clean JSON
    try:
        parsed = json.loads(result)
        return json.dumps(parsed, indent=2, ensure_ascii=False)
    except json.JSONDecodeError:
        return result


def cmd_classify(file_path: Path, labels: str, model: str) -> str:
    """Classify text into one of the given labels."""
    text = read_input(file_path)
    label_list = [lb.strip() for lb in labels.split(",")]
    prompt = (
        f"Classify this text into exactly one of these labels: {label_list}\n\n"
        f"Text:\n{text[:5000]}\n\nLabel:"
    )
    return generate(
        prompt=prompt, model=model, system=SYSTEM_PROMPTS["classify"]
    ).strip()


def cmd_review(file_path: Path, model: str) -> str:
    """Review code in a file."""
    code = read_input(file_path)
    prompt = f"Review this code:\n\n```\n{code}\n```"
    return generate(prompt=prompt, model=model, system=SYSTEM_PROMPTS["review"])


def cmd_ask(question: str, context_file: Path | None, model: str) -> str:
    """Answer a freeform question, optionally with file context."""
    prompt = question
    if context_file:
        context = read_input(context_file)
        prompt = f"Context:\n{context[:10000]}\n\nQuestion: {question}"
    return generate(prompt=prompt, model=model, system=SYSTEM_PROMPTS["ask"])


def main() -> None:
    parser = argparse.ArgumentParser(description="Local LLM tasks via Ollama")
    parser.add_argument("--model", choices=["fast", "default", "deep", "code", "extract"],
                        help="Model tier override")

    sub = parser.add_subparsers(dest="command", required=True)

    # summarize
    p_sum = sub.add_parser("summarize", help="Summarize a file")
    p_sum.add_argument("file", type=Path)

    # extract
    p_ext = sub.add_parser("extract", help="Extract structured data")
    p_ext.add_argument("file", type=Path)
    p_ext.add_argument("--schema", required=True, help="Comma-separated field names")

    # classify
    p_cls = sub.add_parser("classify", help="Classify text")
    p_cls.add_argument("file", type=Path)
    p_cls.add_argument("--labels", required=True, help="Comma-separated labels")

    # review
    p_rev = sub.add_parser("review", help="Code review")
    p_rev.add_argument("file", type=Path)

    # ask
    p_ask = sub.add_parser("ask", help="Freeform question")
    p_ask.add_argument("question", help="The question to ask")
    p_ask.add_argument("--context", type=Path, dest="context_file",
                       help="File to use as context")

    args = parser.parse_args()

    if not is_available():
        print("ERROR: Ollama is not running. Start it with: ollama serve",
              file=sys.stderr)
        sys.exit(1)

    model = resolve_model(args.command, args.model)

    if args.command == "summarize":
        print(cmd_summarize(args.file, model))
    elif args.command == "extract":
        print(cmd_extract(args.file, args.schema, model))
    elif args.command == "classify":
        print(cmd_classify(args.file, args.labels, model))
    elif args.command == "review":
        print(cmd_review(args.file, model))
    elif args.command == "ask":
        print(cmd_ask(args.question, args.context_file, model))


if __name__ == "__main__":
    main()
```

**Windows Tips:**
- File encoding: Windows files often use `cp1252` or `utf-8-sig` (with BOM). The `read_input` function tries multiple encodings.
- Path separators: Use `pathlib.Path` everywhere. Never hardcode `/` or `\\`.

---

### 2.4 data.py — Data Analysis

**Purpose:** Query CSV, Excel, and Parquet files with SQL using DuckDB. Inspect schema, profile data. Keeps large datasets out of the Claude context window.

**When to use:** Any data analysis task. DuckDB auto-detects file formats and handles CSVs with headers, Excel sheets, and Parquet natively.

#### CLI Interface

```
data.py query "SELECT * FROM 'sales.csv' LIMIT 10"     Run SQL query
data.py query "SQL" sales.csv                           Query with explicit file
data.py inspect <file>                                  Schema, row count, sample
data.py profile <file>                                  Statistical profile
      --json                                            JSON output
```

#### Implementation

```python
#!/usr/bin/env python3
"""Data analysis with DuckDB."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import duckdb
import pandas as pd


def get_table_ref(file_path: Path) -> str:
    """Return a DuckDB-compatible table reference for a file path.

    DuckDB reads CSV, Parquet, and JSON directly from file paths.
    Excel requires the spatial extension or read_csv workaround.
    """
    suffix = file_path.suffix.lower()
    # On Windows, backslashes in paths must be escaped or use forward slashes
    path_str = str(file_path).replace("\\", "/")

    if suffix in (".csv", ".tsv"):
        return f"read_csv_auto('{path_str}')"
    elif suffix == ".parquet":
        return f"read_parquet('{path_str}')"
    elif suffix in (".json", ".jsonl", ".ndjson"):
        return f"read_json_auto('{path_str}')"
    elif suffix in (".xlsx", ".xls"):
        # DuckDB can read Excel via the spatial extension
        return f"st_read('{path_str}')"
    else:
        # Try as CSV
        return f"read_csv_auto('{path_str}')"


def cmd_query(sql: str, file_path: Path | None, as_json: bool) -> None:
    """Execute a SQL query."""
    con = duckdb.connect()

    # If a file is provided, register it as a table named 'data'
    if file_path:
        ref = get_table_ref(file_path)
        con.execute(f"CREATE TABLE data AS SELECT * FROM {ref}")
        # Also allow using the filename directly in SQL
        con.execute(f"CREATE VIEW '{file_path.name}' AS SELECT * FROM data")

    try:
        # For Excel support
        con.execute("INSTALL spatial; LOAD spatial;")
    except Exception:
        pass  # Extension may already be installed or not needed

    result = con.execute(sql)
    df = result.fetchdf()

    if as_json:
        print(df.to_json(orient="records", indent=2, force_ascii=False))
    else:
        # Use pandas' string formatting for nice table output
        with pd.option_context("display.max_columns", None, "display.width", 120,
                               "display.max_rows", 100):
            print(df.to_string(index=False))


def cmd_inspect(file_path: Path, as_json: bool) -> None:
    """Show schema, row count, and sample data."""
    con = duckdb.connect()
    ref = get_table_ref(file_path)

    try:
        con.execute("INSTALL spatial; LOAD spatial;")
    except Exception:
        pass

    # Row count
    row_count = con.execute(f"SELECT COUNT(*) FROM {ref}").fetchone()[0]

    # Schema
    schema_df = con.execute(f"DESCRIBE SELECT * FROM {ref}").fetchdf()
    columns = [
        {"name": row["column_name"], "type": row["column_type"], "nullable": row["null"]}
        for _, row in schema_df.iterrows()
    ]

    # Sample (first 5 rows)
    sample_df = con.execute(f"SELECT * FROM {ref} LIMIT 5").fetchdf()

    if as_json:
        print(json.dumps({
            "file": str(file_path),
            "rows": row_count,
            "columns": columns,
            "sample": json.loads(sample_df.to_json(orient="records", force_ascii=False)),
        }, indent=2, ensure_ascii=False))
    else:
        print(f"File:    {file_path}")
        print(f"Rows:    {row_count:,}")
        print(f"Columns: {len(columns)}")
        print()
        print("Schema:")
        for col in columns:
            nullable = "NULL" if col["nullable"] == "YES" else "NOT NULL"
            print(f"  {col['name']:<30} {col['type']:<15} {nullable}")
        print()
        print("Sample (first 5 rows):")
        with pd.option_context("display.max_columns", None, "display.width", 120):
            print(sample_df.to_string(index=False))


def cmd_profile(file_path: Path, as_json: bool) -> None:
    """Statistical profile: min, max, mean, nulls per column."""
    con = duckdb.connect()
    ref = get_table_ref(file_path)

    try:
        con.execute("INSTALL spatial; LOAD spatial;")
    except Exception:
        pass

    schema_df = con.execute(f"DESCRIBE SELECT * FROM {ref}").fetchdf()
    profiles: list[dict] = []

    for _, row in schema_df.iterrows():
        col_name = row["column_name"]
        col_type = row["column_type"]
        # Quote column names to handle spaces and reserved words
        qcol = f'"{col_name}"'

        profile: dict = {"column": col_name, "type": col_type}

        null_count = con.execute(
            f"SELECT COUNT(*) FILTER (WHERE {qcol} IS NULL) FROM {ref}"
        ).fetchone()[0]
        total = con.execute(f"SELECT COUNT(*) FROM {ref}").fetchone()[0]
        profile["nulls"] = null_count
        profile["null_pct"] = round(null_count / total * 100, 1) if total > 0 else 0

        # Numeric stats
        if any(t in col_type.upper() for t in
               ("INT", "FLOAT", "DOUBLE", "DECIMAL", "NUMERIC", "BIGINT", "SMALLINT")):
            stats = con.execute(f"""
                SELECT
                    MIN({qcol}) as min_val,
                    MAX({qcol}) as max_val,
                    AVG({qcol}) as mean_val,
                    STDDEV({qcol}) as std_val,
                    MEDIAN({qcol}) as median_val
                FROM {ref}
            """).fetchone()
            profile.update({
                "min": stats[0], "max": stats[1],
                "mean": round(stats[2], 4) if stats[2] else None,
                "std": round(stats[3], 4) if stats[3] else None,
                "median": stats[4],
            })
        # String stats
        elif "VARCHAR" in col_type.upper() or "TEXT" in col_type.upper():
            distinct = con.execute(
                f"SELECT COUNT(DISTINCT {qcol}) FROM {ref}"
            ).fetchone()[0]
            profile["distinct"] = distinct

        profiles.append(profile)

    if as_json:
        print(json.dumps(profiles, indent=2, default=str, ensure_ascii=False))
    else:
        print(f"Profile: {file_path}")
        print(f"{'Column':<25} {'Type':<12} {'Nulls':<8} {'Stats'}")
        print("-" * 80)
        for p in profiles:
            stats_str = ""
            if "mean" in p:
                stats_str = f"min={p['min']} max={p['max']} mean={p['mean']}"
            elif "distinct" in p:
                stats_str = f"distinct={p['distinct']}"
            null_str = f"{p['nulls']} ({p['null_pct']}%)"
            print(f"{p['column']:<25} {p['type']:<12} {null_str:<8} {stats_str}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Data analysis with DuckDB")
    parser.add_argument("--json", action="store_true", dest="as_json")

    sub = parser.add_subparsers(dest="command", required=True)

    p_query = sub.add_parser("query", help="Run SQL query")
    p_query.add_argument("sql", help="SQL query string")
    p_query.add_argument("file", nargs="?", type=Path, help="Data file (optional)")

    p_inspect = sub.add_parser("inspect", help="Inspect file schema and sample")
    p_inspect.add_argument("file", type=Path)

    p_profile = sub.add_parser("profile", help="Statistical profile")
    p_profile.add_argument("file", type=Path)

    args = parser.parse_args()

    if args.command == "query":
        cmd_query(args.sql, args.file, args.as_json)
    elif args.command == "inspect":
        cmd_inspect(args.file, args.as_json)
    elif args.command == "profile":
        cmd_profile(args.file, args.as_json)


if __name__ == "__main__":
    main()
```

---

### 2.5 diagram.py — Diagram Generation

**Purpose:** Generate diagrams from Mermaid or Graphviz DSL. Simple charts from JSON data. Output SVG or PNG.

**When to use:** Architecture diagrams, flowcharts, sequence diagrams, simple data visualizations.

#### CLI Interface

```
diagram.py mermaid <spec>                  Mermaid diagram (file path or inline string)
diagram.py graphviz <spec>                 Graphviz DOT diagram
diagram.py chart <data.json> --type bar    Simple chart (bar, line, pie)
      --output <file>                      Output file (default: stdout for SVG)
      --png                                PNG output instead of SVG
```

#### Implementation

```python
#!/usr/bin/env python3
"""Diagram generation from Mermaid, Graphviz, or data."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import graphviz


def read_spec(spec: str) -> str:
    """Read spec from file path or return as inline string."""
    path = Path(spec)
    if path.exists():
        return path.read_text(encoding="utf-8")
    return spec


def cmd_mermaid(spec: str, output: Path | None, as_png: bool) -> None:
    """Render Mermaid diagram using mmdc (mermaid-cli).

    Requires: npm install -g @mermaid-js/mermaid-cli
    """
    content = read_spec(spec)
    fmt = "png" if as_png else "svg"

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".mmd", delete=False, encoding="utf-8"
    ) as f:
        f.write(content)
        input_file = f.name

    if output:
        output_file = str(output)
    else:
        output_file = tempfile.mktemp(suffix=f".{fmt}")

    try:
        # mmdc is the Mermaid CLI. On Windows, may need full path:
        # C:\Users\<user>\AppData\Roaming\npm\mmdc.cmd
        result = subprocess.run(
            ["mmdc", "-i", input_file, "-o", output_file, "-f", fmt],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            print(f"ERROR: mmdc failed: {result.stderr}", file=sys.stderr)
            sys.exit(1)

        if not output:
            # Write to stdout
            if as_png:
                sys.stdout.buffer.write(Path(output_file).read_bytes())
            else:
                print(Path(output_file).read_text(encoding="utf-8"))
        else:
            print(f"Wrote: {output_file}", file=sys.stderr)

    except FileNotFoundError:
        print(
            "ERROR: mmdc not found. Install with: npm install -g @mermaid-js/mermaid-cli",
            file=sys.stderr,
        )
        sys.exit(1)
    finally:
        Path(input_file).unlink(missing_ok=True)
        if not output:
            Path(output_file).unlink(missing_ok=True)


def cmd_graphviz(spec: str, output: Path | None, as_png: bool) -> None:
    """Render Graphviz DOT diagram."""
    content = read_spec(spec)
    fmt = "png" if as_png else "svg"

    # Parse the DOT source to extract graph name if present
    src = graphviz.Source(content, format=fmt)

    if output:
        src.render(filename=output.stem, directory=str(output.parent),
                   cleanup=True, format=fmt)
        print(f"Wrote: {output}", file=sys.stderr)
    else:
        rendered = src.pipe(format=fmt)
        if as_png:
            sys.stdout.buffer.write(rendered)
        else:
            print(rendered.decode("utf-8"))


def cmd_chart(data_file: Path, chart_type: str, output: Path | None,
              as_png: bool) -> None:
    """Generate a simple chart from JSON data.

    Expected JSON format:
    {"labels": ["Q1", "Q2", "Q3"], "values": [10, 20, 30]}
    or
    {"labels": ["Q1", "Q2"], "series": {"Revenue": [10, 20], "Cost": [5, 8]}}
    """
    data = json.loads(data_file.read_text(encoding="utf-8"))
    labels = data.get("labels", [])

    # Build a Graphviz-based simple chart (for environments without matplotlib)
    # For real charts, consider adding matplotlib as optional dep
    dot = graphviz.Digraph(format="png" if as_png else "svg")
    dot.attr(rankdir="LR", label=data.get("title", "Chart"))

    if "values" in data:
        max_val = max(data["values"]) if data["values"] else 1
        for label, value in zip(labels, data["values"]):
            width = str(max(0.5, (value / max_val) * 5))
            dot.node(label, f"{label}: {value}",
                     shape="rect", width=width, style="filled",
                     fillcolor="lightblue")
    else:
        # For proper charts, this is where you'd integrate matplotlib
        print("WARN: Multi-series charts need matplotlib. "
              "Install with: uv add matplotlib", file=sys.stderr)
        return

    if output:
        dot.render(filename=output.stem, directory=str(output.parent), cleanup=True)
        print(f"Wrote: {output}", file=sys.stderr)
    else:
        rendered = dot.pipe()
        if as_png:
            sys.stdout.buffer.write(rendered)
        else:
            print(rendered.decode("utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser(description="Diagram generation")
    parser.add_argument("--output", "-o", type=Path, help="Output file")
    parser.add_argument("--png", action="store_true", help="PNG output")

    sub = parser.add_subparsers(dest="command", required=True)

    p_mermaid = sub.add_parser("mermaid", help="Mermaid diagram")
    p_mermaid.add_argument("spec", help="Mermaid spec (file or inline string)")

    p_gv = sub.add_parser("graphviz", help="Graphviz DOT diagram")
    p_gv.add_argument("spec", help="DOT spec (file or inline string)")

    p_chart = sub.add_parser("chart", help="Simple chart from JSON")
    p_chart.add_argument("data", type=Path, help="JSON data file")
    p_chart.add_argument("--type", default="bar",
                         choices=["bar", "line", "pie"], dest="chart_type")

    args = parser.parse_args()

    if args.command == "mermaid":
        cmd_mermaid(args.spec, args.output, args.png)
    elif args.command == "graphviz":
        cmd_graphviz(args.spec, args.output, args.png)
    elif args.command == "chart":
        cmd_chart(args.data, args.chart_type, args.output, args.png)


if __name__ == "__main__":
    main()
```

**Windows Tips:**
- Graphviz system package must be installed separately: `winget install Graphviz.Graphviz`. The Python `graphviz` package is just a wrapper.
- Add Graphviz to PATH: `C:\Program Files\Graphviz\bin` (the installer usually does this).
- Mermaid CLI needs Node.js: `winget install OpenJS.NodeJS.LTS` then `npm install -g @mermaid-js/mermaid-cli`.
- On Windows, `mmdc` is at `%APPDATA%\npm\mmdc.cmd`. If subprocess can't find it, use the full path.

---

### 2.6 pdf.py — PDF Generation

**Purpose:** Convert Markdown or HTML files to PDF. Uses weasyprint for rendering.

**When to use:** Generating reports, exporting documentation, creating deliverables.

#### CLI Interface

```
pdf.py render <file>              Convert markdown or HTML to PDF
      --output <file.pdf>        Output path (default: input name with .pdf)
      --css <style.css>          Custom stylesheet
```

#### Implementation

```python
#!/usr/bin/env python3
"""PDF generation from Markdown or HTML."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path


def markdown_to_html(md_text: str) -> str:
    """Convert Markdown to HTML. Uses built-in or markdown package."""
    try:
        import markdown
        return markdown.markdown(
            md_text,
            extensions=["tables", "fenced_code", "codehilite", "toc"],
        )
    except ImportError:
        # Minimal fallback: wrap in <pre> tags
        from html import escape
        return f"<pre>{escape(md_text)}</pre>"


def render_html_to_pdf(html: str, output: Path, css: str | None = None) -> None:
    """Render HTML string to PDF using weasyprint."""
    try:
        from weasyprint import HTML, CSS
    except ImportError:
        print(
            "ERROR: weasyprint not installed. Install with: uv add weasyprint\n"
            "On Windows, you also need GTK3 runtime. See:\n"
            "https://doc.courtbouillon.org/weasyprint/stable/first_steps.html#windows",
            file=sys.stderr,
        )
        sys.exit(1)
    except OSError as e:
        if "gobject" in str(e).lower() or "gtk" in str(e).lower():
            print(
                "ERROR: GTK3/GObject not found. On Windows:\n"
                "1. Download MSYS2: https://www.msys2.org/\n"
                "2. Run: pacman -S mingw-w64-x86_64-pango\n"
                "3. Add MSYS2 bin to PATH\n"
                "Alternative: use pdfkit instead (uv add pdfkit, requires wkhtmltopdf)",
                file=sys.stderr,
            )
            sys.exit(1)
        raise

    DEFAULT_CSS = """
    body {
        font-family: 'Segoe UI', Tahoma, sans-serif;
        font-size: 11pt;
        line-height: 1.5;
        max-width: 180mm;
        margin: 20mm auto;
        color: #333;
    }
    h1 { font-size: 20pt; border-bottom: 1px solid #ccc; padding-bottom: 4pt; }
    h2 { font-size: 16pt; margin-top: 16pt; }
    h3 { font-size: 13pt; }
    code { background: #f4f4f4; padding: 2px 4px; font-size: 10pt; }
    pre { background: #f4f4f4; padding: 12px; overflow-x: auto; font-size: 9pt; }
    table { border-collapse: collapse; width: 100%; margin: 12px 0; }
    th, td { border: 1px solid #ddd; padding: 6px 8px; text-align: left; }
    th { background: #f0f0f0; }
    """

    stylesheets = [CSS(string=DEFAULT_CSS)]
    if css:
        stylesheets.append(CSS(filename=css))

    full_html = f"<!DOCTYPE html><html><body>{html}</body></html>"
    HTML(string=full_html).write_pdf(str(output), stylesheets=stylesheets)


def cmd_render(file_path: Path, output: Path | None, css: Path | None) -> None:
    """Render a file to PDF."""
    if not file_path.exists():
        print(f"ERROR: File not found: {file_path}", file=sys.stderr)
        sys.exit(1)

    content = file_path.read_text(encoding="utf-8")
    suffix = file_path.suffix.lower()

    if suffix in (".md", ".markdown"):
        html = markdown_to_html(content)
    elif suffix in (".html", ".htm"):
        html = content
    else:
        print(f"ERROR: Unsupported file type: {suffix}. Use .md or .html",
              file=sys.stderr)
        sys.exit(1)

    if not output:
        output = file_path.with_suffix(".pdf")

    css_path = str(css) if css else None
    render_html_to_pdf(html, output, css_path)
    print(f"Wrote: {output}", file=sys.stderr)


def main() -> None:
    parser = argparse.ArgumentParser(description="PDF generation")

    sub = parser.add_subparsers(dest="command", required=True)

    p_render = sub.add_parser("render", help="Render markdown/HTML to PDF")
    p_render.add_argument("file", type=Path, help="Input file (.md or .html)")
    p_render.add_argument("--output", "-o", type=Path, help="Output PDF path")
    p_render.add_argument("--css", type=Path, help="Custom CSS stylesheet")

    args = parser.parse_args()

    if args.command == "render":
        cmd_render(args.file, args.output, args.css)


if __name__ == "__main__":
    main()
```

**Windows Tips:**
- weasyprint requires GTK3/Pango. The easiest path on Windows is MSYS2.
- Alternative: use `pdfkit` + `wkhtmltopdf` if GTK3 is too painful. `winget install wkhtmltopdf` then `uv add pdfkit`.
- Another alternative: `uv add fpdf2` for programmatic PDF generation without system deps (but no HTML rendering).

---

## Part 3: Building Persona-Specific Sidecars

Each persona gets a minimal sidecar that imports the shared `core/` package but only bundles the scripts and dependencies they need.

### Pattern

```
personas/<persona>/sidecar/
├── pyproject.toml                # Minimal deps for this persona
├── core -> ../../../shared/sidecar/core   # Symlink to shared core
├── <subset of core scripts>      # Only what they need
└── <persona-specific scripts>    # Custom tools
```

**Creating symlinks on Windows:**

```powershell
# Run as Administrator (symlinks require elevated privileges on Windows)
# Or enable Developer Mode: Settings > Update & Security > For developers
New-Item -ItemType SymbolicLink -Path "core" -Target "..\..\..\shared\sidecar\core"
```

**Persona pyproject.toml pattern:**

```toml
[project]
name = "reflex-sidecar-<persona>"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = [
    # Only list what this persona's scripts need
]
```

---

### Persona: Tech Subject Expert

**Scripts:** fetch.py, llm.py (summarize, extract), diagram.py (mermaid only)

**Custom tool: evaluate.py**

Fetches a product/technology page and extracts features into a structured evaluation template.

```python
#!/usr/bin/env python3
"""Evaluate a product or technology by fetching its page and extracting features."""
from __future__ import annotations

import argparse
import json
import sys

from core.config import config
from core.ollama_client import generate

# Re-use fetch logic
from fetch import fetch_url, extract_text


EVAL_TEMPLATE = """
Analyze the following product/technology page and extract a structured evaluation.

Return JSON with these fields:
- name: product name
- vendor: company name
- category: product category
- description: one-sentence description
- key_features: list of top 5 features
- pricing_model: free/freemium/paid/enterprise (if mentioned)
- integration: list of integrations mentioned
- pros: list of strengths
- cons: list of potential concerns
- fit_score: 1-5 rating for enterprise IT use

Page content:
{text}
"""


def evaluate_product(url: str) -> str:
    """Fetch product page and return structured evaluation."""
    response = fetch_url(url)
    response.raise_for_status()
    text = extract_text(response.text)[:8000]

    prompt = EVAL_TEMPLATE.format(text=text)
    result = generate(
        prompt=prompt,
        model=config.models.get("extract"),
        system="You are a technology evaluator. Return ONLY valid JSON.",
    )

    try:
        parsed = json.loads(result)
        return json.dumps(parsed, indent=2, ensure_ascii=False)
    except json.JSONDecodeError:
        return result


def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate a product or technology")
    parser.add_argument("url", help="Product page URL")
    args = parser.parse_args()

    print(evaluate_product(args.url))


if __name__ == "__main__":
    main()
```

**Dependencies (pyproject.toml):**

```toml
dependencies = [
    "httpx>=0.27",
    "beautifulsoup4>=4.12",
    "lxml>=5.0",
    "ollama>=0.4",
    "graphviz>=0.20",
]
```

---

### Persona: Tech Solution Architect

**Scripts:** fetch.py (full), llm.py (full), diagram.py (full), data.py (query, inspect)

**Custom tool: adr.py**

Architecture Decision Record generator. Creates an ADR from a template, using the LLM to fill in context.

```python
#!/usr/bin/env python3
"""Generate Architecture Decision Records (ADRs)."""
from __future__ import annotations

import argparse
import datetime
from pathlib import Path

from core.config import config
from core.ollama_client import generate


ADR_TEMPLATE = """# ADR-{number}: {title}

**Date:** {date}
**Status:** Proposed
**Deciders:** [fill in]

## Context

{context}

## Decision

{decision}

## Consequences

### Positive
{positive}

### Negative
{negative}

### Risks
{risks}
"""


def create_adr(title: str, context_hint: str = "", adr_dir: Path | None = None) -> str:
    """Generate an ADR with LLM-assisted content."""
    if adr_dir is None:
        adr_dir = Path("docs/adr")
    adr_dir.mkdir(parents=True, exist_ok=True)

    # Determine next ADR number
    existing = list(adr_dir.glob("*.md"))
    number = len(existing) + 1

    # Use LLM to flesh out the decision
    prompt = (
        f"Generate content for an Architecture Decision Record titled: '{title}'\n"
        f"Additional context: {context_hint}\n\n"
        "Provide these sections as plain text (no markdown headers):\n"
        "1. CONTEXT: Why is this decision needed? (2-3 sentences)\n"
        "2. DECISION: What did we decide? (2-3 sentences)\n"
        "3. POSITIVE: Positive consequences (3 bullet points)\n"
        "4. NEGATIVE: Negative consequences or trade-offs (2-3 bullet points)\n"
        "5. RISKS: Risks to monitor (2-3 bullet points)\n\n"
        "Format each section starting with the label followed by a colon."
    )

    result = generate(
        prompt=prompt,
        model=config.models.get("default"),
        system="You are a solutions architect creating ADRs for enterprise IT decisions.",
    )

    # Parse the LLM output (best-effort)
    sections = {"CONTEXT": "", "DECISION": "", "POSITIVE": "", "NEGATIVE": "", "RISKS": ""}
    current_section = ""
    for line in result.splitlines():
        line_upper = line.strip().upper()
        for key in sections:
            if line_upper.startswith(key):
                current_section = key
                # Take content after the label
                rest = line.split(":", 1)[-1].strip() if ":" in line else ""
                if rest:
                    sections[current_section] = rest + "\n"
                break
        else:
            if current_section:
                sections[current_section] += line + "\n"

    # Fill template
    content = ADR_TEMPLATE.format(
        number=f"{number:04d}",
        title=title,
        date=datetime.date.today().isoformat(),
        context=sections["CONTEXT"].strip() or "[fill in]",
        decision=sections["DECISION"].strip() or "[fill in]",
        positive=sections["POSITIVE"].strip() or "- [fill in]",
        negative=sections["NEGATIVE"].strip() or "- [fill in]",
        risks=sections["RISKS"].strip() or "- [fill in]",
    )

    slug = title.lower().replace(" ", "-")[:50]
    filename = adr_dir / f"adr-{number:04d}-{slug}.md"
    filename.write_text(content, encoding="utf-8")

    return str(filename)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate ADRs")
    sub = parser.add_subparsers(dest="command", required=True)

    p_create = sub.add_parser("create", help="Create a new ADR")
    p_create.add_argument("title", help="Decision title")
    p_create.add_argument("--context", default="", help="Additional context hint")
    p_create.add_argument("--dir", type=Path, default=None, help="ADR directory")

    args = parser.parse_args()

    if args.command == "create":
        path = create_adr(args.title, args.context, args.dir)
        print(f"Created: {path}")


if __name__ == "__main__":
    main()
```

---

### Persona: Tester

**Scripts:** llm.py (summarize, classify only)

**Custom tool: testgen.py**

Generates test cases from requirements written in plain language.

```python
#!/usr/bin/env python3
"""Generate test cases from requirements documents."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from core.config import config
from core.ollama_client import generate


def generate_tests(requirements_file: Path, output_format: str = "markdown") -> str:
    """Read requirements and generate test cases."""
    text = requirements_file.read_text(encoding="utf-8")

    prompt = (
        "Read the following requirements and generate test cases.\n\n"
        "For each requirement, generate:\n"
        "- Test case ID (TC-001, TC-002, ...)\n"
        "- Requirement reference\n"
        "- Test description\n"
        "- Preconditions\n"
        "- Steps (numbered)\n"
        "- Expected result\n"
        "- Priority (High/Medium/Low)\n\n"
        f"Requirements:\n{text[:10000]}\n\n"
        "Generate comprehensive test cases covering happy path, edge cases, "
        "and error scenarios."
    )

    return generate(
        prompt=prompt,
        model=config.models.get("default"),
        system=(
            "You are a QA engineer generating test cases. "
            "Be thorough and specific. Use the exact format requested."
        ),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate test cases from requirements")
    parser.add_argument("file", type=Path, help="Requirements file (markdown or text)")
    parser.add_argument("--format", choices=["markdown", "csv"], default="markdown",
                        dest="output_format")
    args = parser.parse_args()

    if not args.file.exists():
        print(f"ERROR: File not found: {args.file}", file=sys.stderr)
        sys.exit(1)

    print(generate_tests(args.file, args.output_format))


if __name__ == "__main__":
    main()
```

**Custom tool: bugreport.py**

Interactive bug report generator that structures input into a standard template.

```python
#!/usr/bin/env python3
"""Interactive bug report generator."""
from __future__ import annotations

import argparse
import datetime
import sys
from pathlib import Path

from core.config import config
from core.ollama_client import generate


def generate_report(description: str, steps: str = "", environment: str = "") -> str:
    """Generate a structured bug report from raw input."""
    prompt = (
        "Create a structured bug report from this information:\n\n"
        f"Description: {description}\n"
        f"Steps to reproduce: {steps}\n"
        f"Environment: {environment}\n\n"
        "Return a formatted bug report with these sections:\n"
        "- Title (concise, actionable)\n"
        "- Severity (Critical/High/Medium/Low)\n"
        "- Environment\n"
        "- Steps to Reproduce (numbered)\n"
        "- Expected Behavior\n"
        "- Actual Behavior\n"
        "- Additional Notes\n"
    )

    return generate(
        prompt=prompt,
        model=config.models.get("default"),
        system="You are a QA engineer writing clear, actionable bug reports.",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate bug reports")
    parser.add_argument("--description", "-d", required=True,
                        help="Bug description")
    parser.add_argument("--steps", "-s", default="",
                        help="Steps to reproduce")
    parser.add_argument("--env", "-e", default="Windows 11",
                        help="Environment info")
    parser.add_argument("--output", "-o", type=Path,
                        help="Save to file")

    args = parser.parse_args()
    report = generate_report(args.description, args.steps, args.env)

    if args.output:
        args.output.write_text(report, encoding="utf-8")
        print(f"Wrote: {args.output}", file=sys.stderr)
    else:
        print(report)


if __name__ == "__main__":
    main()
```

---

### Persona: Helpdesk

**Scripts:** fetch.py (restricted to internal URLs), llm.py (fast model only)

**Custom tool: kb-search.py**

Searches the Obsidian vault for relevant KB articles.

```python
#!/usr/bin/env python3
"""Search the Obsidian knowledge base for relevant articles."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from core.config import config
from core.ollama_client import generate


def search_vault(query: str, max_results: int = 5) -> list[dict[str, str]]:
    """Search markdown files in the Obsidian vault by keyword matching.

    For a production system, consider indexing with embeddings.
    This simple version uses keyword matching + LLM re-ranking.
    """
    vault = config.kb.vault_path
    if not vault.exists():
        print(f"ERROR: Vault not found at {vault}", file=sys.stderr)
        sys.exit(1)

    query_terms = query.lower().split()
    candidates: list[tuple[int, Path]] = []

    for md_file in vault.rglob("*.md"):
        try:
            content = md_file.read_text(encoding="utf-8", errors="replace").lower()
            score = sum(content.count(term) for term in query_terms)
            if score > 0:
                candidates.append((score, md_file))
        except Exception:
            continue

    # Sort by score descending, take top results
    candidates.sort(key=lambda x: x[0], reverse=True)
    top = candidates[:max_results]

    results = []
    for score, path in top:
        content = path.read_text(encoding="utf-8", errors="replace")
        # First 500 chars as preview
        results.append({
            "file": str(path.relative_to(vault)),
            "score": score,
            "preview": content[:500].strip(),
        })

    return results


def main() -> None:
    parser = argparse.ArgumentParser(description="Search Obsidian knowledge base")
    parser.add_argument("query", help="Search query")
    parser.add_argument("--max", type=int, default=5, help="Max results")
    args = parser.parse_args()

    results = search_vault(args.query, args.max)

    if not results:
        print("No matching articles found.")
        return

    for i, r in enumerate(results, 1):
        print(f"\n--- Result {i}: {r['file']} (score: {r['score']}) ---")
        print(r["preview"])
        print()


if __name__ == "__main__":
    main()
```

**Custom tool: draft-response.py**

Drafts a customer response using KB context.

```python
#!/usr/bin/env python3
"""Draft a customer response using knowledge base context."""
from __future__ import annotations

import argparse
import sys

from core.config import config
from core.ollama_client import generate

# Re-use KB search
from importlib import import_module


def draft_response(ticket_description: str) -> str:
    """Search KB for context, then draft a response."""
    # Import kb_search dynamically to avoid circular deps
    kb_search = __import__("kb-search", fromlist=["search_vault"])
    results = kb_search.search_vault(ticket_description, max_results=3)

    context_parts = []
    for r in results:
        context_parts.append(f"[{r['file']}]\n{r['preview']}")

    kb_context = "\n\n".join(context_parts) if context_parts else "No KB articles found."

    prompt = (
        f"Draft a helpful customer response for this support ticket:\n\n"
        f"TICKET: {ticket_description}\n\n"
        f"KNOWLEDGE BASE CONTEXT:\n{kb_context}\n\n"
        "Requirements:\n"
        "- Professional but friendly tone\n"
        "- Reference specific KB articles if relevant\n"
        "- Include step-by-step instructions if applicable\n"
        "- End with an offer for further help\n"
    )

    return generate(
        prompt=prompt,
        model=config.models.get("fast"),
        system=(
            "You are a helpdesk agent at Reflex BV. Draft clear, helpful "
            "responses. Use the knowledge base articles as reference material."
        ),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Draft customer response")
    parser.add_argument("description", help="Ticket description or question")
    args = parser.parse_args()
    print(draft_response(args.description))


if __name__ == "__main__":
    main()
```

---

### Persona: Marketing

**Scripts:** fetch.py (full), llm.py (summarize, extract)

**Custom tool: content.py**

Content drafting with configurable type and brand voice.

```python
#!/usr/bin/env python3
"""Content drafting with brand voice."""
from __future__ import annotations

import argparse

from core.config import config
from core.ollama_client import generate


CONTENT_PROMPTS: dict[str, str] = {
    "blog": (
        "Write a blog post about: {topic}\n\n"
        "Requirements: 500-800 words, professional but approachable tone, "
        "include an introduction, 3-4 key points, and a conclusion with CTA."
    ),
    "social": (
        "Write a social media post about: {topic}\n\n"
        "Requirements: Under 280 characters for Twitter/X, engaging, "
        "include relevant hashtags. Also provide a longer LinkedIn version (2-3 paragraphs)."
    ),
    "email": (
        "Write a marketing email about: {topic}\n\n"
        "Requirements: Clear subject line, brief body (150-250 words), "
        "single CTA button text, professional tone."
    ),
}


def draft_content(topic: str, content_type: str) -> str:
    """Draft marketing content."""
    prompt = CONTENT_PROMPTS.get(content_type, CONTENT_PROMPTS["blog"]).format(topic=topic)

    return generate(
        prompt=prompt,
        model=config.models.get("default"),
        system=(
            "You are a B2B marketing writer for Reflex BV, a technology company. "
            "Write in a professional, clear style. Avoid jargon. "
            "Focus on business value, not technical details."
        ),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Content drafting")
    sub = parser.add_subparsers(dest="command", required=True)

    p_draft = sub.add_parser("draft", help="Draft content")
    p_draft.add_argument("topic", help="Content topic")
    p_draft.add_argument("--type", choices=["blog", "social", "email"],
                         default="blog", dest="content_type")

    args = parser.parse_args()

    if args.command == "draft":
        print(draft_content(args.topic, args.content_type))


if __name__ == "__main__":
    main()
```

**Custom tool: competitor.py**

Fetch and analyze a competitor's web presence.

```python
#!/usr/bin/env python3
"""Competitor analysis with structured extraction."""
from __future__ import annotations

import argparse
import json

from core.config import config
from core.ollama_client import generate
from fetch import fetch_url, extract_text


def analyze_competitor(url: str) -> str:
    """Fetch competitor page and extract structured analysis."""
    response = fetch_url(url)
    response.raise_for_status()
    text = extract_text(response.text)[:8000]

    prompt = (
        f"Analyze this competitor's web page and extract:\n\n"
        f"Page content:\n{text}\n\n"
        "Return JSON with:\n"
        "- company_name: string\n"
        "- tagline: string\n"
        "- products: list of product names\n"
        "- target_audience: string\n"
        "- key_messages: list of 3-5 marketing messages\n"
        "- differentiators: what they claim makes them unique\n"
        "- pricing_visible: boolean\n"
        "- cta_text: their primary call-to-action\n"
        "- tone: formal/casual/technical/marketing\n"
        "- strengths: list of apparent strengths\n"
        "- weaknesses: list of apparent gaps or weaknesses\n"
    )

    result = generate(
        prompt=prompt,
        model=config.models.get("extract"),
        system="You are a competitive analyst. Return ONLY valid JSON.",
    )

    try:
        parsed = json.loads(result)
        return json.dumps(parsed, indent=2, ensure_ascii=False)
    except json.JSONDecodeError:
        return result


def main() -> None:
    parser = argparse.ArgumentParser(description="Competitor analysis")
    parser.add_argument("url", help="Competitor website URL")
    args = parser.parse_args()
    print(analyze_competitor(args.url))


if __name__ == "__main__":
    main()
```

---

### Persona: CEO

**Scripts:** llm.py (summarize only), data.py (query, inspect)

**Custom tool: briefing.py**

Generates an executive briefing from recent activity.

```python
#!/usr/bin/env python3
"""Generate executive briefing from project activity and KB updates."""
from __future__ import annotations

import argparse
import datetime
import subprocess
import sys
from pathlib import Path

from core.config import config
from core.ollama_client import generate


def get_recent_commits(repo_path: Path, days: int = 7) -> str:
    """Get recent git commits as context."""
    since = (datetime.date.today() - datetime.timedelta(days=days)).isoformat()
    try:
        result = subprocess.run(
            ["git", "log", f"--since={since}", "--oneline", "--no-merges"],
            capture_output=True, text=True, cwd=str(repo_path),
        )
        return result.stdout.strip() or "No recent commits."
    except Exception:
        return "Git log unavailable."


def get_recent_kb_updates(vault_path: Path, days: int = 7) -> list[str]:
    """Find recently modified KB articles."""
    cutoff = datetime.datetime.now() - datetime.timedelta(days=days)
    recent: list[str] = []

    if not vault_path.exists():
        return ["KB vault not found."]

    for md_file in vault_path.rglob("*.md"):
        try:
            mtime = datetime.datetime.fromtimestamp(md_file.stat().st_mtime)
            if mtime > cutoff:
                recent.append(str(md_file.relative_to(vault_path)))
        except Exception:
            continue

    return recent[:20]  # Cap at 20


def generate_briefing(repo_path: Path | None, days: int) -> str:
    """Generate executive briefing."""
    sections = []

    # Git activity
    if repo_path:
        commits = get_recent_commits(repo_path, days)
        sections.append(f"RECENT DEVELOPMENT ACTIVITY ({days} days):\n{commits}")

    # KB updates
    kb_updates = get_recent_kb_updates(config.kb.vault_path, days)
    if kb_updates:
        sections.append(
            f"KNOWLEDGE BASE UPDATES ({days} days):\n"
            + "\n".join(f"- {f}" for f in kb_updates)
        )

    context = "\n\n".join(sections) or "No recent activity data available."

    prompt = (
        f"Generate a concise executive briefing based on this activity data:\n\n"
        f"{context}\n\n"
        "Format:\n"
        "1. Executive Summary (2-3 sentences)\n"
        "2. Key Developments (bullet points)\n"
        "3. Items Requiring Attention (if any)\n"
        "4. Upcoming (if identifiable from context)\n"
    )

    return generate(
        prompt=prompt,
        model=config.models.get("fast"),
        system=(
            "You are an executive assistant creating a briefing for a CEO. "
            "Be concise, factual, and highlight what matters most. "
            "Flag anything that looks like it needs executive attention."
        ),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Executive briefing generator")
    parser.add_argument("--repo", type=Path, default=None, help="Git repo path")
    parser.add_argument("--days", type=int, default=7, help="Lookback period")
    args = parser.parse_args()

    print(generate_briefing(args.repo, args.days))


if __name__ == "__main__":
    main()
```

---

### Persona: CTO

**Scripts:** llm.py (full), diagram.py (full), data.py (full)

**Custom tool: techradar.py**

Technology radar assessment for evaluating technologies against company criteria.

```python
#!/usr/bin/env python3
"""Technology radar assessment tool."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from core.config import config
from core.ollama_client import generate


QUADRANTS = ["Techniques", "Platforms", "Tools", "Languages & Frameworks"]
RINGS = ["Adopt", "Trial", "Assess", "Hold"]


def assess_technology(name: str, context: str = "") -> str:
    """Assess a technology for the tech radar."""
    prompt = (
        f"Assess the technology '{name}' for a company tech radar.\n\n"
        f"Additional context: {context}\n\n"
        f"Quadrants: {QUADRANTS}\n"
        f"Rings: {RINGS}\n\n"
        "Return JSON with:\n"
        "- name: technology name\n"
        "- quadrant: one of the quadrants\n"
        "- ring: one of the rings (Adopt/Trial/Assess/Hold)\n"
        "- description: 1-2 sentence description\n"
        "- rationale: why this ring placement (2-3 sentences)\n"
        "- maturity: low/medium/high\n"
        "- community: small/medium/large\n"
        "- enterprise_ready: boolean\n"
        "- skills_available: how easy to hire for (easy/moderate/hard)\n"
        "- risk_level: low/medium/high\n"
        "- recommendation: actionable next step\n"
    )

    result = generate(
        prompt=prompt,
        model=config.models.get("deep"),
        system=(
            "You are a CTO evaluating technologies for enterprise adoption. "
            "Be pragmatic — consider maturity, hiring, support, and total cost of ownership. "
            "Return ONLY valid JSON."
        ),
    )

    try:
        parsed = json.loads(result)
        return json.dumps(parsed, indent=2, ensure_ascii=False)
    except json.JSONDecodeError:
        return result


def main() -> None:
    parser = argparse.ArgumentParser(description="Technology radar assessment")
    parser.add_argument("technology", help="Technology to assess")
    parser.add_argument("--context", default="",
                        help="Additional context about usage plans")
    args = parser.parse_args()

    print(assess_technology(args.technology, args.context))


if __name__ == "__main__":
    main()
```

---

## Part 4: Development Workflow

### Project Setup

```powershell
# Clone the repo and create a worktree for sidecar development
cd C:\Projects\reflex-genai
git worktree add .worktrees\sidecar-dev -b feature\sidecar-core

cd .worktrees\sidecar-dev\shared\sidecar
uv sync
```

### Testing

#### Unit Tests (mock Ollama, no network)

```python
# tests/test_config.py
"""Tests for config loading."""
from __future__ import annotations

import os
import tempfile
from pathlib import Path

from core.config import load_config, _config_path


def test_default_config() -> None:
    """Config loads with sensible defaults when no file exists."""
    cfg = load_config()
    assert cfg.ollama.host == "localhost"
    assert cfg.ollama.port == 11434
    assert cfg.models.fast == "llama3.2:3b"


def test_env_override(monkeypatch) -> None:
    """Environment variables override config file."""
    monkeypatch.setenv("AIPM_OLLAMA_HOST", "192.168.1.100")
    cfg = load_config()
    assert cfg.ollama.host == "192.168.1.100"
```

```python
# tests/test_llm.py
"""Tests for llm.py with mocked Ollama."""
from __future__ import annotations

from unittest.mock import patch


def test_resolve_model() -> None:
    """Correct model tier selected per command."""
    # Import after config is loaded
    sys_path_hack()  # add sidecar to path
    from llm import resolve_model
    model = resolve_model("classify", override=None)
    assert "3b" in model  # fast tier


def test_summarize_truncates_long_input() -> None:
    """Long inputs are truncated before sending to Ollama."""
    with patch("core.ollama_client.generate", return_value="Summary here") as mock:
        from llm import cmd_summarize
        from pathlib import Path
        import tempfile

        with tempfile.NamedTemporaryFile(mode="w", suffix=".txt",
                                         delete=False, encoding="utf-8") as f:
            f.write("x" * 20000)
            f.flush()
            result = cmd_summarize(Path(f.name), "llama3.1:8b")

        assert result == "Summary here"
        call_prompt = mock.call_args.kwargs.get("prompt", mock.call_args[0][0])
        assert len(call_prompt) < 20000  # Truncated
```

#### Integration Tests (real Ollama, run manually)

```python
# tests/integration/test_ollama_live.py
"""Integration tests — require Ollama running locally."""
import pytest
from core.ollama_client import is_available, generate


@pytest.fixture(autouse=True)
def skip_if_no_ollama() -> None:
    if not is_available():
        pytest.skip("Ollama not running")


def test_generate_basic() -> None:
    result = generate("Say 'hello' and nothing else.", model="llama3.2:3b")
    assert "hello" in result.lower()
```

#### Running Tests

```powershell
# Unit tests (no Ollama needed)
uv run pytest tests/ -v --ignore=tests/integration

# Integration tests (Ollama must be running)
uv run pytest tests/integration/ -v

# With coverage
uv run pytest tests/ -v --cov=core --cov-report=term-missing
```

### Code Quality

```powershell
# Type checking
uv run mypy core/ *.py --ignore-missing-imports

# Linting
uv run ruff check .

# Formatting
uv run ruff format .
```

Add dev dependencies:

```powershell
uv add --dev pytest pytest-cov mypy ruff
```

### Versioning

The sidecar follows the main project's semantic versioning.

- Bump `version` in `pyproject.toml`
- Tag in git: `git tag sidecar-v0.2.0`
- Core changes = MINOR bump (new script, new command)
- Bug fixes = PATCH bump
- Breaking config/CLI changes = MAJOR bump

### Deployment

**Option A: Direct copy (simplest)**

```powershell
# On each user's machine
Copy-Item "\\server\shared\sidecar\*" "$env:USERPROFILE\.claude\sidecar\" -Recurse -Force
cd "$env:USERPROFILE\.claude\sidecar"
uv sync
```

**Option B: Git clone (recommended for developers)**

```powershell
git clone https://github.com/reflex-bv/reflex-genai.git "$env:USERPROFILE\reflex-genai"
New-Item -ItemType SymbolicLink `
    -Path "$env:USERPROFILE\.claude\sidecar" `
    -Target "$env:USERPROFILE\reflex-genai\shared\sidecar"
cd "$env:USERPROFILE\.claude\sidecar"
uv sync
```

**Updating:**

```powershell
cd "$env:USERPROFILE\.claude\sidecar"
git pull    # if git-based
uv sync     # update dependencies
```

---

## Part 5: Persona Sidecar Quick Reference

| Persona | Scripts | Custom Tools | Ollama Models | Approx. Disk |
|---------|---------|-------------|---------------|-------------|
| Developer | all 5 | none needed | all tiers | ~60GB |
| Subject Expert | 3 (fetch, llm, diagram) | evaluate.py | default, extract | ~12GB |
| Solution Architect | 4 (fetch, llm, diagram, data) | adr.py | default, deep, code | ~60GB |
| Tester | 1 (llm) | testgen.py, bugreport.py | fast, default | ~8GB |
| Helpdesk | 2 (fetch, llm) | kb-search.py, draft-response.py | fast, default | ~8GB |
| Marketing | 2 (fetch, llm) | content.py, competitor.py | default, extract | ~12GB |
| CEO | 2 (llm, data) | briefing.py | fast, default | ~8GB |
| CTO | 3 (llm, diagram, data) | techradar.py | default, deep | ~50GB |

### Ollama Model Sizes

| Tier | Model | Size | RAM Needed |
|------|-------|------|-----------|
| fast | llama3.2:3b | ~2GB | 4GB |
| default | llama3.1:8b | ~5GB | 8GB |
| extract | mistral:7b | ~4GB | 8GB |
| code | deepseek-coder-v2:16b | ~9GB | 16GB |
| deep | llama3.1:70b | ~40GB | 48GB |
| embed | nomic-embed-text | ~275MB | 1GB |

### How to Build a New Persona Sidecar

1. Create `personas/<name>/sidecar/`
2. Create a minimal `pyproject.toml` with only the dependencies needed
3. Symlink `core/` to `shared/sidecar/core/`
4. Copy only the core scripts this persona needs
5. Add persona-specific scripts
6. Write tests for the custom scripts
7. Document in the persona's CLAUDE.md which scripts are available and how they map to `uv run` commands

### Invocation Pattern in CLAUDE.md

Add this to each persona's CLAUDE.md so the AI assistant knows the scripts are available:

```markdown
## Python Sidecar

| Task | Command |
|------|---------|
| Fetch a webpage | `uv run --directory ~/.claude/sidecar python fetch.py <url>` |
| Summarize a file | `uv run --directory ~/.claude/sidecar python llm.py summarize <file>` |
| ... | ... |
```
