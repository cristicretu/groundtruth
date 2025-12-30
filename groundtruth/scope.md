
## MILESTONE 1: State of the Art
**Deadline: 30 Jan 2026 (35 days)**
**Deliverable: 2-4 pages + references**

### Literature Review (days 1-20)
- [ ] assistive navigation systems
  - [ ] NavCog (CMU) - bluetooth beacon based
  - [ ] Lazarillo - GPS + points of interest
  - [ ] Seeing AI (Microsoft) - scene description
  - [ ] Aira - human remote assistance
  - [ ] dotlumen - hardware glasses, LiDAR array
- [ ] visual SLAM
  - [ ] ORB-SLAM, LSD-SLAM classics
  - [ ] ARKit/ARCore commercial implementations
  - [ ] neural SLAM (recent deep learning approaches)
- [ ] traversability estimation
  - [ ] classical (geometry-based, from robotics)
  - [ ] learned (semantic segmentation for navigation)
  - [ ] hybrid approaches
- [ ] vision-language models for navigation
  - [ ] ViNT, NaVid, LM-Nav
  - [ ] VLM grounding for robotics
- [ ] depth estimation
  - [ ] LiDAR vs monocular vs stereo
  - [ ] MiDaS, Depth Anything, Apple depth APIs
- [ ] spatial audio for navigation
  - [ ] existing research on 3D audio interfaces
  - [ ] cognitive load studies

### Document Writing (days 21-30)
- [ ] structure: intro, categories of related work, gap analysis, our position
- [ ] write 2-4 pages summarizing landscape
- [ ] reference list (aim for 25-40 papers)
- [ ] submit

### Parallel: Initial Development (days 1-30)
- [ ] Xcode project setup
- [ ] ARKit pipeline: depth + RGB + pose streaming
- [ ] record 5 hours of walking data
- [ ] basic elevation grid working
- [ ] basic obstacle detection working
- [ ] prove core technical approach is viable

---

## MILESTONE 2: App Requirements
**Deadline: 15 Feb 2026 (16 days after M1)**
**Deliverable: 6-10 pages**

### Requirements Document (days 1-10)
- [ ] functional requirements
  - [ ] FR1: detect obstacles within 5m range
  - [ ] FR2: detect elevation changes >10cm
  - [ ] FR3: provide directional audio feedback
  - [ ] FR4: provide haptic warnings
  - [ ] FR5: navigate to GPS destination
  - [ ] FR6: detect crosswalks and traffic lights
  - [ ] FR7: identify semantic landmarks via VLM
  - [ ] FR8: run at minimum 10Hz update rate
- [ ] non-functional requirements
  - [ ] NFR1: iPhone 14 Pro or newer (LiDAR required)
  - [ ] NFR2: <100ms latency from detection to feedback
  - [ ] NFR3: battery life >2 hours continuous use
  - [ ] NFR4: work offline for core navigation
  - [ ] NFR5: accessible UI (VoiceOver compatible)
- [ ] system architecture diagram
- [ ] data flow diagram
- [ ] use case descriptions
  - [ ] UC1: walk safely without destination
  - [ ] UC2: navigate to specific address
  - [ ] UC3: cross street safely
  - [ ] UC4: find and board correct bus
- [ ] user personas
- [ ] success metrics definition
- [ ] submit 6-10 page document

### Parallel: Development Sprint 1 (days 1-16)
- [ ] floor detection via RANSAC
- [ ] curb detection (height discontinuities)
- [ ] stair detection (periodic planes)
- [ ] spatial audio prototype (AVAudioEngine 3D)
- [ ] haptic patterns (CoreHaptics)
- [ ] 10Hz main loop stable
- [ ] **DEMO**: walk around room without collisions

---

## MILESTONE 3: Initial Version + Thesis Structure
**Deadline: 15 Mar 2026 (28 days after M2)**
**Deliverable: Working prototype + 20-25 pages**

