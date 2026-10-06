# Changelog

## [12.1.5-2] - 2026-10-06

- Updated for WoW 12.1.5.

### Features

- Add Marksmanship Hunter's Harrier's Cry and track Primal Rage through the active pet, including pet swaps, deaths, resurrections, and specialization changes.
- Add readiness alerts for usable Void-Touched Drums and Thunderous Drums carried by characters without an available supported class or pet ability.

### Fixes

- Start the final 30-second countdown automatically even when the alert was previously hidden.
- Hide automatic alerts while dead, outside supported instances, or when readiness cannot be confirmed from restricted data; reset placement previews to a consistent ready label.

### Compatibility

- Remove reliance on legacy spellbook compatibility functions when detecting class abilities.

## [12.1.0-1] - 2026-08-10

### Features

- Show when the player's Bloodlust, Heroism, Time Warp, Primal Rage, or Fury of the Aspects is ready in a group instance.
- Display a 30-second countdown as the ability cooldown or Sated-style debuff expires when the timing is available.
- Provide a movable, lockable display with per-character position persistence and test and debug commands.

### Compatibility

- Support World of Warcraft Retail interfaces 12.0.7 and 12.1.0.
- Handle secret aura and cooldown values safely on the Midnight client.
