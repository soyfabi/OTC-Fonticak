-- Export / import client options and hotkeys as JSON files under /configs/export/

local CONFIG_FORMAT = 'otc-fonticak-config'
local CONFIG_VERSION = 1
local EXPORT_DIR = '/configs/export'

local CATEGORIES = {
    {
        id = 'generalHotkey',
        label = 'Export General Hotkey',
    },
    {
        id = 'customHotkey',
        label = 'Export Custom Hotkey',
    },
    {
        id = 'interface',
        label = 'Export Interface',
        panels = { 'interface', 'interfaceHUD', 'interfaceGameWindow', 'interfaceConsole', 'actionbars' },
    },
    {
        id = 'graphics',
        label = 'Export Graphics',
        panels = { 'graphicsPanel', 'graphicsEffectsPanel', 'graphicsAnimationPanel' },
    },
    {
        id = 'sound',
        label = 'Export Sound',
        panels = { 'soundPanel' },
    },
    {
        id = 'misc',
        label = 'Export Misc',
        panels = { 'misc', 'miscGameplay', 'miscScreenshot', 'miscHelp' },
    },
}

local function ensureExportDir()
    if not g_resources.directoryExists('/configs') then
        g_resources.makeDir('/configs')
    end
    if not g_resources.directoryExists(EXPORT_DIR) then
        g_resources.makeDir(EXPORT_DIR)
    end
end

local function findCategory(categoryId)
    for _, category in ipairs(CATEGORIES) do
        if category.id == categoryId then
            return category
        end
    end
end

local function collectOptionKeys(panelIds)
    local keys = {}
    local seen = {}

    local function visit(widget)
        if not widget or widget:isDestroyed() then
            return
        end
        local id = widget:getId()
        if id and id ~= '' and not seen[id] and modules.client_options.hasOption(id) then
            seen[id] = true
            table.insert(keys, id)
        end
        for _, child in ipairs(widget:getChildren()) do
            visit(child)
        end
    end

    for _, panelId in ipairs(panelIds or {}) do
        local panel = panels[panelId]
        if panel then
            visit(panel)
        end
    end

    table.sort(keys)
    return keys
end

local function deepCopy(value)
    if type(value) ~= 'table' then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = deepCopy(v)
    end
    return copy
end

-- json.lua only accepts nil/bool/number/string/table. Strip userdata, functions, etc.
local function toJsonSafe(value, depth)
    depth = depth or 0
    if depth > 30 then
        return nil
    end

    local valueType = type(value)
    if value == nil or valueType == 'boolean' or valueType == 'string' then
        return value
    end
    if valueType == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then
            return 0
        end
        return value
    end
    if valueType ~= 'table' then
        return tostring(value)
    end

    local arrayCount = 0
    local maxIndex = 0
    local hasStringKey = false
    for key, _ in pairs(value) do
        local keyType = type(key)
        if keyType == 'string' then
            hasStringKey = true
        elseif keyType == 'number' and key >= 1 and key == math.floor(key) then
            arrayCount = arrayCount + 1
            if key > maxIndex then
                maxIndex = key
            end
        else
            hasStringKey = true
        end
    end

    local out = {}
    if not hasStringKey and arrayCount > 0 and maxIndex == arrayCount then
        for i = 1, maxIndex do
            out[i] = toJsonSafe(value[i], depth + 1)
            if out[i] == nil and value[i] ~= nil then
                out[i] = tostring(value[i])
            end
        end
    else
        for key, child in pairs(value) do
            local keyType = type(key)
            local outKey
            if keyType == 'string' or keyType == 'number' then
                outKey = tostring(key)
            else
                outKey = nil
            end
            if outKey then
                local safeChild = toJsonSafe(child, depth + 1)
                if safeChild ~= nil or child == nil then
                    out[outKey] = safeChild
                elseif child ~= nil then
                    out[outKey] = tostring(child)
                end
            end
        end
    end
    return out
end

local function showMessage(title, message)
    -- Defer so the message survives InputBox/PopupMenu teardown.
    scheduleEvent(function()
        displayInfoBox(title, message)
    end, 50)
end

local function exportOptionsCategory(category)
    local keys = collectOptionKeys(category.panels)
    local values = {}
    for _, key in ipairs(keys) do
        values[key] = toJsonSafe(modules.client_options.getOption(key))
    end
    return {
        keys = keys,
        values = values,
    }
end

local function exportGeneralHotkeys()
    local preset = Keybind.currentPreset
    local binds = {}
    for chatMode = CHAT_MODE.ON, CHAT_MODE.OFF do
        local modeBinds = {}
        for _, keybind in pairs(Keybind.defaultKeybinds) do
            local keys = Keybind.getKeybindKeys(keybind.category, keybind.action, chatMode, preset)
            table.insert(modeBinds, {
                category = keybind.category,
                action = keybind.action,
                primary = keys.primary or '',
                secondary = keys.secondary or '',
            })
        end
        binds[tostring(chatMode)] = modeBinds
    end
    return {
        preset = preset,
        binds = binds,
    }
