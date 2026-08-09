setDefaultTab("HP")
if voc() ~= 1 and voc() ~= 11 and voc() ~= 5 and voc() ~= 15 then
    if storage.foodItems then
        local t = {}
        for i, v in pairs(storage.foodItems) do
            local id = type(v) == "table" and v.id or v
            if id and not table.find(t, id) then
                table.insert(t, id)
            end
        end
        local foodItems = { 3607, 3585, 3592, 3600, 3601 }
        for i, item in pairs(foodItems) do
            if not table.find(t, item) then
                table.insert(storage.foodItems, { id = item })
            end
        end
    end
    macro(500, "Cast Food", function()
        if player:getRegenerationTime() <= 400 then
            cast("exevo pan", 5000)
        end
    end)
end
