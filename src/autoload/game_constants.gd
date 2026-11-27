class_name GameConstants
extends RefCounted

## Central registry of balanced gameplay constants, definitions, and visual palettes.

const TITLE: String = "Vibe Taxi"
const VERSION: String = "2.1.0"

const VIRTUAL_WIDTH: int = 640
const VIRTUAL_HEIGHT: int = 360
const TILE_SIZE: int = 16

const CAMERA_FOLLOW_RATE: float = 8.0

const TILED_GROUND_LAYERS: Array[String] = ["ground"]
const TILED_MIDDLE_LAYERS: Array[String] = ["decoration-low", "buildings"]
const TILED_UPPER_NO_SHADOW_LAYERS: Array[String] = ["decoration-high"]
const TILED_UPPER_SHADOW_LAYERS: Array[String] = ["overheads"]

# Physics layers (bit values for 1-based layer indices)
const LAYER_WALLS: int = 1 << 0
const LAYER_TAXI: int = 1 << 1
const LAYER_TRAFFIC: int = 1 << 2
const LAYER_PROPS: int = 1 << 3
const LAYER_PEDESTRIANS: int = 1 << 4
const LAYER_TRIGGERS: int = 1 << 5

# Driving & Steering
const TURN_REDUCTION: float = 0.6
const MOUSE_MAX_SPEED_RADIUS: float = 80.0
const TAXI_MAX_HEALTH: float = 140.0
const TAXI_DAMAGED_ENGINE_HEALTH: float = 40.0
const TAXI_VIBE_DAMAGE_MULT: float = 0.4
const TAXI_VIBE_SPEED_MULT: float = 1.85
const TAXI_VIBE_ACCEL_MULT: float = 1.5
const TAXI_DRIFT_TURN_MULT: float = 2.2
const TAXI_DRIFT_GRIP: float = 3.5
const TAXI_VIBE_GRIP: float = 12.0
const WALL_CRASH_DAMAGE: float = 15.0
const CAR_CRASH_DAMAGE: float = 10.0
const WALL_CRASH_MIN_SPEED: float = 20.0
const TRAFFIC_CRASH_REL_SPEED: float = 150.0

# Vibe Ghosting
const GHOSTING_SPAWN_RATE: float = 0.08
const GHOSTING_DURATION: float = 0.4
const GHOSTING_ALPHA_START: float = 120.0 / 255.0

# Passenger & Comfort
const PASSENGER_DETECTION_RADIUS: float = 30.0
const PASSENGER_DELIVERY_RADIUS: float = 70.0
const PASSENGER_STOP_SPEED_THRESHOLD: float = 5.0
const PASSENGER_WALK_SPEED: float = 100.0
const PASSENGER_NEXT_PAGE_TIME: float = 1.0
const DIALOGUE_DISPLAY_TIME: float = 5.0
const BAD_MUSIC_PENALTY_TIME: float = 1.5

const COMFORT_RULES: Dictionary = {
	"initial_min": 50.0,
	"initial_max": 60.0,
	"initial_reaction_time": 6.0,
	"initial_reaction_bonus": 22.0,
	"comfort_increase_rate": 3.0,
	"comfort_decrease_rate": 5.0,
	"collision_penalty": 6.0,
	"max_comfort": 100.0,
	"min_comfort": 0.0,
	"vibe_threshold": 75.0,
	"exit_good_threshold": 50.0,
}

# Rules, Scoring & Economy
const WORKDAY_TIME_LIMIT: float = 120.0
const WORKDAY_BASE_FEE: float = 80.0
const WORKDAY_FEE_INCREMENT: float = 15.0
const WORKDAY_BASE_FARE: float = 10.0
const WORKDAY_FAST_BONUS: float = 5.0
const WORKDAY_SAFETY_BONUS: float = 3.0
const REPAIR_COST: float = 40.0

const ARCADE_START_TIME: float = 120.0
const ARCADE_BASE_TIME_GAIN: float = 8.0
const ARCADE_FAST_TIME_GAIN: float = 5.0
const ARCADE_SAFETY_TIME_GAIN: float = 3.0
const ARCADE_BASE_SCORE: int = 150
const ARCADE_TIME_BONUS_SCORE: int = 50
const ARCADE_SAFETY_BONUS_SCORE: int = 50

const ALLOW_GAMEOVER_SKIP: bool = false
const MAX_RECORDS_PER_MODE: int = 10
const RADIO_FADEOUT_TIME: float = 2.0

# Traffic & Pedestrians (spawn_max_dist < despawn_dist avoids instant despawn)
const TRAFFIC_SPAWN_INTERVAL: float = 0.2
const TRAFFIC_MAX_CARS: int = 20
const TRAFFIC_SPAWN_MAX_DIST: float = 550.0
const TRAFFIC_DESPAWN_DIST: float = 720.0
const TRAFFIC_SPEED_SCALE: float = 0.6

const PEDESTRIAN_SPAWN_INTERVAL: float = 0.8
const PEDESTRIAN_MAX_COUNT: int = 25
const PEDESTRIAN_SPAWN_RANGE: float = 600.0
const PEDESTRIAN_MAX_DISTANCE: float = 900.0
const PEDESTRIAN_SPAWN_CHANCE: float = 0.65

