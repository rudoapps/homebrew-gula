"""Skill service — loads, merges, and resolves skills from multiple sources."""

from __future__ import annotations

import logging
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Optional

from ..ports.driven.api_client_port import ApiClientPort
from .auth_service import AuthService
from ...domain.entities.skill import Skill, SkillResolution

logger = logging.getLogger(__name__)


class SkillService:
    """Manages the lifecycle of skills: load, merge, resolve.

    Skills are loaded from three sources (highest priority first):
      1. Project-local:  .gula/skills/*.yaml
      2. User-global:    ~/.config/gula-agent/skills/*.yaml
      3. Backend:        GET /agent/skills

    Duplicate names are resolved by priority — project overrides user
    overrides backend.
    """

    def __init__(
        self,
        auth_service: AuthService,
        api_client: ApiClientPort,
    ) -> None:
        self._auth_service = auth_service
        self._api_client = api_client
        self._skills: Dict[str, Skill] = {}

    async def load_skills(self) -> None:
        """Load and merge skills from all sources."""
        from ...driven.skills.yaml_loader import load_skills_from_directory

        # 1. Backend skills (lowest priority — loaded first, overwritten later)
        backend = await self._fetch_backend_skills()
        for s in backend:
            self._skills[s.name] = s

        # 2. User-global skills
        user_dir = Path.home() / ".config" / "gula-agent" / "skills"
        for s in load_skills_from_directory(user_dir, source="user"):
            self._skills[s.name] = s

        # 3. Project-local skills (highest priority)
        project_dir = Path.cwd() / ".gula" / "skills"
        for s in load_skills_from_directory(project_dir, source="project"):
            self._skills[s.name] = s

    def get_skill(self, name: str) -> Optional[Skill]:
        """Get a skill by name."""
        return self._skills.get(name)

    def list_skills(self) -> List[Skill]:
        """Return all loaded skills sorted by category then name."""
        return sorted(self._skills.values(), key=lambda s: (s.category, s.name))

    def resolve(self, name: str, args: str) -> Optional[SkillResolution]:
        """Resolve a skill invocation into an expanded prompt.

        Args:
            name: Skill slug.
            args: User-provided arguments (replaces {input} in the template).

        Returns:
            SkillResolution with the expanded prompt, or None if not found.
        """
        skill = self._skills.get(name)
        if not skill:
            return None

        # Use format_map with a defaultdict to handle missing placeholders
        placeholders = defaultdict(str, input=args.strip())
        try:
            expanded = skill.prompt_template.format_map(placeholders)
        except (KeyError, ValueError):
            expanded = skill.prompt_template.replace("{input}", args.strip())

        return SkillResolution(
            expanded_prompt=expanded,
            system_prompt_addition=skill.system_prompt_addition,
            allowed_tools=skill.allowed_tools,
        )

    async def _fetch_backend_skills(self) -> List[Skill]:
        """Fetch skills from the backend API. Returns [] on failure."""
        try:
            config = await self._auth_service.ensure_valid_token()
            data = await self._api_client.get_skills(
                api_url=config.api_url,
                access_token=config.access_token,
            )
            skills_raw = data.get("skills", [])
            return [
                Skill(
                    name=s["name"],
                    display_name=s.get("display_name", s["name"]),
                    description=s.get("description", ""),
                    prompt_template=s.get("prompt_template", "{input}"),
                    source="backend",
                    system_prompt_addition=s.get("system_prompt_addition"),
                    allowed_tools=s.get("allowed_tools"),
                    icon=s.get("icon", ""),
                    category=s.get("category", "general"),
                )
                for s in skills_raw
                if "name" in s
            ]
        except Exception as exc:
            logger.debug("Could not fetch backend skills: %s", exc)
            return []
