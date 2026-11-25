-- A saved pre-0.42.43 watch can still load this callback before migration.
function damage_about_to_be_received(damage,x,y,responsible,critical)
    return damage,critical
end