### Thesis Document (days 1-28)
- [ ] thesis structure outline
- [ ] Chapter 1: Introduction (3-4 pages)
  - [ ] problem statement
  - [ ] motivation and impact
  - [ ] research questions
  - [ ] contributions
  - [ ] document structure
- [ ] Chapter 2: Background (4-5 pages)
  - [ ] visual impairment statistics
  - [ ] current assistive technologies
  - [ ] technical foundations (SLAM, depth sensing, path planning)
- [ ] Chapter 3: Related Work (8-10 pages)
  - [ ] expand state of the art document
  - [ ] detailed comparison table
  - [ ] gap analysis
  - [ ] positioning our approach
- [ ] Chapter 4: System Design (5-6 pages) - initial version
  - [ ] architecture overview
  - [ ] component descriptions
  - [ ] design decisions and rationale

### Software: Initial Version (days 1-28)
- [ ] **Perception module complete**
  - [ ] elevation grid from LiDAR
  - [ ] obstacle detection and tracking
  - [ ] curb/stair detection
  - [ ] dynamic object tracking (people)
- [ ] **Traversability network v1**
  - [ ] collect 10 hours labeled data
  - [ ] train MobileNetV3-based model
  - [ ] CoreML export and integration
  - [ ] runs at 30fps on Neural Engine
- [ ] **Path planning v1**
  - [ ] 2D occupancy grid
  - [ ] A* with custom cost function
  - [ ] basic path following
- [ ] **Audio interface v1**
  - [ ] obstacle direction + distance
  - [ ] path guidance ("slight left")
  - [ ] warning sounds
- [ ] **Haptic interface v1**
  - [ ] imminent collision pattern
  - [ ] curb ahead pattern
  - [ ] navigation confirmation
- [ ] **DEMO**: navigate around building, avoid obstacles, follow path

---

## MILESTONE 4: Alpha Version + Application Chapter
**Deadline: 15 Apr 2026 (31 days after M3)**
**Deliverable: Functional app + application chapter**

### Thesis: Application Chapter Initial (days 1-31)
- [ ] Chapter 5: Implementation (10-12 pages)
  - [ ] development environment and tools
  - [ ] ARKit integration details
  - [ ] perception pipeline implementation
  - [ ] traversability network architecture and training
  - [ ] path planning algorithm
  - [ ] audio/haptic interface design
  - [ ] code snippets for key components
  - [ ] performance optimizations

### Software: Alpha Version (days 1-31)
- [ ] **Macro navigation**
  - [ ] Google Maps SDK integration
  - [ ] route parsing to waypoints
  - [ ] GPS + visual odometry fusion
  - [ ] turn-by-turn guidance
  - [ ] arrival detection
- [ ] **Meso navigation**
  - [ ] crosswalk detection
  - [ ] traffic light state (basic)
  - [ ] bus stop identification
  - [ ] entrance/door detection
- [ ] **VLM integration**
  - [ ] FastVLM running on device
  - [ ] scene query on demand
  - [ ] sign reading
  - [ ] semantic landmark description
- [ ] **UI/UX**
  - [ ] VoiceOver compatible
  - [ ] settings screen
  - [ ] onboarding tutorial
- [ ] **DEMO**: full outdoor navigation to destination
- [ ] **BEGIN USER RECRUITMENT** for studies

---

## MILESTONE 5: Beta Version + Experiments Chapter
**Deadline: 01 Jun 2026 (47 days after M4)**
**Deliverable: Advanced app + experiments**

### User Studies (days 1-30)
- [ ] IRB approval (submit in April, should be approved by now)
- [ ] recruit 8-10 blind participants
- [ ] study protocol finalized
  - [ ] Task 1: indoor navigation (find specific room)
  - [ ] Task 2: outdoor navigation (walk to destination)
  - [ ] Task 3: obstacle course (curbs, people, objects)
  - [ ] Baseline: same tasks with white cane only
