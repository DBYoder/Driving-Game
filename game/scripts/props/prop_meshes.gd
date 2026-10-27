class_name PropMeshes
extends RefCounted
## Low-poly roadside props. Local axes: Z runs along the road, X points across it.

const WOOD := Color(0.36, 0.27, 0.18)
const POST_GRAY := Color(0.45, 0.45, 0.47)


## A rural mailbox on a post, opening toward the road (-X).
static func mailbox() -> ArrayMesh:
	var st := MeshKit.begin(true)
	MeshKit.box(st, Vector3(0.1, 1.1, 0.1), Vector3(0, 0.55, 0), WOOD)
	MeshKit.box(st, Vector3(0.5, 0.24, 0.24), Vector3(-0.05, 1.2, 0), Color(0.12, 0.12, 0.13))
	MeshKit.box(st, Vector3(0.03, 0.16, 0.05), Vector3(0.05, 1.38, 0.14), Color(0.8, 0.1, 0.08))  # the flag
	return MeshKit.finish(st)


## Four meters of pasture fence: two posts and three boards along Z.
static func fence_span() -> ArrayMesh:
	var st := MeshKit.begin(true)
	for z in [-2.0, 2.0]:
		MeshKit.box(st, Vector3(0.12, 1.3, 0.12), Vector3(0, 0.65, z), WOOD)
	for y in [0.45, 0.8, 1.15]:
		MeshKit.box(st, Vector3(0.04, 0.1, 4.0), Vector3(0.06, y, 0), Color(0.62, 0.58, 0.52))
	return MeshKit.finish(st)


## A round hay bale lying on its side (rolls along X... until something hits it).
static func hay_bale(radius: float, width: float) -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.cylinder(st, radius, width, Vector3.ZERO, Color(0.80, 0.69, 0.38), Color(0.66, 0.55, 0.28), 12, Vector3.FORWARD)
	return MeshKit.finish(st)
