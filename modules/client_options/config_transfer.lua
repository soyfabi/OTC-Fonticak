-- Export / import client options and hotkeys as JSON files under /configs/export/
-- Also upload/download shareable hashes via the Fonticak config Worker.

local CONFIG_FORMAT = 'otc-fonticak-config'
local CONFIG_VERSION = 1
local EXPORT_DIR = '/configs/export'

local CATEGORIES = {
    {
        id = 'generalHotkey',
        name = 'General Hotkey',
    },
    {
        id = 'customHotkey',
        name = 'Custom Hotkey',
    },
    {
        id = 'interface',
        name = 'Interface',
        panels = { 'interface', 'interfaceHUD', 'interfaceGameWindow', 'interfaceConsole', 'actionbars' },
    },
    {
        id = 'graphics',
        name = 'Graphics',
        panels = { 'graphicsPanel', 'graphicsEffectsPanel', 'graphicsAnimationPanel' },
    },
    {
        id = 'sound',
        name = 'Sound',
        panels = { 'soundPanel' },
    },
    {
        id = 'misc',
        name = 'Misc',
        panels = { 'misc', 'miscGameplay', 'miscScreenshot', 'miscHelp' },
    },
    {
        id = 'all',
        name = 'All',
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
    if table.contains(category.panels or {}, 'miscScreenshot')
        and not panels.miscScreenshot
        and modules.game_notifications
        and modules.game_notifications.ensureScreenshotOptionsPanel then
        modules.game_notifications.ensureScreenshotOptionsPanel()
    end
    if table.contains(category.panels or {}, 'graphicsAnimationPanel')
        and not panels.graphicsAnimationPanel
        and modules.client_options.ensureGraphicsAnimationPanel then
        modules.client_options.ensureGraphicsAnimationPanel()
    end

    local keys
    if category.id == 'allOptions' and modules.client_options.getOptionKeys then
        keys = modules.client_options.getOptionKeys()
    else
        keys = collectOptionKeys(category.panels)
    end
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

    if categoryId == 'all' then
        local sections = {}
        for _, entry in ipairs(CATEGORIES) do
            if entry.id ~= 'all' then
                if entry.id == 'generalHotkey' then
                    sections[entry.id] = exportGeneralHotkeys()
                elseif entry.id == 'customHotkey' then
                    sections[entry.id] = exportCustomHotkeys()
                else
                    sections[entry.id] = exportOptionsCategory(entry)
                end
            end
        end
        if modules.client_options.getOptionKeys then
            sections.allOptions = exportOptionsCategory({ id = 'allOptions' })
        end
        payload.data = sections
    elseif categoryId == 'generalHotkey' then
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

local function validatePayload(payload)
    if type(payload) ~= 'table' or payload.format ~= CONFIG_FORMAT then
        return false, tr('This is not an OTC Fonticak options config.')
    end
    local version = tonumber(payload.version)
    if not version or version < 1 or version > CONFIG_VERSION then
        return false, tr('Unsupported config version: %s.', tostring(payload.version))
    end
    if type(payload.category) ~= 'string' or not findCategory(payload.category) then
        return false, tr('Unknown config category.')
    end
    if type(payload.data) ~= 'table' then
        return false, tr('Config has no data.')
    end
    return true
end

local function readPayload(fileName)
    ensureExportDir()
    local path = EXPORT_DIR .. '/' .. fileName
    if not g_resources.fileExists(path) then
        return nil, tr('File not found:\n%s', path)
    end
    local contents = g_resources.readFileContents(path)
    if type(contents) ~= 'string' or contents:len() > ConfigShare.maxBytes then
        return nil, tr('Config file is too large. Maximum is 1024 KB.')
    end
    local ok, payload = pcall(function()
        return json.decode(contents)
    end)
    if not ok or type(payload) ~= 'table' then
        return nil, tr('Invalid JSON file.')
    end
    local valid, validationError = validatePayload(payload)
    if not valid then
        return nil, validationError
    end
    return payload
end

local function isCompatibleOptionValue(key, value)
    local current = modules.client_options.getOption(key)
    local expectedType = type(current)
    local valueType = type(value)
    if expectedType ~= valueType then
        return false
    end
    if valueType == 'number' and (value ~= value or value == math.huge or value == -math.huge) then
        return false
    end
    return valueType == 'boolean' or valueType == 'number' or valueType == 'string' or valueType == 'table'
end

local function importOptionsCategory(payload)
    local values = payload.data and payload.data.values
    if type(values) ~= 'table' then
        return false, tr('Config file has no options data.')
    end
    local count = 0
    local skipped = 0
    for key, value in pairs(values) do
        if modules.client_options.hasOption(key) and isCompatibleOptionValue(key, value) then
            modules.client_options.setOption(key, value, true)
            count = count + 1
        else
            skipped = skipped + 1
        end
    end
    g_settings.save()
    local message = tr('Imported %d options successfully.', count)
    if skipped > 0 then
        message = message .. '\n' .. tr('Skipped %d unknown or invalid options.', skipped)
    end
    return count > 0, message
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
    if Keybind.configs.keybinds[preset] then
        Keybind.configs.keybinds[preset]:save()
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
    return true, tr('Custom hotkeys imported successfully for preset "%s".', Keybind.currentPreset)
end

local function importAll(payload)
    local data = payload.data
    if type(data) ~= 'table' then
        return false, tr('Config file has no data.')
    end

    local messages = {}
    local failures = 0
    local function runImport(categoryId, importer, section)
        if type(section) ~= 'table' then
            return
        end
        local ok, message = importer({
            format = payload.format,
            version = payload.version,
            category = categoryId,
            data = section,
        })
        if ok then
            table.insert(messages, message or categoryId)
        else
            failures = failures + 1
            table.insert(messages, tr('%s failed: %s', categoryId, message or tr('unknown error')))
        end
    end

    if type(data.allOptions) == 'table' then
        runImport('options', importOptionsCategory, data.allOptions)
    else
        for _, entry in ipairs(CATEGORIES) do
            if entry.id ~= 'all' and entry.id ~= 'generalHotkey' and entry.id ~= 'customHotkey' then
                runImport(entry.id, importOptionsCategory, data[entry.id])
            end
        end
    end
    for _, entry in ipairs(CATEGORIES) do
        if entry.id == 'generalHotkey' or entry.id == 'customHotkey' then
            local section = data[entry.id]
            if entry.id == 'generalHotkey' then
                runImport(entry.id, importGeneralHotkeys, section)
            else
                runImport(entry.id, importCustomHotkeys, section)
            end
        end
    end

    if #messages == 0 then
        return false, tr('Nothing to import in this file.')
    end
    return failures == 0, table.concat(messages, '\n')
end

local function importPayload(payload, expectedCategory)
    local valid, validationError = validatePayload(payload)
    if not valid then
        return false, validationError
    end
    if expectedCategory and payload.category ~= expectedCategory then
        return false, tr('This file belongs to category "%s", not "%s".', tostring(payload.category), expectedCategory)
    end

    local categoryId = payload.category
    if categoryId == 'all' then
        return importAll(payload)
    elseif categoryId == 'generalHotkey' then
        return importGeneralHotkeys(payload)
    elseif categoryId == 'customHotkey' then
        return importCustomHotkeys(payload)
    elseif findCategory(categoryId) then
        return importOptionsCategory(payload)
    end
    return false, tr('Unknown config category.')
end

local function fileCategoryFromName(name)
    for _, category in ipairs(CATEGORIES) do
        if name:find('^' .. category.id .. '_') then
            return category.id
        end
    end
    return nil
end

local function listExportFiles(categoryId)
    ensureExportDir()
    local files = {}
    for _, name in ipairs(g_resources.listDirectoryFiles(EXPORT_DIR, false, false, false) or {}) do
        if name:lower():find('%.json$') then
            if not categoryId then
                table.insert(files, name)
            else
                local namedCategory = fileCategoryFromName(name)
                if namedCategory == categoryId then
                    table.insert(files, name)
                elseif namedCategory == nil then
                    -- Only files without a recognizable prefix (legacy/renamed)
                    -- need a decode to identify their category.
                    local payload = select(1, readPayload(name))
                    if payload and payload.category == categoryId then
                        table.insert(files, name)
                    end
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

local function countEntries(value)
    local count = 0
    if type(value) == 'table' then
        for _ in pairs(value) do
            count = count + 1
        end
    end
    return count
end

local function payloadSummary(payload)
    local category = findCategory(payload.category)
    local summary = tr('Category: %s', category and category.name or tostring(payload.category))
    local data = payload.data or {}
    if payload.category == 'generalHotkey' then
        summary = summary .. '\n' .. tr('Preset in config: %s', tostring(data.preset or 'unknown'))
    elseif payload.category == 'customHotkey' then
        summary = summary .. '\n' .. tr('Preset in config: %s', tostring(data.preset or 'unknown'))
    elseif payload.category == 'all' then
        local allOptions = data.allOptions and data.allOptions.values
        summary = summary .. '\n' .. tr('Options: %d', countEntries(allOptions))
        local preset = data.customHotkey and data.customHotkey.preset
        if preset then
            summary = summary .. '\n' .. tr('Hotkey preset in config: %s', tostring(preset))
        end
    elseif data.values then
        summary = summary .. '\n' .. tr('Options: %d', countEntries(data.values))
    end
    if (data.preset and data.preset ~= Keybind.currentPreset)
        or (data.customHotkey and data.customHotkey.preset and data.customHotkey.preset ~= Keybind.currentPreset) then
        summary = summary .. '\n\n' .. tr('Hotkeys will be applied to active preset "%s".', Keybind.currentPreset)
    end
    return summary
end

local function runImportWithConfirmation(payload, expectedCategory, title)
    local valid, validationError = validatePayload(payload)
    if not valid then
        showMessage(title, validationError)
        return
    end

    local function applyImport()
        local ok, message = importPayload(payload, expectedCategory)
        showMessage(title, message or (ok and tr('Import successful.') or tr('Import failed.')))
    end

    local destructive = payload.category == 'all'
        or payload.category == 'generalHotkey'
        or payload.category == 'customHotkey'
    if not destructive then
        applyImport()
        return
    end

    local box
    local accept = function()
        if box then box:destroy() end
        applyImport()
    end
    local cancel = function()
        if box then box:destroy() end
    end
    box = displayGeneralBox(
        tr('Confirm Import'),
        payloadSummary(payload) .. '\n\n' .. tr('This import will overwrite existing settings. Continue?'),
        {
            { text = tr('Cancel'), callback = cancel },
            { text = tr('Import'), callback = accept },
            anchor = AnchorHorizontalCenter,
        },
        accept,
        cancel
    )
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
        runImportWithConfirmation(payload, categoryId, tr('Import Config'))
    end)
    inputBox:addLabel(tr('Choose a JSON file from configs/export:'))
    inputBox:addComboBox(nil, unpack(files))
    inputBox:display()
end

local function promptUploadHash(categoryId)
    local category = findCategory(categoryId)
    if not category then
        return
    end

    local payloadOk, payload = pcall(function()
        return buildPayload(categoryId)
    end)
    if not payloadOk or not payload then
        showMessage(tr('Upload Hash'), tr('Could not build config payload:\n%s', tostring(payload)))
        return
    end

    if not json or not json.encode then
        showMessage(tr('Upload Hash'), tr('JSON library is not available.'))
        return
    end

    local encodeOk, encoded = pcall(function()
        return json.encode(payload)
    end)
    if not encodeOk or type(encoded) ~= 'string' or encoded:len() == 0 then
        showMessage(tr('Upload Hash'), tr('Failed to encode JSON:\n%s', tostring(encoded)))
        return
    end
    if encoded:len() > ConfigShare.maxBytes then
        showMessage(tr('Upload Hash'), tr('Config is too big (%s KB). Maximum is 1024 KB.', math.floor(encoded:len() / 1024)))
        return
    end

    local infoBox = displayInfoBox(tr('Uploading config'), tr('Uploading "%s". Please wait.', category.name))
    local configName = ('options_' .. categoryId):gsub('%s+', '_')
    local operation, startError = ConfigShare.upload('options', configName, encoded, function(data, err)
        if infoBox then
            infoBox:destroy()
        end
        local hash, responseError, response = ConfigShare.parseUploadResponse(data, err)
        if not hash then
            showMessage(tr('Upload Hash'), tr('Upload failed:\n%s', responseError))
            return
        end
        g_window.setClipboardText(hash)
        local message = response.message or ('Config hash: ' .. hash)
        showMessage(tr('Upload Hash'), tr('%s\n\n%s\n\nHash copied to clipboard. Share it so others can download with Download Hash.', category.name, message))
    end)
    if not operation then
        infoBox:destroy()
        showMessage(tr('Upload Hash'), startError)
    end
end

local function promptDownloadHash()
    displayInputBox(tr('Download Hash'), tr('Paste the config hash code:'), function(hash)
        hash = ConfigShare.normalizeHash(hash)
        if not hash then
            showMessage(tr('Download Hash'), tr('Enter a valid 12-character config hash.'))
            return
        end

        local infoBox = displayInfoBox(tr('Downloading config'), tr('Downloading config with hash %s. Please wait.', hash))
        local operation, startError = ConfigShare.download('options', hash, 'json', function(path, checksum, err)
            if infoBox then
                infoBox:destroy()
            end
            if err then
                showMessage(tr('Download Hash'), tr('Config with hash %s cannot be downloaded:\n%s', hash, err))
                return
            end

            local filePath = '/downloads/' .. path
            if not g_resources.fileExists(filePath) then
                showMessage(tr('Download Hash'), tr('Downloaded file was not found.'))
                return
            end
            local contents = g_resources.readFileContents(filePath)
            if type(contents) ~= 'string' or contents:len() > ConfigShare.maxBytes then
                showMessage(tr('Download Hash'), tr('Downloaded config is too large.'))
                return
            end
            local decodeOk, payload = pcall(function() return json.decode(contents) end)
            if not decodeOk or type(payload) ~= 'table' then
                showMessage(tr('Download Hash'), tr('This hash is not an OTC Fonticak options config.'))
                return
            end
            runImportWithConfirmation(payload, nil, tr('Download Hash'))
        end)
        if not operation then
            infoBox:destroy()
            showMessage(tr('Download Hash'), startError)
        end
    end)
end

local function showCategoryMenu(mode)
    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)

    for _, category in ipairs(CATEGORIES) do
        local verb = mode == 'import' and 'Import' or (mode == 'upload' and 'Upload' or 'Export')
        local label = verb .. ' ' .. category.name
        menu:addOption(tr(label), function()
            if mode == 'export' then
                promptExport(category.id)
            elseif mode == 'upload' then
                promptUploadHash(category.id)
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

function showUploadConfigHashMenu()
    showCategoryMenu('upload')
end

function showDownloadConfigHash()
    promptDownloadHash()
end

function openConfigFolder()
    ensureExportDir()
    local writeDir = g_resources.getWriteDir() or ''
    if writeDir == '' then
        showMessage(tr('Open Folder'), tr('Could not resolve the client data folder.'))
        return
    end
    local directory = (writeDir .. EXPORT_DIR):gsub('[/\\]+', '\\')
    g_platform.openDir(directory)
end
