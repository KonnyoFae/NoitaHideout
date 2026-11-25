local path="data/shaders/post_final.frag"
local source=[[
#version 110
uniform vec4 overlay_color_blindness;
uniform vec4 overlay_color;
uniform float drugged_color_amount;
uniform float drugged_nightvision_amount;
uniform float drugged_fractals_amount;
uniform float drugged_doublevision_amount;
uniform float drugged_distortion_amount;
void main() {
    vec3 color = vec3(drugged_distortion_amount, drugged_fractals_amount, drugged_doublevision_amount);
    color.g += drugged_color_amount;
    color *= 1.0 + drugged_nightvision_amount;
    color = mix(color, overlay_color_blindness.rgb, overlay_color_blindness.a);
    color = mix(color, overlay_color.rgb, overlay_color.a);
    gl_FragColor = vec4(color, 1.0);
}
]]
local writes=0
function ModTextFileGetContent(file) assert(file==path); return source end
function ModTextFileSetContent(file,value) assert(file==path); source=value; writes=writes+1 end
local function install() dofile("mods/noita_hideout/files/tarot_sight_shader.lua") end
local function has(text) return source:find(text,1,true)~=nil end
install()
assert(writes==1 and has("uniform vec4 nh_tarot_sight;"))
for _,channel in ipairs({"distortion_amount","fractals_amount","doublevision_amount"}) do
    assert(has("uniform float drugged_"..channel..";"))
    assert(has("(drugged_"..channel.." * nh_tarot_status_visibility)"))
end
assert(has("mix(min(drugged_color_amount, 0.3 * drugged_nightvision_amount), drugged_color_amount, nh_tarot_status_visibility)"))
assert(has("(overlay_color_blindness.a * nh_tarot_status_visibility)"))
assert(has("color *= 1.0 + drugged_nightvision_amount;") and has("mix(color, overlay_color.rgb, overlay_color.a)"))
local once=source
install()
assert(source==once and writes==1)
-- A replacement shader may implement only one of the original channels.
source="uniform float drugged_color_amount;\nvoid main() { float x = drugged_color_amount; }"
install()
assert(has("mix(0.0, drugged_color_amount, nh_tarot_status_visibility)") and not has("drugged_nightvision_amount"))
source="void main() { gl_FragColor = vec4(1.0); }"
install()
assert(writes==2 and not has("nh_tarot_sight"))
print("Visual protection filters only blindness and adverse drug channels, preserving night vision and other overlays.")
