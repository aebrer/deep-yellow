class_name Snowfall extends GPUParticles3D
## Snowfall particle effect that follows a target node (typically the player)
##
## Creates falling snow particles in a box around the target.
## Enable/disable via set_active(). Call set_target() to follow a node.

var target: Node3D = null

func _init() -> void:
	amount = 200
	lifetime = 4.0
	visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 12, 40))
	emitting = false

	# Process material for particle physics
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(15, 0.5, 15)
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 10.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 2.5
	mat.gravity = Vector3(0.3, -0.8, 0.0)  # Slight wind drift
	mat.scale_min = 0.03
	mat.scale_max = 0.08
	process_material = mat

	# Draw pass: simple quad mesh with snow shader
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.15, 0.15)
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = load("res://shaders/snow_particles.gdshader")
	mesh.material = shader_mat
	draw_pass_1 = mesh

func _process(_delta: float) -> void:
	if target and is_instance_valid(target):
		global_position = target.global_position + Vector3(0, 6, 0)

func set_target(node: Node3D) -> void:
	target = node

func set_active(active: bool) -> void:
	emitting = active
	visible = active
