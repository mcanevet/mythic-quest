# Primary benchmark prompt — RallyWall (fast feedback profile)

Smallest game that still exercises every harness path: collision, input,
signals, UI, win/lose state, speed progression. ~6 mechanics, no instancing,
no AI opponent, no lives — chosen for **lowest token burn and fastest
turnaround**, per the benchmark goal (library correctness + token economy).

## The Prompt

```
Build a small single-player reflex game called "RallyWall":
a player-controlled paddle at the bottom keeps a ball in play
against the top, left, and right walls. Every time the paddle
hits the ball, the score increases by 1 and the ball speeds up
by 5%. If the ball passes the paddle, the game ends immediately
and shows the final score with a "play again" key. The player
wins by reaching a score of 15, showing a win screen. Controls:
left/right arrow keys. The game is complete when: all mechanics
work in a live engine run, the full QA gauntlet passes, and the
win/lose screens display correctly.
```

## Why this shape

- **Spec-light but checkable** — 6 unambiguous mechanics (movement,
  3-wall bounce, paddle bounce + scoring, speed-up, lose screen with
  final score + restart, win screen at 15) so the functional-QA
  gauntlet can verify each one, while leaving implementation, scene
  layout, and pacing decisions to the genesis / backlog-grooming
  pipeline.
- **Fewer entities than the breakout variant** → fewer plan files →
  fewer poppy spawns → less token burn per run. Differences in outcome
  across runs measure the harness, not the prompt.
- **Win/lose screens keep the QA gauntlet meaningful** — UI-state
  verification is where regression-prone harness paths live.
- **Known coverage gap:** no repeated-node instancing. When that path
  needs testing, use the `brickfall.md` variant instead.
