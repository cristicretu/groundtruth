# PATHFINDER - Development Scope (Revised)

## Overview

Building a Tesla FSD-style perception stack for blind navigation. The goal is to understand the 3D scene around the user well enough to navigate from inside a mall to inside a university classroom.

**Core Architecture:** Occupancy Grid + Elevation Map + Object Tracking

**Key Insight:** Geometry for navigation, semantics for context.

---

## PHASE 1: Foundation (Week 1-2)
**Goal:** ARKit mesh to occupancy grid with elevation detection

### Deliverables
- [ ] `OccupancyGrid.swift` - Proper grid data structure with cell states
- [ ] `ElevationAnalyzer.swift` - Step/curb/ramp detection from mesh geometry
- [ ] Clean ARKit mesh extraction in `Sensors.swift`
- [ ] Mac Bird's Eye View visualization (basic 2D grid)
- [ ] Stream occupancy + elevation data to Mac

### OccupancyGrid Structure
```swift
enum CellState: UInt8 {
    case unknown = 0
    case free = 1
    case occupied = 2
    case step = 3      // 5-20cm elevation change
    case curb = 4      // >20cm elevation change
    case ramp = 5      // gradual slope
}

struct OccupancyGrid {
    let resolution: Float = 0.1  // 10cm cells
    let size: Int = 200          // 20m x 20m
    var cells: [CellState]
    var elevation: [Float]       // height relative to user floor
    var userPosition: (x: Int, y: Int)
    var userHeading: Float
}
```

### Elevation Detection Rules
| Condition | Classification |
|-----------|----------------|
| Height change 5-20cm | Step (warn but walkable) |
| Height change >20cm | Curb (heavy warning) |
| Slope <10° | Ramp (safe) |
| Slope >15° | Steep (caution) |
| Repeating 15-20cm steps | Stairs |

### Success Criteria
- [ ] Walk indoors, see occupancy grid on Mac
- [ ] Steps detected and highlighted in BEV
- [ ] Curbs detected and highlighted
- [ ] Grid updates at 10Hz

---

## PHASE 2: Extended Depth (Week 3-4)
**Goal:** Add MiDaS monocular depth for 5-30m range

### Deliverables
- [ ] `MonocularDepth.swift` - MiDaS CoreML inference
- [ ] `DepthFusion.swift` - Combine LiDAR + monocular depth
- [ ] MiDaS-small.mlmodel integrated (~25MB)

### Depth Fusion Strategy
```
Distance 0-5m:   Trust LiDAR (centimeter accuracy)
Distance 5-15m:  Blend LiDAR edge + MiDaS
Distance 15-30m: MiDaS only (scaled to real-world units)
Distance >30m:   Unknown
```

### Success Criteria
- [ ] See obstacles at 20-30m in BEV
- [ ] Smooth transition from LiDAR to monocular
- [ ] No visible "seam" at 5m boundary
- [ ] Runs at 30fps on Neural Engine

---

## PHASE 3: Object Detection (Week 5-6)
**Goal:** Add YOLOv8 for cars, bikes, people with tracking

### Deliverables
- [ ] `ObjectDetector.swift` - YOLO CoreML inference
- [ ] `ObjectTracker.swift` - Multi-object tracking with Kalman filter
- [ ] YOLOv8n.mlmodel integrated (~6MB)
- [ ] Velocity estimation from tracking

### Tracked Object Types
| Type | Priority | Why |
|------|----------|-----|
| Car | HIGH | Can kill you |
| Bicycle | HIGH | Fast, quiet, dangerous |
| Person | MEDIUM | Moving obstacle |
| Bus | MEDIUM | Need to board |
| Dog | LOW | Unpredictable |

### Mac BEV Enhancement
- [ ] Show tracked objects with icons
- [ ] Velocity vectors (arrows)
- [ ] Predicted paths (dashed lines)
- [ ] Object labels with distance

### Success Criteria
- [ ] "Car approaching from left, 20m" detected
- [ ] Velocity estimation within 20% accuracy
- [ ] Track maintained across frames (no ID switching)
- [ ] Runs at 30fps alongside depth

