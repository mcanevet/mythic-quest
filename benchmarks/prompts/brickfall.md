# Coverage variant — BrickFall (instancing stress profile)

~9 mechanics: everything RallyWall has plus a brick grid (repeated-node
instancing), per-brick destruction events, and a 3-lives system. Roughly
1.5–2× the implementation cost of the primary prompt — use when testing
code paths involving instancing (grids, spawners, bulk node creation),
not for routine regression benchmarking.

## The Prompt

```
Build a small breakout-style arcade game called "BrickFall":
a player-controlled paddle at the bottom keeps a ball in play,
the ball destroys bricks arranged in rows at the top, and the
player wins when all bricks are destroyed. The ball speeds up
slightly every 5 bricks broken. If the ball passes the paddle,
the player loses one of 3 lives; losing all 3 ends the game with
a lose screen. Controls: left/right arrow keys. The game is
complete when: all mechanics work in a live engine run, the full
QA gauntlet passes, and the win/lose screens display correctly.
```

## What this exercises that the primary does not

- Repeated-node instancing (brick rows via scene instantiation)
- Per-entity destruction + signal-driven scoring on many nodes
- Lives/lose-state machine (vs immediate game-over)
- Larger scene trees under the QA bot's interaction
