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

UI.Label("Eatable items:")
if type(storage.foodItems) ~= "table" then
  storage.foodItems = { { id = 3582 }, { id = 3577 } }
end

local foodContainer = UI.Container(function(widget, items)
  storage.foodItems = items
end, true)
foodContainer:setHeight(100)
foodContainer:setItems(storage.foodItems)

macro(500, "Eat Food", function()
  if player:getRegenerationTime() > 400 or not storage.foodItems[1] then return end
  -- search for food in containers
  for _, container in pairs(g_game.getContainers()) do
    for __, item in ipairs(container:getItems()) do
      for i, foodItem in ipairs(storage.foodItems) do
        local foodId = type(foodItem) == "table" and foodItem.id or foodItem
        if foodId and item:getId() == foodId then
          return g_game.use(item)
        end
      end
    end
  end
end)
UI.Separator()
