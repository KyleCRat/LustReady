# Lust Ready

Lust Ready displays a movable alert when your character's Bloodlust- or Heroism-equivalent ability is ready in a group instance. When timing data is available, it also shows a countdown during the final 30 seconds of the ability cooldown or Sated-style debuff.

## Features

- Detects Heroism, Bloodlust, Time Warp, Primal Rage, and Fury of the Aspects known by the player.
- Accounts for Sated, Exhaustion, Temporal Displacement, Insanity, and Fatigued debuffs.
- Shows the alert in party, raid, scenario, arena, and battleground instances.
- Saves the display position per character.
- Handles restricted aura and cooldown values on current Retail clients.

## Usage

Use `/lr lock` to unlock the display, drag it to the desired position, and run the command again to lock it. The unlocked display remains visible while positioning it.

## Commands

- `/lr lock` or `/lr l` — Lock or unlock the display.
- `/lr test` or `/lr t` — Toggle the display for testing.
- `/lr debug` or `/lr d` — Toggle debug messages.
- `/lr` — List available commands.

## Compatibility

Lust Ready supports World of Warcraft Retail interfaces 12.0.7 and 12.1.0.
