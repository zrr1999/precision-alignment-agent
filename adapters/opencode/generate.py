#!/usr/bin/env python3
"""
OpenCode Adapter

Reads canonical agent definitions from agents/*.md (YAML frontmatter + prompt)
and generates the .opencode/ directory structure that opencode-ai expects.

Usage:
    python adapters/opencode/generate.py [--dry-run]

Dependencies: PyYAML (pyyaml)
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import yaml

# ── Paths ────────────────────────────────────────────────────────────────────

ROOT = Path(__file__).resolve().parent.parent.parent
AGENTS_DIR = ROOT / "agents"
OPENCODE_DIR = ROOT / ".opencode"
OPENCODE_AGENTS_DIR = OPENCODE_DIR / "agents"

# ── Model mapping ────────────────────────────────────────────────────────────

MODEL_MAP: dict[str, str] = {
    "reasoning": "github-copilot/claude-opus-4.6",   # exploration, planning, analysis, review
    "coding": "github-copilot/gpt-5.2-codex",        # code editing, building, execution
}

# ── Capability group expansion ───────────────────────────────────────────────

# Each capability group maps to a set of opencode tool flags
CAPABILITY_GROUPS: dict[str, dict[str, bool]] = {
    "read-code":    {"read": True, "glob": True, "grep": True},
    "write-code":   {"write": True, "edit": True},
    "write-report": {"write": True},
    "web-access":   {"webfetch": True, "websearch": True},
    "web-read":     {"webfetch": True},
    "context7":     {"context7": True},
    "gh-search":    {"gh_grep": True},
}


def expand_capabilities(caps: list) -> tuple[dict[str, bool], list[str], list[str]]:
    """Expand capability groups into opencode tools, bash patterns, and delegates.

    Returns: (tools_map, bash_allowed, delegates)
    """
    tools: dict[str, bool] = {}
    bash_allowed: list[str] = []
    delegates: list[str] = []

    for cap in caps:
        if isinstance(cap, str):
            # Simple capability group
            if cap in CAPABILITY_GROUPS:
                tools.update(CAPABILITY_GROUPS[cap])
            else:
                print(f"  Warning: unknown capability group '{cap}'")
        elif isinstance(cap, dict):
            # Structured capability: bash or delegate
            if "bash" in cap:
                bash_allowed = cap["bash"] or []
                tools["bash"] = bool(bash_allowed)
            if "delegate" in cap:
                delegates = cap["delegate"] or []
                if delegates:
                    tools["task"] = True

    # Only keep True entries
    return {k: v for k, v in tools.items() if v}, bash_allowed, delegates


# ── Loader ───────────────────────────────────────────────────────────────────


def load_agent_defs() -> list[dict]:
    """Load all agents/*.md with YAML frontmatter."""
    agents = []
    for md_path in sorted(AGENTS_DIR.glob("*.md")):
        text = md_path.read_text()

        # Parse YAML frontmatter (between --- delimiters)
        if not text.startswith("---"):
            continue
        end = text.index("---", 3)
        fm_text = text[3:end]
        body = text[end + 3:].lstrip("\n")

        defn = yaml.safe_load(fm_text)
        if not defn or "name" not in defn:
            continue

        # Expand capabilities
        raw_caps = defn.get("capabilities", [])
        tools, bash_allowed, delegates = expand_capabilities(raw_caps)
        defn["_tools"] = tools
        defn["_bash_allowed"] = bash_allowed
        defn["_delegates"] = delegates

        # Resolve prompt content
        prompt_file = defn.get("prompt_file")
        if prompt_file:
            prompt_path = (AGENTS_DIR / prompt_file).resolve()
            defn["_prompt_content"] = prompt_path.read_text() if prompt_path.exists() else ""
            defn["_prompt_rel_path"] = str(prompt_path.relative_to(ROOT))
        else:
            defn["_prompt_content"] = body
            defn["_prompt_rel_path"] = ""

        defn["_source"] = md_path.name
        agents.append(defn)
    return agents


# ── Shared helpers ───────────────────────────────────────────────────────────


def build_permissions(bash_allowed: list[str], delegates: list[str], tools: dict[str, bool]) -> dict:
    perm: dict = {}

    # Bash command whitelist
    if bash_allowed:
        perm["bash"] = {"*": "deny"}
        for pattern in bash_allowed:
            perm["bash"][pattern] = "allow"

    # Sub-agent delegation
    if delegates:
        perm["task"] = {"*": "deny"}
        for d in delegates:
            perm["task"][d] = "allow"

    # File mutation permissions
    if tools.get("edit"):
        perm["edit"] = "allow"
    if tools.get("write"):
        perm["write"] = "allow"

    perm["question"] = "allow"
    return perm


def resolve_model(model_cfg: dict | None) -> str:
    tier = (model_cfg or {}).get("tier", "reasoning")
    return MODEL_MAP.get(tier, MODEL_MAP["reasoning"])


def resolve_temperature(model_cfg: dict | None, default: float) -> float:
    return (model_cfg or {}).get("temperature", default)


# ── YAML serializer (clean output with double-quoted keys) ───────────────────


def _yaml_line(key: str, value, indent: int = 0) -> str:
    prefix = "  " * indent
    if isinstance(value, bool):
        return f'{prefix}"{key}": {str(value).lower()}'
    elif isinstance(value, (int, float)):
        return f'{prefix}"{key}": {value}'
    elif isinstance(value, str):
        return f'{prefix}"{key}": {value}'
    else:
        return f'{prefix}"{key}": {value}'


def serialize_frontmatter(desc: str, mode: str, model: str, temp: float,
                          skills: list[str], tools: dict, permission: dict) -> str:
    """Serialize opencode agent frontmatter with consistent formatting."""
    lines = ["---"]
    lines.append(f"description: {desc}")
    lines.append(f"mode: {mode}")
    lines.append(f"model: {model}")
    lines.append(f"temperature: {temp}")

    if skills:
        lines.append("skills:")
        for s in skills:
            lines.append(f"  - {s}")

    if tools:
        lines.append("tools:")
        for k, v in tools.items():
            lines.append(f'  "{k}": {str(v).lower()}')

    if permission:
        lines.append("permission:")
        for section, val in permission.items():
            if isinstance(val, dict):
                lines.append(f'  "{section}":')
                for pk, pv in val.items():
                    lines.append(f'    "{pk}": {pv}')
            else:
                lines.append(f'  "{section}": {val}')

    lines.append("---")
    return "\n".join(lines)


# ── opencode.json generator ─────────────────────────────────────────────────


def generate_opencode_json(agents: list[dict]) -> dict:
    config = {
        "$schema": "https://opencode.ai/config.json",
        "permission": {
            "external_directory": {
                "*": "deny",
                "/workspace/*": "allow",
            },
        },
        "agent": {},
    }

    for agent in agents:
        if agent.get("role") != "primary":
            continue

        tools = agent["_tools"]
        bash_allowed = agent["_bash_allowed"]
        delegates = agent["_delegates"]

        config["agent"][agent["name"]] = {
            "mode": "primary",
            "model": resolve_model(agent.get("model")),
            "temperature": resolve_temperature(agent.get("model"), 0.2),
            "prompt": "{file:./" + agent["_prompt_rel_path"] + "}",
            "skills": agent.get("skills", []),
            "tools": tools,
            "permission": build_permissions(bash_allowed, delegates, tools),
        }

    return config


# ── .opencode/agents/*.md generator ─────────────────────────────────────────


def generate_agent_md(agent: dict) -> str:
    tools = agent["_tools"]
    bash_allowed = agent["_bash_allowed"]
    delegates = agent["_delegates"]

    desc = agent["description"].strip()
    model = resolve_model(agent.get("model"))
    temp = resolve_temperature(agent.get("model"), 0.1)
    skills = [s for s in agent.get("skills", []) if s]
    permission = build_permissions(bash_allowed, delegates, tools)

    fm = serialize_frontmatter(desc, "subagent", model, temp, skills, tools, permission)
    prompt = agent.get("_prompt_content", "")
    return f"{fm}\n\n{prompt}"


# ── Main ─────────────────────────────────────────────────────────────────────


def main():
    parser = argparse.ArgumentParser(description="Generate .opencode/ from agents/")
    parser.add_argument("--dry-run", action="store_true", help="Preview without writing files")
    args = parser.parse_args()

    print("Loading agent definitions from agents/...")
    agents = load_agent_defs()
    primaries = [a for a in agents if a.get("role") == "primary"]
    subagents = [a for a in agents if a.get("role") == "subagent"]
    print(f"  Found {len(agents)} agents ({len(primaries)} primary, {len(subagents)} subagent)")

    # 1. Generate opencode.json
    config = generate_opencode_json(agents)
    config_json = json.dumps(config, indent=2, ensure_ascii=False) + "\n"

    if args.dry_run:
        print("\n── opencode.json ──")
        print(config_json)
    else:
        (ROOT / "opencode.json").write_text(config_json)
        print("  Written: opencode.json")

    # 2. Generate .opencode/agents/*.md
    OPENCODE_AGENTS_DIR.mkdir(parents=True, exist_ok=True)

    for agent in subagents:
        content = generate_agent_md(agent)
        out_path = OPENCODE_AGENTS_DIR / f"{agent['name']}.md"

        if args.dry_run:
            print(f"\n── .opencode/agents/{agent['name']}.md ──")
            lines = content.split("\n")
            print("\n".join(lines[:40]))
            if len(lines) > 40:
                print(f"  ... ({len(lines) - 40} more lines)")
        else:
            out_path.write_text(content)
            print(f"  Written: .opencode/agents/{agent['name']}.md")

    print("\nDone.")


if __name__ == "__main__":
    main()
