# PATHFINDER

## the problem

1 billion people on this planet can't see.

the "solutions" are:
- **white cane** — invented 1921. pokes things. doesn't predict. doesn't plan.
- **guide dog** — 2 years training. $50k. dies in 10 years. you get one.
- **dotlumen** — $10k glasses. 10 sensors. looks like you're cosplaying a borg.
- **aira** — pays a human to watch your camera. $30/hour. not scalable.
- **apps** — "there is a chair in front of you" thanks GPT very helpful

all of these treat blind people as passengers. something to be guided. helped. accommodated.

fuck that.

## the insight

Tesla removed radar. comma never had it. turns out cameras + compute beats sensors.

an iPhone 14 Pro has:
- LiDAR (time-of-flight depth, 0-5m precise)
- 48MP camera at 60fps (0-50m visual)
- 6-axis IMU
- Neural Engine doing 35 TOPS
- ARKit SLAM that Apple spent $100M developing

that's more sensing than any robotics lab had in 2015. and it fits in your pocket.

pedestrians move at 1.4 m/s. cars move at 30 m/s. the problem is literally 20x easier than self-driving.

so why hasn't anyone built FSD for humans?

because the assistive tech industry is stuck in "help the disabled" mode instead of "give them superpowers" mode.

## what we're building

**PATHFINDER** — autonomous navigation for humans.

not a chatbot. not "AI describes your surroundings." a full perception-planning stack that runs at 30Hz and keeps you alive.

### the architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     PERCEPTION STACK                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │   LiDAR      │  │   Camera     │  │    IMU       │       │
│  │  (0-5m)      │  │  (0-50m)     │  │  (motion)    │       │
│  │  SURVIVAL    │  │  SCENE       │  │  POSE        │       │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘       │
│         │                 │                 │                │
│         ▼                 ▼                 ▼                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ ARKit Mesh   │  │ MiDaS Depth  │  │ Pose Update  │       │
│  │ + Elevation  │  │ YOLO Objects │  │              │       │
│  │ + Steps      │  │ Segmentation │  │              │       │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘       │
│         └────────────┬────┴─────────────────┘                │
│                      ▼                                       │
│              ┌──────────────────┐                            │
│              │  OCCUPANCY GRID  │  ← Tesla-style voxels      │
│              │  + ELEVATION MAP │  ← Steps, curbs, ramps     │
│              │  + TRACKED OBJS  │  ← Cars, bikes, people     │
│              └────────┬─────────┘                            │
│                       ▼                                      │
│              ┌──────────────────┐                            │
│              │   WORLD MODEL    │  ← Single source of truth  │
│              └────────┬─────────┘                            │
│                       │                                      │
│         ┌─────────────┼─────────────┐                        │
│         ▼             ▼             ▼                        │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐                  │
│   │   Path   │  │  Audio   │  │  Stream  │                  │
│   │ Planning │  │ Feedback │  │  Debug   │                  │
│   └──────────┘  └──────────┘  └──────────┘                  │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### three layers of navigation

**MICRO** (always on, 30Hz) — SURVIVAL
- don't hit things (LiDAR occupancy)
- don't fall off things (elevation detection)
- don't get hit by things (object tracking)
- works with no destination. just walk.

**MESO** (street-level, 10Hz) — SCENE
- follow sidewalks (semantic segmentation)
- cross streets safely (traffic light detection)
- find entrances (door detection)
- board the right bus (OCR)

**MACRO** (city-level, 0.1Hz) — ROUTING
- google maps integration
- multimodal routing (walk, bus, train)
- "get me to the university"

## the key insight: geometry > ontology

Tesla figured this out. They stopped asking "what is that object?" and started asking "is that space occupied?"

you don't ask a VLM "is there a curb." you detect the 15cm height discontinuity in the depth map. that's robust. that works at night. that works when the model hallucinates.

```
BEFORE (object detection):
  "Is that a truck?" → Fixed 7x3 rectangle → Misses ladder on top → CRASH

AFTER (occupancy):
  "Is that space occupied?" → Volume marked occupied → Safe
```

same principle:
- curbs are 15cm height changes. detect them with geometry.
- stairs are repeating 18cm steps. detect them with geometry.
- doors are openings in walls. detect them with geometry.

VLM tells you "that's a bus stop." geometry tells you "path clear, 3 meters, slight left."

**geometry for navigation. semantics for context.**

## the sensing stack

| Range | Source | What We Get | Latency |
|-------|--------|-------------|---------|
| 0-5m | LiDAR + ARKit Mesh | Precise 3D, steps, walls | 33ms |
| 5-30m | MiDaS monocular depth | Extended depth estimate | 33ms |
| 0-50m | YOLO object detection | Cars, bikes, people | 33ms |
| 0-30m | Semantic segmentation | Sidewalk vs road | 66ms |
| on-demand | VLM | "What bus is this?" | 500ms |

LiDAR is the last line of defense. camera extends our vision. ML fills the gaps.

## elevation is everything

for a sighted person: a 15cm step is nothing.
for a blind person: a 15cm step is a fall.

we detect:
- **steps** (5-20cm) — warn, but walkable
- **curbs** (15-25cm) — heavy warning
- **stairs** (repeating pattern) — announce
- **ramps** (gradual slope) — safe path
- **drop-offs** (>30cm) — STOP

all from geometry. no ML needed for this.

## how we win

| them | us |
|------|-----|
| $10,000 hardware | free app |
| custom glasses | phone in pocket |
| charge per month | open source |
| works in "supported areas" | works everywhere with GPS |
| 10 sensors | 1 phone |
| helps blind people | makes blind people autonomous |
| object detection | occupancy grid |
| "there's a chair" | "path clear, slight left" |

dotlumen thinks this is a hardware problem. it's not. it's a software problem.

## the technical bet

1. **ARKit mesh is good enough** — Apple's scene reconstruction gives us geometry. we build occupancy grids from it.

2. **hybrid sensing beats pure ML** — LiDAR for precision close, camera+ML for range. right tool for right distance.

3. **occupancy > detection** — don't classify, just mark occupied. handles unknown objects, ladders, weird shapes.

4. **elevation is geometric** — steps are height discontinuities. detect them with math, not vibes.

5. **audio is the interface** — not TTS spam. spatial audio. sound comes FROM the obstacle. your ears already do 3D localization.

6. **the data moat is real** — every user walking around improves the system. every curb detected, every path walked. this is the comma playbook.

## the goal

**Phase 1: Mall to University**

a blind person:
1. exits the mall (indoor navigation, doors, escalators)
2. walks to the bus stop (outdoor, sidewalks, crossings)
3. boards the right bus (OCR, VLM)
4. exits at the right stop (GPS, audio)
5. walks to university (outdoor navigation)
6. finds room 304 (indoor, sign reading)
7. sits down

no training. no hardware. no subscription. no human in the loop.

just walks.

## principles

- **ship weekly** — working software over planning documents
- **test with real users** — blind people, not sighted people with blindfolds
- **open source everything** — the mission is helping people, not building a moat
- **phone only** — if it needs extra hardware, we failed
- **geometry > ML** — when geometry works, use geometry
- **occupancy > detection** — don't ask what, ask where

---