end

local function exportCustomHotkeys()
    local preset = Keybind.currentPreset
    local hotkeys = {}
    for chatMode = CHAT_MODE.ON, CHAT_MODE.OFF do
        local list = {}
        for _, hotkey in ipairs(Keybind.hotkeys[chatMode][preset] or {}) do
            table.insert(list, {
                action = hotkey.action,
                primary = hotkey.primary or '',
                secondary = hotkey.secondary or '',
                data = toJsonSafe(hotkey.data or {}),
            })
        end
        hotkeys[tostring(chatMode)] = list
    end
    return {
        preset = preset,
        hotkeys = hotkeys,
    }
end

local function buildPayload(categoryId)
    local category = findCategory(categoryId)
    if not category then
        return nil
    end

    local exportedAt = tostring(g_clock.millis())
    if os and os.date then
        exportedAt = os.date('!%Y-%m-%dT%H:%M:%SZ')
    end

    local payload = {
        format = CONFIG_FORMAT,
        version = CONFIG_VERSION,
        category = categoryId,
        exportedAt = exportedAt,
    }

    if categoryId == 'generalHotkey' then
        payload.data = exportGeneralHotkeys()
    elseif categoryId == 'customHotkey' then
        payload.data = exportCustomHotkeys()
    else
        payload.data = exportOptionsCategory(category)
    end

    return toJsonSafe(payload)
end

local function defaultFileName(categoryId)
    local stamp = tostring(g_clock.millis())
    if os and os.date then
        stamp = os.date('%Y%m%d_%H%M%S')
    end
    return string.format('%s_%s.json', categoryId, stamp)
end

