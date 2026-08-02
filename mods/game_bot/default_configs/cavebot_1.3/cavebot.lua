-- Cavebot by otclient@otclient.ovh
-- visit http://bot.otclient.ovh/

local cavebotTab = "Cave"
local targetingTab = "Target"

setDefaultTab(cavebotTab)
CaveBot = {} -- global namespace
CaveBot.Extensions = {}
importStyle("/cavebot/cavebot.otui")
importStyle("/cavebot/config.otui")
importStyle("/cavebot/editor.otui")
importStyle("/cavebot/supply.otui")

local cavebotFiles = {
  "/cavebot/actions.lua",
  "/cavebot/config.lua",
  "/cavebot/editor.lua",
  "/cavebot/example_functions.lua",
  "/cavebot/recorder.lua",
  "/cavebot/walking.lua",
  -- "/cavebot/extension_template.lua",
  "/cavebot/depositer.lua",
  "/cavebot/supply.lua",
  "/cavebot/cavebot.lua", -- main cavebot file, must be last among cavebot
}

local targetFiles = {
  "/targetbot/creature.lua",
  "/targetbot/creature_attack.lua",
  "/targetbot/creature_editor.lua",
  "/targetbot/creature_priority.lua",
  "/targetbot/looting.lua",
  "/targetbot/walking.lua",
  "/targetbot/target.lua", -- main targetbot file, must be last
}

local queue = {}
for _, f in ipairs(cavebotFiles) do
  table.insert(queue, { file = f, kind = "cavebot" })
end
table.insert(queue, { file = "__target_tab__", kind = "meta" })
for _, f in ipairs(targetFiles) do
  table.insert(queue, { file = f, kind = "targetbot" })
end

loadScriptQueue(queue, function(entry)
  if entry.kind == "meta" then
    setDefaultTab(targetingTab)
    TargetBot = {} -- global namespace
    importStyle("/targetbot/looting.otui")
    importStyle("/targetbot/target.otui")
    importStyle("/targetbot/creature_editor.otui")
    return
  end

  local status, err = pcall(function()
    dofile(entry.file)
  end)
  if not status then
    warn("[" .. entry.kind .. "] Failed to load " .. entry.file .. ":\n" .. tostring(err))
  end
end)
