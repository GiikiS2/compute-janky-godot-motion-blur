#[compute]
#version 450

// Invocations in the (x, y, z) dimensions
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant, std430) uniform Params {
	float TIME;
    float passes;
    float intensity;
    float vpasses;
    float vintensity;
    float resolutionx;
    float resolutiony;
	float blending;
} params;

layout(rgba16f, set=0, binding=0) uniform image2D color_image; 
layout(set=1, binding=0) uniform sampler2D velocity_image;
layout(set=2, binding=0) uniform sampler2D color_image2;

// The code we want to execute in each invocation

vec3 aces(vec3 x) {
  const float a = 2.51;
  const float b = 0.03;
  const float c = 2.43;
  const float d = 0.59;
  const float e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

float rand(vec2 co){
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

vec3 average(sampler2D img, vec2 uv, vec2 fac, int passes) {
	vec3 result;

	// int passes = 8;
	int x_passes = passes/2;
	int y_passes = passes/2;

	vec3 col = vec3(0.0);
	for (int i=0; i < passes; i++) {

		vec2 factor = (fac+float(i)) * (clamp(2.0*rand(uv*params.TIME),0.5,1.5));

		for (int x=0; x < x_passes; x++) {
			for (int y=0; y < y_passes; y++) {

				vec2 ofs = vec2(factor.x*(float(x/x_passes)),factor.y*(float(y/y_passes)));
				vec2 ofsn = vec2(factor.x*(float(x/x_passes)),factor.y*(float(clamp(y-1,0,y_passes)/y_passes)));
				vec2 ofss = vec2(factor.x*(float(x/x_passes)),factor.y*(float(clamp(y+1,0,y_passes)/y_passes)));
				vec2 ofse = vec2(factor.x*(float(clamp(x+1,0,x_passes)/x_passes)),factor.y*(float(y/y_passes)));
				vec2 ofsw = vec2(factor.x*(float(clamp(x-1,0,x_passes)/x_passes)),factor.y*(float(y/y_passes)));



				vec2 new_uv = ((round(uv*factor)+(ofs))/factor);
				vec2 new_uv1 = ((round(uv*factor)+(ofsn))/factor);
				vec2 new_uv2 = ((round(uv*factor)+(ofss))/factor);
				vec2 new_uv3 = ((round(uv*factor)+(ofse))/factor);
				vec2 new_uv4 = ((round(uv*factor)+(ofsw))/factor);

				vec3 res = max(texture(img,new_uv).rgb + vec3(0.5,0.5,0.5),max(max(texture(img,new_uv1).rgb + vec3(0.5,0.5,0.5),texture(img,new_uv2).rgb + vec3(0.5,0.5,0.5)),max(texture(img,new_uv3).rgb + vec3(0.5,0.5,0.5),texture(img,new_uv4).rgb + vec3(0.5,0.5,0.5))));
				col += res;
			}
		}
	}


	col = col / float(x_passes*y_passes*passes);

	result = col;
	return result;
}

void main() {
	ivec2 render_size = ivec2(vec2(params.resolutionx, params.resolutiony));

	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);

	// Just in case the render_size size is not divisable by 8
	if ((uv.x >= render_size.x) || (uv.y >= render_size.y)) {
		return;
	}

    vec2 tuv = gl_GlobalInvocationID.xy / vec2(params.resolutionx, params.resolutiony);
    
	float k = params.vintensity;
	// float k = 8.;

    vec3 velocity = average(velocity_image, tuv, vec2(k), int(params.vpasses)).rgb - vec3(0.5);
    // vec3 velocity = textureLod(velocity_image, tuv, 0).rgb;
    // vec3 velocity = average(velocity_image, tuv, vec2(k), 8).rgb - vec3(0.5);

	int samples = int(params.passes);
	// int samples = 12;

    float intensity = (params.intensity)/float(samples);
    // float intensity = 16./float(samples);

    vec2 ofs1 = vec2(0.0);
	vec2 ofs2 = vec2(0.0);

	vec3 colour = vec3(0.0);

   for (int i=0; i < samples; i++) {
		float indf = float(i);
		float sampf = float(samples);

        ofs1 = ((velocity.rg*intensity)*((indf)/(sampf-1.0)-0.5))*clamp(rand(tuv+vec2(params.TIME+0.000)),0.25,1.0);
		ofs2 = ((velocity.rg*intensity)*((indf)/(sampf-1.0)-0.5))*clamp(rand(tuv+vec2(params.TIME+0.001)),0.25,1.0);

        vec3 blur1 = (texture(color_image2, tuv+ofs1).rgb);
		vec3 blur2 = (texture(color_image2, tuv+ofs2).rgb);

        colour += (blur1+blur2)/2.;
    }

    colour /= samples;

    vec4 res;
	
	if(params.blending == 1.){
		res = mix(imageLoad(color_image, uv), vec4(colour, 1.), clamp((velocity.r+velocity.g)*500., 0., 1.));
	}else{
		res = vec4(colour,1.);
	}

    
    // res = vec4(blur1, 1.);
	// res = vec4(clamp((velocity.r+velocity.g)*500., 0., 1.), clamp((velocity.r+velocity.g)*500., 0., 1.), clamp((velocity.r+velocity.g)*500., 0., 1.), 1.);

	// res = vec4(velocity.rgb, 1.);

    imageStore(color_image, uv, res);
}