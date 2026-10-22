class_name Condition
extends RefCounted
## The five ways to drive the road (PLAN.md §4.6): the light and weather, what's growing,
## what's on the road, how much grip there is. Pure data; main.gd's apply_condition()
## hands it to the systems it touches. Each has its own records.

const IDS := ["summer", "harvest", "night", "storm", "winter"]

var id := "summer"
var display_name := "Summer afternoon"
var tagline := "Tall green corn, full grip."

# Sky and light
var sky_top := Color(0.36, 0.55, 0.82)
var sky_horizon := Color(0.78, 0.83, 0.86)
var haze := Color(0.76, 0.81, 0.85)  ## fog, and the sky below the horizon
var ambient := Color(0.82, 0.82, 0.78)
var ambient_energy := 0.55
var sun_rotation := Vector3(-48.0, -35.0, 0.0)  ## degrees
var sun_color := Color(1.0, 1.0, 1.0)
var sun_energy := 1.1
var fog_begin := 450.0
var fog_end := 3000.0
var cloud_cover := 0.32  ## share of the sky (sky.gdshader)
var cloud_color := Color(1.0, 1.0, 1.0)  ## sunlit
var cloud_shade := Color(0.70, 0.74, 0.80)  ## underneath
var stars := 0.0

# The land
var corn_leaf := Color(0.20, 0.40, 0.12)
var corn_tassel := Color(0.62, 0.58, 0.36)
var corn_ground := Color(0.32, 0.43, 0.18)  ## corn fields from afar (terrain.gdshader)
var soybeans := Color(0.34, 0.50, 0.17)
var hay := Color(0.58, 0.60, 0.30)
var pasture := Color(0.42, 0.50, 0.24)
var verge := Color(0.47, 0.57, 0.29)
var stubble := Color(0.62, 0.55, 0.38)  ## a harvested field
var harvested := 0.0  ## share of the corn fields already cut (no corn standing)
var leaf := Color(0.25, 0.42, 0.17)  ## tree leaves; brown-gray is bare branches
var snow := 0.0  ## on roofs, trees and the ground
var asphalt := Color(0.17, 0.17, 0.18)
var gravel := Color(0.56, 0.51, 0.42)
var road_verge := Color(0.40, 0.48, 0.24)

# Driving
var grip := 1.0  ## all surfaces
var ice_grip := 1.0  ## on bridges and where trees shade the road (winter's black ice)
var wind_gusts := 0.0  ## peak side pressure, N per square meter of the car's side
var night := 0.0  ## headlights, lit windows, yard lights, lanterns
var rain := 0.0
var snowfall := 0.0
var lightning := false

# Traffic and deer
var deer_rate := 1.0
var same_direction := {"buggy": 0.0, "tractor": 0.3, "car": 0.7}  ## mix after the buggies
var oncoming := {"semi": 0.2, "pickup": 0.3, "car": 0.5}