# Colors
const COLOR_TRIP_SHORT: Color = Color(0.0, 1.0, 0.0)
const COLOR_TRIP_MEDIUM: Color = Color(1.0, 1.0, 0.0)
const COLOR_TRIP_LONG: Color = Color(1.0, 69.0 / 255.0, 0.0)
const COLOR_PASSENGER_DELIVERY: Color = Color(0.0, 1.0, 0.0)

# UI Theme Colors
const UI_BG_PLUM: Color = Color(69.0 / 255.0, 40.0 / 255.0, 60.0 / 255.0)
const UI_BTN_NORMAL: Color = Color(100.0 / 255.0, 60.0 / 255.0, 90.0 / 255.0)
const UI_BTN_HOVER: Color = Color(150.0 / 255.0, 90.0 / 255.0, 120.0 / 255.0)
const UI_BTN_ACTIVE: Color = Color(145.0 / 255.0, 90.0 / 255.0, 130.0 / 255.0)
const UI_BTN_ACTIVE_HOVER: Color = Color(175.0 / 255.0, 115.0 / 255.0, 155.0 / 255.0)
const UI_BTN_DISABLED: Color = Color(60.0 / 255.0, 40.0 / 255.0, 50.0 / 255.0)
const UI_INPUT_BG: Color = Color(40.0 / 255.0, 20.0 / 255.0, 30.0 / 255.0)
const UI_GOLD: Color = Color(1.0, 220.0 / 255.0, 50.0 / 255.0)
const UI_GREEN: Color = Color(100.0 / 255.0, 1.0, 100.0 / 255.0)
const UI_AMBER: Color = Color(1.0, 200.0 / 255.0, 50.0 / 255.0)
const UI_LED_RED: Color = Color(200.0 / 255.0, 45.0 / 255.0, 72.0 / 255.0)

const RANKS: Array[Dictionary] = [
	{"name": "F", "color": Color(150.0 / 255.0, 150.0 / 255.0, 150.0 / 255.0), "workday_min": 1, "arcade_min": 0, "sound": "fatal"},
	{"name": "E", "color": Color(200.0 / 255.0, 100.0 / 255.0, 100.0 / 255.0), "workday_min": 2, "arcade_min": 350, "sound": "bad"},
	{"name": "D", "color": Color(200.0 / 255.0, 150.0 / 255.0, 50.0 / 255.0), "workday_min": 3, "arcade_min": 700, "sound": "bad"},
	{"name": "C", "color": Color(200.0 / 255.0, 200.0 / 255.0, 50.0 / 255.0), "workday_min": 4, "arcade_min": 1050, "sound": "good"},
	{"name": "B", "color": Color(100.0 / 255.0, 200.0 / 255.0, 100.0 / 255.0), "workday_min": 5, "arcade_min": 1400, "sound": "good"},
	{"name": "A", "color": Color(50.0 / 255.0, 200.0 / 255.0, 1.0), "workday_min": 6, "arcade_min": 1750, "sound": "awesome"},
	{"name": "VIBE", "color": Color(1.0, 50.0 / 255.0, 1.0), "workday_min": 8, "arcade_min": 2100, "sound": "vibe"},
]

const CAR_FRAME_RECTS: Array[Rect2] = [
	Rect2(0, 0, 14, 28),
	Rect2(16, 0, 14, 25),
	Rect2(32, 0, 16, 29),
	Rect2(48, 0, 16, 30),
	Rect2(64, 0, 14, 25),
	Rect2(0, 32, 16, 30),
	Rect2(34, 32, 18, 30),
	Rect2(52, 32, 20, 35),
]

const PROP_DEFS: Dictionary = {
	4: {"frame": 4, "damage": 5.0, "particles": []},
	6: {"frame": 6, "damage": 5.0, "particles": []},
	7: {"frame": 7, "damage": 8.0, "particles": [Color(1.0, 165.0 / 255.0, 0.0), Color(1.0, 140.0 / 255.0, 0.0)], "duration": 0.0},
	19: {"frame": 19, "damage": 10.0, "particles": [Color(1.0, 1.0, 1.0), Color(200.0 / 255.0, 200.0 / 255.0, 200.0 / 255.0)], "duration": 0.0},
	36: {"frame": 36, "damage": 10.0, "particles": [Color(1.0, 1.0, 1.0), Color(200.0 / 255.0, 200.0 / 255.0, 200.0 / 255.0)], "duration": 0.0},
	40: {"frame": 40, "damage": 15.0, "particles": [Color(0.0, 150.0 / 255.0, 1.0, 150.0 / 255.0), Color(100.0 / 255.0, 200.0 / 255.0, 1.0, 120.0 / 255.0)], "duration": 2.0},
}

const PASSENGER_DEFS: Dictionary = {
	"pedestrian_1": {"idle": [0, 1], "walk": [2, 3, 4, 5]},
	"pedestrian_2": {"idle": [6, 7], "walk": [8, 9, 10, 11]},
	"pedestrian_3": {"idle": [12, 13], "walk": [14, 15, 16, 17]},
	"pedestrian_4": {"idle": [18, 19], "walk": [20, 21, 22, 23]},
	"pedestrian_5": {"idle": [24, 25], "walk": [26, 27, 28, 29]},
}