local function sanitizeFileName(name)
    name = tostring(name or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then
        return nil
    end
    name = name:gsub('[\\/:*?"<>|]', '_')
    if not name:lower():find('%.json$') then
        name = name .. '.json'
    end
    return name
end

local function writePayload(fileName, payload)
    ensureExportDir()
    local path = EXPORT_DIR .. '/' .. fileName
    if not json or not json.encode then
        return false, tr('JSON library is not available.')
    end
    local ok, encoded = pcall(function()
        return json.encode(payload)
    end)
    if not ok or type(encoded) ~= 'string' then
        return false, tr('Failed to encode JSON:\n%s', tostring(encoded))
    end
    if not g_resources.writeFileContents(path, encoded) then
        return false, tr('Failed to write file:\n%s', path)
    end
    return true, path
end

local function readPayload(fileName)
    ensureExportDir()
    local path = EXPORT_DIR .. '/' .. fileName
    if not g_resources.fileExists(path) then
        return nil, tr('File not found:\n%s', path)
    end
    local contents = g_resources.readFileContents(path)
    local ok, payload = pcall(function()
        return json.decode(contents)
    end)
    if not ok or type(payload) ~= 'table' then
        return nil, tr('Invalid JSON file.')
    end
    if payload.format ~= CONFIG_FORMAT then
        return nil, tr('This file is not an OTC Fonticak config export.')
    end
    return payload
end

local function importOptionsCategory(payload)
    local values = payload.data and payload.data.values
    if type(values) ~= 'table' then
        return false, tr('Config file has no options data.')
    end
    local count = 0
    for key, value in pairs(values) do
        if modules.client_options.hasOption(key) then
            modules.client_options.setOption(key, value, true)
            count = count + 1
        end
    end
    g_settings.save()
    return true, tr('Imported %d options successfully.', count)
end

local function importGeneralHotkeys(payload)
    local data = payload.data
    if type(data) ~= 'table' or type(data.binds) ~= 'table' then
        return false, tr('Config file has no general hotkey data.')
    end

    local preset = Keybind.currentPreset
    for chatModeStr, binds in pairs(data.binds) do
        local chatMode = tonumber(chatModeStr)
        if chatMode and type(binds) == 'table' then
            for _, bind in ipairs(binds) do
                if bind.category and bind.action then
                    Keybind.setPrimaryActionKey(bind.category, bind.action, preset, bind.primary or '', chatMode)
                    Keybind.setSecondaryActionKey(bind.category, bind.action, preset, bind.secondary or '', chatMode)
                end
            end
        end
    end

    if type(updateKeybinds) == 'function' then
        updateKeybinds()
    end
    return true, tr('General hotkeys imported successfully for preset "%s".', preset)
end

local function importCustomHotkeys(payload)
    local data = payload.data
    if type(data) ~= 'table' or type(data.hotkeys) ~= 'table' then
        return false, tr('Config file has no custom hotkey data.')
    end

    for chatMode = CHAT_MODE.ON, CHAT_MODE.OFF do
        Keybind.removeAllHotkeys(chatMode)
        local list = data.hotkeys[tostring(chatMode)] or {}
        for _, hotkey in ipairs(list) do
            local action = tonumber(hotkey.action) or hotkey.action
            Keybind.newHotkey(action, deepCopy(hotkey.data or {}), hotkey.primary or '', hotkey.secondary or '', chatMode)
        end
    end

    if type(updateCustomHotkeys) == 'function' then
        updateCustomHotkeys()
    end
    -- keybinds panel updateHotkeys() still references removed addHotkey(); custom UI is enough.
    return true, tr('Custom hotkeys imported successfully for preset "%s".', Keybind.currentPreset)
end

local function importPayload(payload, expectedCategory)
    if expectedCategory and payload.category ~= expectedCategory then
        return false, tr('This file belongs to category "%s", not "%s".', tostring(payload.category), expectedCategory)
    end

    local categoryId = payload.category
    if categoryId == 'generalHotkey' then
        return importGeneralHotkeys(payload)
    elseif categoryId == 'customHotkey' then
        return importCustomHotkeys(payload)
    elseif findCategory(categoryId) then
        return importOptionsCategory(payload)
    end
    return false, tr('Unknown config category.')
end

local function listExportFiles(categoryId)
    ensureExportDir()
    local files = {}
    for _, name in ipairs(g_resources.listDirectoryFiles(EXPORT_DIR, false, false, false) or {}) do
        if name:lower():find('%.json$') then
            if not categoryId then
                table.insert(files, name)
            else
                local payload = select(1, readPayload(name))
                if payload and payload.category == categoryId then
                    table.insert(files, name)
                elseif name:find('^' .. categoryId .. '_') then
                    table.insert(files, name)
                end
            end
        end
    end
    table.sort(files)
    return files
end

local function promptExport(categoryId)
    local category = findCategory(categoryId)
    if not category then
        return
    end

    local suggested = defaultFileName(categoryId)
    displayInputBox(tr('Export Config'), tr('File name (saved in configs/export):'), function(name)
        local fileName = sanitizeFileName(name) or suggested
        local payloadOk, payload = pcall(function()
            return buildPayload(categoryId)
        end)
        if not payloadOk or not payload then
            showMessage(tr('Export Config'), tr('Could not build config payload:\n%s', tostring(payload)))
            return
        end
        local ok, result = writePayload(fileName, payload)
        if ok then
            showMessage(tr('Export Config'), tr('Exported successfully:\n%s\n\nWrite dir:\n%s', result, g_resources.getWriteDir()))
        else
            showMessage(tr('Export Config'), result)
        end
    end, nil, suggested)
end

local function promptImport(categoryId)
    local files = listExportFiles(categoryId)
    if #files == 0 then
        showMessage(tr('Import Config'), tr('No matching JSON files found in configs/export.'))
        return
    end

    local inputBox = UIInputBox.create(tr('Import Config'), function(option)
        local fileName = option
        if type(option) == 'table' then
            fileName = option.text or option
        end
        if not fileName or fileName == '' then
            return
        end
        local payload, err = readPayload(fileName)
        if not payload then
            showMessage(tr('Import Config'), err or tr('Import failed.'))
            return
        end
        local ok, message = importPayload(payload, categoryId)
        if ok then
            showMessage(tr('Import Config'), message or tr('Import successful.'))
        else
            showMessage(tr('Import Config'), message or tr('Import failed.'))
        end
    end)
    inputBox:addLabel(tr('Choose a JSON file from configs/export:'))
    inputBox:addComboBox(nil, unpack(files))
    inputBox:display()
end

local function showCategoryMenu(mode)
    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)

    for _, category in ipairs(CATEGORIES) do
        local label = category.label
        if mode == 'import' then
            label = category.label:gsub('^Export ', 'Import ')
        end
        menu:addOption(tr(label), function()
            if mode == 'export' then
                promptExport(category.id)
            else
                promptImport(category.id)
            end
        end)
    end

    menu:display(g_window.getMousePosition())
end

function showExportConfigMenu()
    showCategoryMenu('export')
end

function showImportConfigMenu()
    showCategoryMenu('import')
end

function openConfigFolder()
    ensureExportDir()
    local directory = g_resources.getWriteDir() or ''
    directory = directory:gsub('[/\\]+', '\\')
    if directory == '' then
        showMessage(tr('Dir Folder'), tr('Could not resolve the client data folder.'))
        return
    end
    g_platform.openDir(directory)
end
