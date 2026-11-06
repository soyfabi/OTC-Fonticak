CreateCharacter = {}
local window, worlds, selectedWorld
local requests = {}
local generation = 0
local busy = false
local sex = 'male'

local function widget(id) return window:recursiveGetChildById(id) end

local function request(data, callback)
    local url = Services and Services.createAccount
    if type(url) ~= 'string' or url == '' then
        displayErrorBox(tr('Create Character'), tr('The registration service is not configured.'))
        return
    end
    local token = generation
    local id = HTTP.post(url, json.encode(data), function(body, err)
        if token ~= generation or not window then return end
        local ok, result = pcall(json.decode, body or '')
        if err or not ok or type(result) ~= 'table' then
            displayErrorBox(tr('Create Character'), tr('Could not contact the character creation service.'))
            busy = false
            CreateCharacter.validate()
            return
        end
        callback(result)
    end, false)
    if id then table.insert(requests, id) end
end

function CreateCharacter.validate()
    if not window then return end
    local nameInput, nameStatus, createButton = widget('characterName'), widget('nameStatus'), widget('createButton')
    if not nameInput or not nameStatus or not createButton then return end
    local name = nameInput:getText()
    local valid = #name >= 3 and #name <= 29 and name:match('^[A-Z][a-z]+[A-Za-z %-]*$') ~= nil
    nameStatus:setEnabled(valid)
    createButton:setEnabled(valid and selectedWorld ~= nil and not busy)
end

function CreateCharacter.selectSex(value)
    sex = value
    widget('male'):setChecked(value == 'male')
    widget('female'):setChecked(value == 'female')
end

function CreateCharacter.selectWorld(world)
    selectedWorld = world
    widget('worldInfo'):setText(world.Name)
    local values = {
        PlayersOnline = tostring(world.PlayersOnline or 0), PvPType = world.PvPType or '',
        Region = world.Region or '', CreationDate = world.CreationDate and world.CreationDate > 0 and os.date('%b %Y', world.CreationDate) or 'Unknown',
        Protection = 'Not protected', PremiumOnly = world.PremiumOnly == 1 and 'true' or 'false',
        TransferType = world.TransferType or ''
    }
    for id, value in pairs(values) do widget(id):setText(value) end
    CreateCharacter.validate()
end

function CreateCharacter.filterWorlds()
    if not window then return end
    local region = widget('region'):getCurrentOption().text
    local pvp = widget('pvp'):getCurrentOption().text
    local list = widget('worldList')
    list:destroyChildren()
    selectedWorld = nil
    local first
    for _, world in ipairs(worlds or {}) do
        if (region == 'All' or region == world.Region) and (pvp == 'All' or pvp == world.PvPType) then
            local row = g_ui.createWidget('CharacterSelectionRow', list)
            if not row then
                g_logger.error('Could not create character world selection row.')
                return
            end
            row:getChildById('details'):setText(world.Name)
            row.onFocusChange = function(self, focused)
                if focused then CreateCharacter.selectWorld(world) end
            end
            first = first or row
        end
    end
    if first then list:focusChild(first, KeyboardFocusReason) end
    CreateCharacter.validate()
end

function CreateCharacter.show()
    if window then window:raise() window:focus() return end
    if not G.account or G.account == '' or not G.password or G.password == '' then
        displayErrorBox(tr('Create Character'), tr('Please log in to your account first.'))
        return
    end
    window = g_ui.displayUI('createcharacter')
    CharacterList.hide()
    selectedWorld, worlds, sex, busy = nil, {}, 'male', false
    widget('region'):addOption('All')
    widget('pvp'):addOption('All')
    CreateCharacter.validate()
    request({type = 'getaccountcreationstatus'}, function(result)
        worlds = result.Worlds or {}
        local regions, pvps = {}, {}
        for _, world in ipairs(worlds) do
            if not regions[world.Region] then widget('region'):addOption(world.Region) regions[world.Region] = true end
            if not pvps[world.PvPType] then widget('pvp'):addOption(world.PvPType) pvps[world.PvPType] = true end
        end
        widget('region').onOptionChange = CreateCharacter.filterWorlds
        widget('pvp').onOptionChange = CreateCharacter.filterWorlds
        CreateCharacter.filterWorlds()
    end)
end

function CreateCharacter.close(showList)
    generation = generation + 1
    for _, id in ipairs(requests) do HTTP.cancel(id) end
    requests = {}
    if window then window:destroy() window = nil end
    selectedWorld, worlds, busy = nil, nil, false
    if showList then CharacterList.show() end
end

function CreateCharacter.suggestName()
    request({type = 'generatecharactername'}, function(result)
        if result.GeneratedName then widget('characterName'):setText(result.GeneratedName) end
    end)
end

function CreateCharacter.submit()
    if not window or not widget('createButton'):isEnabled() then return end
    busy = true
    CreateCharacter.validate()
    request({type = 'createcharacter', Account = G.account, Password = G.password,
        CharacterName = widget('characterName'):getText(), CharacterSex = sex,
        World = selectedWorld.Name}, function(result)
        busy = false
        if result.Success then
            CreateCharacter.close(false)
            -- Reload the authenticated character list through the normal login flow.
            EnterGame.setAccountName(g_crypt.encrypt(G.account))
            EnterGame.setPassword(g_crypt.encrypt(G.password))
            EnterGame.doLogin()
        else
            CreateCharacter.validate()
            displayErrorBox(tr('Create Character'), result.errorMessage or tr('Character creation failed.'))
        end
    end)
end
