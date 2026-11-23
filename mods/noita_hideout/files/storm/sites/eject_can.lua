-- The item's Box2D body can become available a frame after EntityLoad.
local can = GetUpdatedEntityID()
if EntityGetRootEntity(can) == can then
    if #(PhysicsBodyIDGetFromEntity(can) or {}) == 0 then return end
    PhysicsApplyForce(can, 32, -55)
end
EntityRemoveComponent(can, GetUpdatedComponentID())
