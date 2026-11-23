function interacting(player,terminal)
    if EntityHasTag(player,"player_unit") then
        GamePrint(GameTextGetTranslatedOrNot("$nh_travel_open_inventory"))
    end
end
