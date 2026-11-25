-- Leave gameplay status timers and the renderer's own uniform bindings intact.
-- Only attenuate their contribution to the final image on this client.
local path="data/shaders/post_final.frag"
local shader=ModTextFileGetContent(path)
local uniform="uniform vec4 nh_tarot_sight;"
if not shader or shader:find(uniform,1,true) then return end
local first,last=shader:find("void%s+main%s*%(%s*%)%s*{")
if not first then return end
local header,main=shader:sub(1,first-1),shader:sub(last+1)
local visibility="nh_tarot_status_visibility"
local normal={
    distortion_amount=true, doublevision_amount=true, fractals_amount=true,
}
local hasNightVision=header:find("uniform%s+float%s+drugged_nightvision_amount%s*;")
local original=main
main=main:gsub("%f[%w_]drugged_([%w_]+)",function(channel)
    local name="drugged_"..channel
    if channel=="color_amount" then
        -- Vanilla worm blood contributes 0.3 color per unit of night vision.
        local protected=hasNightVision and "min("..name..", 0.3 * drugged_nightvision_amount)" or "0.0"
        return "mix("..protected..", "..name..", "..visibility..")"
    end
    if normal[channel] then return "("..name.." * "..visibility..")" end
end)
main=main:gsub("%f[%w_](overlay_color_blindness%s*%.%s*[aw])%f[^%w_]",function(alpha)
    return "("..alpha.." * "..visibility..")"
end)
if main~=original then
    local start=shader:sub(first,last)
    ModTextFileSetContent(path,header..uniform.."\n"..start.."\n    float "..visibility.." = 1.0 - nh_tarot_sight.x;\n"..main)
end