static func preset(condition_id: String) -> Condition:
	var c := Condition.new()
	c.id = condition_id
	match condition_id:
		"harvest":
			c.display_name = "Harvest dusk"
			c.tagline = "Brown corn, stubble, combines and grain trucks. More deer."
			c.sky_top = Color(0.28, 0.34, 0.55)
			c.sky_horizon = Color(0.95, 0.62, 0.38)
			c.haze = Color(0.78, 0.62, 0.50)
			c.ambient = Color(0.85, 0.70, 0.60)
			c.ambient_energy = 0.42
			c.sun_rotation = Vector3(-9.0, -78.0, 0.0)
			c.sun_color = Color(1.0, 0.68, 0.42)
			c.sun_energy = 0.95
			c.fog_begin = 350.0
			c.fog_end = 2600.0
			c.cloud_cover = 0.3
			c.cloud_color = Color(1.0, 0.72, 0.52)
			c.cloud_shade = Color(0.50, 0.42, 0.50)
			c.corn_leaf = Color(0.52, 0.42, 0.24)
			c.corn_tassel = Color(0.66, 0.56, 0.36)
			c.corn_ground = Color(0.55, 0.46, 0.28)
			c.soybeans = Color(0.60, 0.48, 0.22)
			c.hay = Color(0.60, 0.56, 0.32)
			c.pasture = Color(0.48, 0.48, 0.26)
			c.verge = Color(0.52, 0.52, 0.30)
			c.road_verge = Color(0.46, 0.45, 0.27)
			c.harvested = 0.45
			c.leaf = Color(0.72, 0.42, 0.16)
			c.deer_rate = 1.6
			c.same_direction = {"buggy": 0.0, "combine": 0.3, "tractor": 0.2, "grain_truck": 0.2, "car": 0.3}
			c.oncoming = {"grain_truck": 0.3, "semi": 0.15, "pickup": 0.25, "car": 0.3}
		"night":
			c.display_name = "Night"
			c.tagline = "Headlights only. Buggy lanterns, yard lights, deer ×3."
			c.sky_top = Color(0.02, 0.03, 0.07)
			c.sky_horizon = Color(0.06, 0.07, 0.12)
			c.haze = Color(0.04, 0.05, 0.08)
			c.ambient = Color(0.40, 0.45, 0.65)
			c.ambient_energy = 0.12
			c.sun_rotation = Vector3(-35.0, 140.0, 0.0)  # the moon
			c.sun_color = Color(0.55, 0.62, 0.85)
			c.sun_energy = 0.12
			c.fog_begin = 250.0
			c.fog_end = 2400.0
			c.cloud_cover = 0.22
			c.cloud_color = Color(0.13, 0.15, 0.21)
			c.cloud_shade = Color(0.04, 0.05, 0.08)
			c.stars = 1.0
			c.night = 1.0
			c.deer_rate = 3.0
		"storm":
			c.display_name = "Thunderstorm"
			c.tagline = "Rain, wet grip, lightning, gusts. Bad news for the Windstar."
			c.sky_top = Color(0.20, 0.23, 0.26)
			c.sky_horizon = Color(0.40, 0.44, 0.44)
			c.haze = Color(0.38, 0.42, 0.42)
			c.ambient = Color(0.70, 0.75, 0.75)
			c.ambient_energy = 0.45
			c.sun_rotation = Vector3(-60.0, -20.0, 0.0)
			c.sun_color = Color(0.80, 0.86, 0.88)
			c.sun_energy = 0.45
			c.fog_begin = 120.0
			c.fog_end = 1500.0
			c.cloud_cover = 0.95
			c.cloud_color = Color(0.40, 0.43, 0.46)
			c.cloud_shade = Color(0.20, 0.22, 0.24)
			c.corn_leaf = Color(0.16, 0.33, 0.12)
			c.corn_ground = Color(0.26, 0.36, 0.16)
			c.asphalt = Color(0.10, 0.10, 0.11)
			c.grip = 0.72
			c.wind_gusts = 260.0
			c.rain = 1.0
			c.lightning = true
		"winter":
			c.display_name = "Winter"
			c.tagline = "Snow, black ice on bridges and in the shade, snowplows, whiteout."
			c.sky_top = Color(0.62, 0.66, 0.72)
			c.sky_horizon = Color(0.86, 0.88, 0.90)
			c.haze = Color(0.86, 0.88, 0.90)
			c.ambient = Color(0.85, 0.88, 0.95)
			c.ambient_energy = 0.6
			c.sun_rotation = Vector3(-22.0, -20.0, 0.0)
			c.sun_color = Color(0.95, 0.96, 1.0)
			c.sun_energy = 0.7
			c.fog_begin = 60.0
			c.fog_end = 900.0
			c.cloud_cover = 0.8
			c.cloud_color = Color(0.88, 0.90, 0.93)
			c.cloud_shade = Color(0.64, 0.67, 0.72)
			c.corn_ground = Color(0.86, 0.87, 0.88)
			c.soybeans = Color(0.88, 0.89, 0.90)
			c.hay = Color(0.84, 0.85, 0.85)
			c.pasture = Color(0.87, 0.88, 0.89)
			c.verge = Color(0.90, 0.91, 0.92)
			c.stubble = Color(0.80, 0.80, 0.78)
			c.harvested = 1.0
			c.road_verge = Color(0.88, 0.89, 0.91)
			c.gravel = Color(0.76, 0.75, 0.73)
			c.asphalt = Color(0.25, 0.25, 0.27)
			c.leaf = Color(0.38, 0.33, 0.28)  # bare branches
			c.snow = 0.85
			c.grip = 0.82
			c.ice_grip = 0.3
			c.snowfall = 1.0
			c.same_direction = {"buggy": 0.0, "snowplow": 0.12, "tractor": 0.05, "car": 0.83}
			c.oncoming = {"snowplow": 0.08, "semi": 0.17, "pickup": 0.35, "car": 0.4}
	return c


## How lit the (unshaded) corn should look: roughly what the sky and sun give a lit
## surface, relative to summer's.
func corn_light() -> Color:
	var lit := ambient * ambient_energy + sun_color * sun_energy * 0.6
	return Color(lit.r / 1.11, lit.g / 1.11, lit.b / 1.08)


## Key for this condition's records: the plain car name for summer (the records from
## before conditions existed), "car|condition" for the others.
func records_key(car_name: String) -> String:
	return car_name if id == "summer" else "%s|%s" % [car_name, id]
