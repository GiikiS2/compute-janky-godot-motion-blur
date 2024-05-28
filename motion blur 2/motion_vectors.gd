@icon("res://icon.png")
@tool
extends CompositorEffect
class_name MotionBlurC

@export_category("MotionBlur")
@export var blending : bool = false
#@export var Passes : int = 12
@export_range (2, 30) var Passes: int = 12 ##motion blur passes.
#@export var Intensity : float = 16 ## motion blur intensity.
@export_range (1., 1000.) var Intensity: float = 16. ## motion blur intensity.


@export_category("mapBlurring")
@export_range (2, 16) var vPasses: int = 8 ## ⚠️: this lags sm!! passes for motion blur area.
#@export var vSize : float = 8 ## if smaller, then the motion blur area will be bigger.
#12 or 25
@export_range (0., 150.) var vSize: float = 12.  ## if smaller, then the motion blur area will be bigger.

func _init() -> void:
	needs_motion_vectors = true
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	RenderingServer.call_on_render_thread(_initialize_compute)

func _notification(what:int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# When this is called it should be safe to clean up our shader.
		# If not we'll crash anyway because we can no longer call our _render_callback.
		if shader.is_valid():
			rd.free_rid(shader)

###############################################################################
# Everything after this point is designed to run on our rendering thread

var rd : RenderingDevice
var shader : RID
var pipeline : RID

func _initialize_compute()->void:
	rd = RenderingServer.get_rendering_device()
	if !rd:
		return

	# Create our shader
	var shader_file: RDShaderFile = load("res://motion blur 2/motion_vectors.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)

func _render_callback(p_effect_callback_type:int, p_render_data: RenderData)->void:
	
	if rd and p_effect_callback_type == CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		# Get our render scene buffers object, this gives us access to our render buffers. 
		# Note that implementation differs per renderer hence the need for the cast.
		var render_scene_buffers : RenderSceneBuffersRD = p_render_data.get_render_scene_buffers()
		if render_scene_buffers:
			# Get our render size, this is the 3D render resolution!
			var render_size : Vector2 = render_scene_buffers.get_internal_size()
			var effect_size : Vector2 = render_size
			if effect_size.x == 0.0 and effect_size.y == 0.0:
				return

			# Render our intermediate at half size
			#if half_size:
				#effect_size *= 0.5;


			# Loop through views just in case we're doing stereo rendering. No extra cost if this is mono.
			var view_count:int = render_scene_buffers.get_view_count()
			for view in range(view_count):
				# Get the RID for our color image, we will be reading from and writing to it.
				var input_image: RID = render_scene_buffers.get_color_layer(view)
				var velocity_buffer: RID = render_scene_buffers.get_velocity_layer(view)
				

				# Create a uniform set, this will be cached, the cache will be cleared if our viewports configuration is changed
				var uniform : RDUniform = RDUniform.new()
				uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
				uniform.binding = 0
				uniform.add_id(input_image)
				var uniform_set: RID = UniformSetCacheRD.get_cache(shader, 0, [ uniform ])
				
				
				var sampler_state := RDSamplerState.new()
				sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
				sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
				var sampler = rd.sampler_create(sampler_state)
				
				
				# Create velocity map / buffer uniform 
				var velocity_uniform : RDUniform = RDUniform.new()
				#velocity_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
				velocity_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE 
				velocity_uniform.binding = 0
				velocity_uniform.add_id(sampler)
				velocity_uniform.add_id(velocity_buffer)
				var velocity_set: RID = UniformSetCacheRD.get_cache(shader, 1, [ velocity_uniform ])
				
				var color_uni2 : RDUniform = RDUniform.new()
				color_uni2.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE 
				color_uni2.binding = 0
				color_uni2.add_id(sampler)
				color_uni2.add_id(input_image)
				var color_set2: RID = UniformSetCacheRD.get_cache(shader, 2, [ color_uni2 ])
					
				var time = Time.get_ticks_msec()
				#@warning_ignore("integer_division")
				#var half_size := Vector2i((effect_size.x + 1) / 2, (effect_size.y + 1) / 2)
				
				var push_constant : PackedFloat32Array = PackedFloat32Array()
				push_constant.push_back(time)
				
				push_constant.push_back(Passes)
				push_constant.push_back(Intensity)
				push_constant.push_back(vPasses)
				push_constant.push_back(vSize)
				
				push_constant.push_back(effect_size.x)
				push_constant.push_back(effect_size.y)
				push_constant.push_back(1. if blending == true else 0.)
				push_constant.resize(32)
				#push_constant.resize(16)
				
				@warning_ignore("integer_division")
				var x_groups : int = (effect_size.x - 1) / 8 + 1
				@warning_ignore("integer_division")
				var y_groups : int = (effect_size.y - 1) / 8 + 1
				# Run our compute shader
				var compute_list := rd.compute_list_begin()
				rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
				rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
				rd.compute_list_bind_uniform_set(compute_list, velocity_set, 1)
				rd.compute_list_bind_uniform_set(compute_list, color_set2, 2)
				rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size())
				rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
				rd.compute_list_end()
