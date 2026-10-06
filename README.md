# Lust Ready

Lust Ready displays a movable alert when your character's Bloodlust-equivalent ability or carried drums are ready in a group instance. Outside combat, it also shows a countdown during the final 30 seconds of the cooldown or Sated-style debuff when timing data is available.

## Supported abilities

| Character | Tracked ability |
| --- | --- |
| Shaman | Heroism or Bloodlust |
| Mage | Time Warp |
| Evoker | Fury of the Aspects |
| Marksmanship Hunter | Harrier's Cry |
| Hunter with an active Ferocity pet | The pet's Primal Rage |
| Any class without an available supported class or pet ability | Usable Void-Touched Drums or Thunderous Drums carried in bags |

A known class ability or an available pet's Primal Rage takes priority over drums, including while that ability is on cooldown. Pet swaps, dismissals, deaths, resurrections, and specialization changes refresh detection automatically.

Drums display **Drums Ready** or **Drums in N**. Banked items and other drum versions are not tracked. Characters without a supported ability or usable carried drums have no automatic alert.

## Features

- Accounts for Sated, Exhaustion, Temporal Displacement, Insanity, and Fatigued debuffs.
- Shows the alert in party, raid, scenario, and battleground instances; automatic alerts are hidden in arenas and the open world.
- Starts the countdown automatically when readiness is 30 seconds away, even if the display was hidden.
- Saves the display position and lock state per character.
- Shows only confirmed readiness in combat. Restricted or unavailable data hides the automatic alert.

## Usage

On first use, drag the unlocked display to the desired position, then use `/lr lock` to lock it and enable automatic visibility. Run the same command to unlock it again later.

The unlocked display and `/lr test` are placement previews: they show **Lust Ready** regardless of your class, cooldown, or location. Turn testing off and lock the display to see actual readiness.

## Commands

- `/lr lock` or `/lr l` — Lock or unlock the display.
- `/lr test` or `/lr t` — Toggle the display for testing.
- `/lr debug` or `/lr d` — Toggle debug messages.
- `/lr` — List available commands.

## Compatibility

Lust Ready supports World of Warcraft Retail 12.1.5.