- [ ] run studies (1-2 participants per day)
- [ ] collect metrics
  - [ ] task completion time
  - [ ] collision count
  - [ ] near-miss count
  - [ ] NASA-TLX (cognitive load)
  - [ ] System Usability Scale (SUS)
  - [ ] qualitative interview

### Thesis: Experiments Chapter (days 20-47)
- [ ] Chapter 6: Evaluation (12-15 pages)
  - [ ] study design and methodology
  - [ ] participant demographics
  - [ ] experimental setup
  - [ ] results with tables and figures
  - [ ] statistical analysis
  - [ ] qualitative findings
  - [ ] comparison with baseline
  - [ ] discussion of results

### Thesis: Application Chapter Advanced (days 30-47)
- [ ] expand implementation details
- [ ] add figures and diagrams
- [ ] performance benchmarks
- [ ] edge cases and error handling

### Software: Beta Version (days 1-47)
- [ ] bug fixes from user studies
- [ ] performance optimization
- [ ] battery optimization
- [ ] crash hardening
- [ ] edge case handling
- [ ] improved audio/haptic based on user feedback
- [ ] FSD-style visualization (for demos)

---

## MILESTONE 6: Final Version
**Deadline: 15 Jun 2026 (14 days after M5)**
**Deliverable: Final app + 45-50 page thesis**

### Thesis Completion (days 1-14)
- [ ] Chapter 7: Discussion (4-5 pages)
  - [ ] interpretation of results
  - [ ] comparison with dotlumen and alternatives
  - [ ] limitations
  - [ ] threats to validity
- [ ] Chapter 8: Conclusion (2-3 pages)
  - [ ] summary of contributions
  - [ ] future work
  - [ ] broader impact
- [ ] Abstract (1 page)
- [ ] Acknowledgments
- [ ] Table of Contents, List of Figures, List of Tables
- [ ] References (clean up, consistent format)
- [ ] Appendices
  - [ ] user study materials
  - [ ] additional results
  - [ ] code repository link
- [ ] full proofread
- [ ] formatting check against university template
- [ ] advisor review + final revisions
- [ ] **SUBMIT**

### Software: Final Version (days 1-14)
- [ ] final bug fixes
- [ ] code cleanup and documentation
- [ ] README with setup instructions
- [ ] demo video (3-5 min)
- [ ] public GitHub release
- [ ] **SUBMIT**

---

## ONGOING TASKS (entire project)

### Weekly
- [ ] advisor meeting (15-30 min)
- [ ] commit code (minimum 3x/week)
- [ ] update project log

### Monthly
- [ ] demo video for Twitter/YouTube
- [ ] backup everything

### Critical Path Items
- [ ] **IRB application**: submit by March 15 (takes 4-6 weeks to approve)
- [ ] **user recruitment**: start reaching out to blind community in March
- [ ] **device testing**: ensure iPhone 17 Pro works, have backup device

---

## RISK MITIGATION

| Risk | Mitigation |
|------|------------|
| ARKit tracking fails outdoors | test early, have fallback to GPS-only mode |
| VLM too slow | can defer VLM features, core is geometric |
| can't recruit blind users | contact local blind association NOW |
| IRB takes too long | submit early, have contingency protocol |
| traversability model doesn't work | geometric-only fallback is still viable |
| battery drains fast | profile early, reduce update rate if needed |

---

## SUCCESS CRITERIA

### Minimum Viable Thesis (must have)
- [ ] working app that detects obstacles and provides audio feedback
- [ ] path planning that avoids obstacles
- [ ] user study with 5+ blind participants
- [ ] 45+ page thesis with all required chapters

### Target (should have)
- [ ] full outdoor navigation to destination
- [ ] VLM integration for semantic info
- [ ] user study with 8+ participants
- [ ] statistically significant improvement over baseline

### Stretch (nice to have)
- [ ] bus boarding assistance
- [ ] traffic light detection
- [ ] works at night
- [ ] open source release with community adoption
