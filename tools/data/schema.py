"""Core data schema for HoopClone.

These dataclasses are the canonical, engine-agnostic representation of league
data. The Python toolchain produces them; ``to_dict`` serialises them to the
JSON that the Godot client loads at runtime. Keep this module dependency-free
(stdlib only) so it imports cleanly in any environment.
"""

from __future__ import annotations

from dataclasses import dataclass, field, asdict
from typing import Optional

# The 13 game attributes, shared verbatim with the sandbox and the Godot engine
# (game/core/attributes.gd mirrors this list and ordering).
ATTRIBUTES: tuple[str, ...] = (
    "shooting",
    "three_pt",
    "finishing",
    "dunking",
    "passing",
    "handles",
    "steals",
    "hustle",
    "hops",
    "rebounding",
    "perim_d",
    "inside_d",
    "speed",
)

POSITIONS: tuple[str, ...] = ("PG", "SG", "SF", "PF", "C")


@dataclass
class AttributeBlock:
    """A player's 13 rated attributes, each on a 0-99 scale."""

    shooting: int = 50
    three_pt: int = 50
    finishing: int = 50
    dunking: int = 50
    passing: int = 50
    handles: int = 50
    steals: int = 50
    hustle: int = 50
    hops: int = 50
    rebounding: int = 50
    perim_d: int = 50
    inside_d: int = 50
    speed: int = 50

    def overall(self) -> int:
        """Unweighted mean of all attributes, clamped to 0-99."""
        vals = [getattr(self, a) for a in ATTRIBUTES]
        return max(0, min(99, round(sum(vals) / len(vals))))

    def to_dict(self) -> dict[str, int]:
        return {a: int(getattr(self, a)) for a in ATTRIBUTES}


@dataclass
class Player:
    player_id: str
    name: str
    position: str
    jersey: int
    attributes: AttributeBlock = field(default_factory=AttributeBlock)
    # Optional cosmetic / pipeline metadata (asset URLs, archetype, etc.).
    archetype: str = ""
    asset_id: str = ""

    def to_dict(self) -> dict:
        return {
            "player_id": self.player_id,
            "name": self.name,
            "position": self.position,
            "jersey": self.jersey,
            "archetype": self.archetype,
            "asset_id": self.asset_id,
            "overall": self.attributes.overall(),
            "attributes": self.attributes.to_dict(),
        }


@dataclass
class Team:
    team_id: str
    name: str
    abbreviation: str
    primary_color: str = "#7a0019"
    secondary_color: str = "#0b0e13"
    players: list[Player] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "team_id": self.team_id,
            "name": self.name,
            "abbreviation": self.abbreviation,
            "primary_color": self.primary_color,
            "secondary_color": self.secondary_color,
            "players": [p.to_dict() for p in self.players],
        }


@dataclass
class League:
    name: str = "HoopClone League"
    season: str = "2025-26"
    teams: list[Team] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "season": self.season,
            "teams": [t.to_dict() for t in self.teams],
        }
