-- Maps Tibia clientoptions.json hotkey action ids to General Hotkeys (category, action).

CipImportMappings = CipImportMappings or {}

CipImportMappings.KEY_SEQUENCE_REPLACEMENTS = {
  Return = "Enter",
  Backtab = "BackTab",
}

-- actionsetting.action -> { category, action }
CipImportMappings.KEYBIND_ACTIONS = {
  AttackNextTarget = { "Battle List", "Attack Next Target" },
  Logout = { "Misc", "Logout" },
  NextChannel = { "Chat Channel", "Next Channel" },
  PreviousChannel = { "Chat Channel", "Previous Channel" },
  OpenChannelList = { "Chat Channel", "Open Channel List" },
  CloseCurrentChannel = { "Chat Channel", "Close Current Channel" },
  OpenHelpChannel = { "Chat Channel", "Open Help Channel" },
  ToggleBattlelist = { "Windows", "Open Battle List" },
  ShowQuestlog = { "Windows", "Open Quest Log" },
  ShowPrey = { "Dialogs", "Open Prey Dialog" },
  Bugreport = { "Dialogs", "Open Bug Report" },
  QuickLootAreaAtPlayer = { "Loot", "Quick Loot Nearby Corpses" },
  ChatModeTemporaryOn = { "Chat Mode", "Set to Chat On" },
  ToggleManualSortMode = { "Containers", "Toggle Manual Sort Mode" },
}

function CipImportMappings.normalizeKeySequence(keysequence)
  if type(keysequence) ~= "string" or keysequence == "" then
    return nil
  end

  return CipImportMappings.KEY_SEQUENCE_REPLACEMENTS[keysequence] or keysequence
end

function CipImportMappings.resolveKeybindFromCipAction(cipAction)
  if type(cipAction) ~= "string" or cipAction == "" then
    return nil, nil
  end

  local mapping = CipImportMappings.KEYBIND_ACTIONS[cipAction]
  if not mapping then
    return nil, nil
  end

  if Keybind and Keybind.normalizeKeybindIdentity then
    return Keybind.normalizeKeybindIdentity(mapping[1], mapping[2])
  end

  return mapping[1], mapping[2]
end

function CipImportMappings.resolveKeybindIdentity(category, action)
  if Keybind and Keybind.normalizeKeybindIdentity then
    return Keybind.normalizeKeybindIdentity(category, action)
  end

  return category, action
end
