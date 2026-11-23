-- World origin is derived from the dock's horizontal centre and bottom edge.
-- All points below are local pixels measured from the top left of the art.
local C={
    center=260,bottom=-26400,width=384,height=168,
    material="mods/noita_hideout/files/travel/cabin_materials.png",
    background="mods/noita_hideout/files/travel/cabin_background.png",revision="3",
    infirmary={x=173,y=51},terminal={x=224,y=143},gate={x=91,y=129},
}
C.left=C.center-math.floor(C.width/2)
C.top=C.bottom-C.height
function C.point(p) return C.left+p.x,C.top+p.y end
function C.overlaps(left,top,right,bottom,padding)
    local d=padding or 0
    return right>=C.left-d and left<=C.left+C.width+d and bottom>=C.top-d and top<=C.bottom+d
end
function C.inside(x,y)
    x,y=x-C.left,y-C.top
    if y>=60 and y<104 then return x>=201 and x<226 end
    if y>=20 and y<60 then return x>=math.max(5,49-y) and x<381 end
    return y>=104 and y<144 and x>=math.max(17,y-87) and x<253
end
-- Test the standing player's footprint before filling a breached wall.
function C.wouldEmbed(x,y)
    if not C.overlaps(x-4,y-13,x+4,y+5,0) then return false end
    for row=math.max(0,math.floor(y-C.top-13)),math.min(C.height-1,math.floor(y-C.top+5)) do
        local bow,stern
        if row<84 then
            bow,stern=math.max(0,42-row),383
        else
            bow,stern=math.max(13,row-91),255
        end
        local left=math.max(math.floor(x-4),C.left+bow)
        local right=math.min(math.floor(x+4),C.left+stern)
        if left<=right and (not C.inside(left,C.top+row) or not C.inside(right,C.top+row)) then return true end
    end
    return false
end
return C
