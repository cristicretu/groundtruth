# PATHFINDER

## the problem

1 billion people on this planet can't see.

the "solutions" are:
- **white cane** → invented 1921. pokes things. doesn't predict. doesn't plan.
- **guide dog** → 2 years training. $50k. dies in 10 years. you get one.
- **dotlumen** → $10k glasses. 10 sensors. looks like you're cosplaying a borg.
- **aira** → pays a human to watch your camera. $30/hour. not scalable.
- **apps** → "there is a chair in front of you" thanks GPT very helpful

all of these treat blind people as passengers. something to be guided. helped. accommodated.

fuck that.

## the insight

Tesla removed radar. comma never had it. turns out cameras + compute beats sensors.

an iPhone 17 Pro has:
- LiDAR (time-of-flight depth)
- 48MP camera at 60fps
- 6-axis IMU
- Neural Engine doing 35 TOPS
- ARKit SLAM that Apple spent $100M developing

that's more sensing than any robotics lab had in 2015. and it fits in your pocket.

pedestrians move at 1.4 m/s. cars move at 30 m/s. the problem is literally 20x easier than self-driving.

so why hasn't anyone built FSD for humans?

because the assistive tech industry is stuck in "help the disabled" mode instead of "give them superpowers" mode.

## what we're building

**PATHFINDER** — autonomous navigation for humans.

not a chatbot. not "AI describes your surroundings." a full perception-planning stack that runs at 10Hz and keeps you alive.

three layers:

**MICRO** (always on, 10Hz)
- don't hit things
- don't fall off things  
- don't get hit by things
- works with no destination. just walk.

**MESO** (street-level)
- follow sidewalks
- cross streets safely
- find entrances
- board the right bus

**MACRO** (city-level)
- google maps integration
- multimodal routing (walk, bus, train)
- "get me to the university"

the key insight: geometry for navigation, semantics for context.

you don't ask a VLM "is there a curb." you detect the 15cm height discontinuity in the depth map. that's robust. that works at night. that works when the model hallucinates.

VLM tells you "that's a bus stop." geometry tells you "path clear, 3 meters, slight left."

## how we win

| them | us |
|------|-----|
| $10,000 hardware | free app |
| custom glasses | phone in pocket |
| charge per month | open source |
| works in "supported areas" | works everywhere with GPS |
| 10 sensors | 1 phone |
| helps blind people | makes blind people autonomous |

dotlumen thinks this is a hardware problem. it's not. it's a software problem.

## the technical bet

1. **ARKit SLAM is good enough** — Apple's sensor fusion + depth is world-class. we build on top, not from scratch.

2. **small models beat big prompts** — a 500k param traversability CNN at 60fps beats GPT-4V at 0.5fps. use the right tool.

3. **geometry is robust** — curbs are 15cm. stairs are 18cm. these don't change. detect them with math, not vibes.

4. **audio is the interface** — not TTS spam. spatial audio. sound comes FROM the obstacle. your ears already do 3D localization.

5. **the data moat is real** — every user walking around is training data. every curb detected improves the model. this is the comma playbook.

## principles

- **ship weekly** — working software over planning documents
- **test with real users** — blind people, not sighted people with blindfolds
- **open source everything** — the mission is helping people, not building a moat
- **phone only** — if it needs extra hardware, we failed
- **robust over clever** — geometry > ML when geometry works

## the goal

a blind person downloads an app. puts phone in pocket. walks to work.

no training. no hardware. no subscription. no human in the loop.

just walks.

---

*"the best way to predict the future is to build it"*
— alan kay

*"the best way to help people is to make them not need help"*  
— us, now
