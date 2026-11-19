class_name RadioStationDef
extends Resource

## Editable radio station metadata, Vibe color, and playlist streams.

@export var station_name: String = "off"
@export var genre: String = "off"
@export var vibe_color: Color = Color(0.588, 1.0, 0.588, 1.0)
@export_file("*.ogg", "*.mp3", "*.wav") var track_paths: Array[String] = []
@export var tracks: Array[AudioStream] = []