---

## PHASE 4: World Model Fusion (Week 7-8)
**Goal:** Unified world model combining all inputs

### Deliverables
- [ ] `WorldModel.swift` - Complete rewrite, single source of truth
- [ ] `SensorFusion.swift` - Kalman filter for sensor fusion
- [ ] Temporal consistency (objects don't flicker)
- [ ] Confidence tracking per cell

### World Model Contents
```swift
class WorldModel {
    // Static environment
    var occupancyGrid: OccupancyGrid      // Free/occupied/step/curb
    var elevationMap: ElevationMap        // Height at each cell
    
    // Dynamic objects
    var trackedObjects: [TrackedObject]   // Cars, bikes, people
    
    // User state
    var userPose: Pose                    // Position + heading
    var floorHeight: Float                // Reference floor
    
    // Derived
    var traversabilityMap: TraversabilityMap  // Where can we walk?
    var nearestThreat: Threat?            // Most urgent warning
}
```

### Success Criteria
- [ ] All sensor data flows into single model
- [ ] No flickering objects or cells
- [ ] Consistent world representation across frames
- [ ] Can query "what's at position (x, z)?"

---

## PHASE 5: Path Planning (Week 9-10)
**Goal:** A* path finding on occupancy grid

### Deliverables
- [ ] `PathPlanner.swift` - A* with custom cost function
- [ ] `NavigationCore.swift` - High-level navigation commands
- [ ] Dynamic replanning when obstacles appear
- [ ] Safe corridor detection

### Cost Function
```swift
func cost(from: Cell, to: Cell) -> Float {
    switch to.state {
    case .occupied: return .infinity    // Can't walk through
    case .step:     return 2.0          // Penalize but allow
    case .curb:     return 5.0          // Heavy penalty
    case .ramp:     return 1.2          // Slight penalty
    case .free:     return 1.0          // Base cost
    case .unknown:  return 3.0          // Discourage unknown
    }
}
```

### Navigation Commands
| Situation | Output |
|-----------|--------|
| Path clear ahead | "Clear" |
| Obstacle left | "Slight right" |
| Step ahead | "Step up in 2 meters" |
| Curb ahead | "Curb in 1 meter" |
| No safe path | "Stop, obstacle" |

### Success Criteria
- [ ] Find path around obstacles
- [ ] Avoid steps when alternative exists
- [ ] Warn about unavoidable steps
- [ ] Replan within 100ms when obstacle appears

---

## PHASE 6: Polish and Integration (Week 11-12)
**Goal:** GPS integration, user feedback, end-to-end testing

### Deliverables
- [ ] `GPSRouting.swift` - Google Maps Directions API
- [ ] `AudioFeedback.swift` - Spatial audio from obstacle direction
- [ ] VoiceOver-compatible UI
- [ ] End-to-end demo video

### GPS Integration
```
Google Maps API → Route waypoints → Local path planning
                                          ↓
                                   "Turn left in 50m"
                                   "Bus stop ahead"
                                   "Cross at crosswalk"
```

### Audio Feedback Types
| Type | Sound | Meaning |
|------|-------|---------|
| Obstacle | Beep from direction | Something there |
| Step | Rising tone | Elevation change ahead |
| Clear path | Silence | Keep walking |
| Turn | Spatial chime | Turn direction |
| Arrival | Success tone | Reached waypoint |

### Success Criteria
- [ ] Navigate outdoor route with GPS
- [ ] Spatial audio indicates obstacle direction
- [ ] VoiceOver reads all UI elements
- [ ] Demo: Walk 500m following route

---

## MILESTONE ALIGNMENT WITH THESIS

| Thesis Milestone | Project Phase | Deadline |
|------------------|---------------|----------|
| M1: State of Art | Research + Phase 1 start | 30 Jan 2026 |
| M2: Requirements | Phase 1-2 complete | 15 Feb 2026 |
| M3: Initial Version | Phase 3-4 complete | 15 Mar 2026 |
| M4: Alpha Version | Phase 5-6 complete | 15 Apr 2026 |
| M5: Beta + Studies | User testing | 01 Jun 2026 |
| M6: Final | Thesis submission | 15 Jun 2026 |

---

## ML MODELS REQUIRED

| Model | Size | FPS | Source | Phase |
|-------|------|-----|--------|-------|
| MiDaS-small | ~25MB | 30 | Apple CoreML Zoo | 2 |
| YOLOv8n | ~6MB | 30 | Ultralytics | 3 |
| SegFormer-B0 | ~15MB | 15 | HuggingFace | 6 (optional) |

All models run on Neural Engine. No cloud required.

---

## NON-FUNCTIONAL REQUIREMENTS

| ID | Requirement | Target |
|----|-------------|--------|
| NFR1 | Device | iPhone 14 Pro or newer (LiDAR required) |
| NFR2 | Latency | <100ms from detection to feedback |
| NFR3 | Battery | >2 hours continuous use |
| NFR4 | Offline | Core navigation works without internet |
| NFR5 | Accessibility | VoiceOver compatible |
| NFR6 | Frame rate | 30Hz sensor processing |
| NFR7 | Grid update | 10Hz occupancy grid refresh |

---

## SUCCESS CRITERIA (MVP)

### Must Have
- [ ] Occupancy grid from ARKit mesh
- [ ] Step/curb detection from elevation
- [ ] Object detection (cars, bikes, people)
- [ ] Spatial audio warnings
- [ ] Mac BEV visualization
- [ ] User study with 5+ blind participants

### Should Have
- [ ] Extended depth (MiDaS)
- [ ] Object tracking with velocity
- [ ] Path planning around obstacles
- [ ] GPS route following

### Nice to Have
- [ ] Traffic light detection
- [ ] Bus number OCR
- [ ] Indoor sign reading (VLM)
- [ ] Works at night

---

## RISK MITIGATION

| Risk | Mitigation |
|------|------------|
| ARKit mesh too sparse | Use depth map fallback, increase scan density |
| MiDaS depth inaccurate | Calibrate scale factor, blend with LiDAR overlap |
| YOLO misses objects | Conservative detection, track over time |
| Battery drains fast | Profile early, reduce model frequency if needed |
| Can't recruit blind users | Contact blind association early (March) |
| Steps not detected | Lower threshold, test on real steps |

---

## WEEKLY SCHEDULE

### Week 1-2: Foundation
- Day 1-3: OccupancyGrid structure
- Day 4-6: ElevationAnalyzer
- Day 7-10: Mac BEV basic
- Day 11-14: Streaming + testing

### Week 3-4: Extended Depth
- Day 1-4: MiDaS integration
- Day 5-7: Depth fusion
- Day 8-14: Testing + tuning

### Week 5-6: Object Detection
- Day 1-4: YOLO integration
- Day 5-7: Object tracker
- Day 8-14: BEV enhancement + testing

### Week 7-8: World Model
- Day 1-7: WorldModel rewrite
- Day 8-14: Sensor fusion + testing

### Week 9-10: Path Planning
- Day 1-7: A* implementation
- Day 8-14: Navigation commands + testing

### Week 11-12: Polish
- Day 1-4: GPS integration
- Day 5-7: Audio feedback
- Day 8-14: End-to-end testing + demo

---

## THE DEMO

**Scenario:** Navigate from university entrance to room 304

1. **Start:** Standing at main entrance
2. **Indoor:** Navigate hallway, avoid people, find elevator
3. **Elevator:** Detect door opening, enter, exit at floor 3
4. **Hallway:** Navigate to room 304
5. **Door:** Detect door, enter room
6. **Seat:** Find empty chair, sit down

**What we show:**
- Mac BEV showing real-time world model
- iPhone giving audio cues
- Split screen: camera view + BEV + audio waveform

**What we prove:**
- Geometry-based navigation works
- Elevation detection catches steps
- Object tracking handles people
- The system keeps you safe

---

*"make it work, make it right, make it fast"*
— kent beck

*"geometry for navigation, semantics for context"*
— pathfinder principle
