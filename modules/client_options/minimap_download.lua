local rows
local refreshEvent
local activeRow
local uninstallBox

local function refreshMapPreferences()
    local minimap = modules.game_minimap
    local cyclopedia = modules.game_cyclopedia
    if minimap and minimap.refreshMinimapPreferences then
        minimap.refreshMinimapPreferences()
    end
    if cyclopedia and cyclopedia.refreshMapMinimapPreferences then
        cyclopedia.refreshMapMinimapPreferences()
    end
end

local function refresh()
    refreshEvent = nil
    local downloading = false
    for _, row in ipairs(rows) do
        if not activeRow or row == activeRow then
            row.status = g_minimap.getPackDownloadStatus(row.animations)
        end
        downloading = downloading or row.status == 'downloading' or row.status == 'canceling'
    end

    for _, row in ipairs(rows) do
        local status = row.status
        local active = status == 'downloading' or status == 'canceling'
        row.button:setText(active and tr('Cancel Download') or row.title)
        row.button:setEnabled(status ~= 'installed' and status ~= 'canceling'
            and (not downloading or active))
        local removable = status == 'installed' and g_minimap.canUninstallPack
            and g_minimap.canUninstallPack(row.animations)
        row.uninstall:setVisible(removable == true)
        row.uninstall:setEnabled(not downloading)
        if status == 'downloading' then
            row.label:setText(tr('Downloading... %d%%', g_minimap.getPackDownloadProgress()))
        elseif status == 'canceling' then
            row.label:setText(tr('Canceling...'))
        elseif status == 'installed' then
            row.label:setText(tr('Installed'))
        else
            row.label:setText(tr('%d MB', g_minimap.getPackDownloadSizeMb(row.animations)))
        end
    end

    local minimap = modules.game_minimap
    if minimap and minimap.refreshMinimapDownloadOverlay then
        minimap.refreshMinimapDownloadOverlay()
    end
    local cyclopedia = modules.game_cyclopedia
    if cyclopedia and cyclopedia.refreshCyclopediaMapDownloadOverlay then
        cyclopedia.refreshCyclopediaMapDownloadOverlay()
    end

    if downloading then
        refreshEvent = scheduleEvent(refresh, 250)
    elseif activeRow then
        local row = activeRow
        activeRow = nil
        local status = row.status
        if status == 'installed' and not row.animations then
            refreshMapPreferences()
        elseif status ~= 'installed' and status ~= '' and status ~= 'Download canceled.' then
            displayErrorBox(row.title, status)
        end
    end
end

function initMinimapAnimationDownload(panel)
    if not g_minimap.getPackDownloadStatus then
        return
    end
    rows = {
        { animations = false, title = tr('Download Map HD'), button = panel.downloadHdMap,
            label = panel.hdDownloadStatus, uninstall = panel.uninstallHdMap },
        { animations = true, title = tr('Download Animation Map'), button = panel.downloadAnimationMap,
            label = panel.animationDownloadStatus, uninstall = panel.uninstallAnimationMap }
    }
    for _, row in ipairs(rows) do
        row.button:show()
        row.label:show()
    end
    panel.onVisibilityChange = function(_, visible)
        if visible and rows and not refreshEvent then
            refresh()
        end
    end
    refresh()
end

function getMinimapPackDownloadState()
    if not rows then
        return
    end
    return rows[1].status, rows[2].status
end

function isMinimapHdMapInstalled()
    if rows then
        return rows[1].status == 'installed'
    end
    return g_resources.fileExists('/data/minimap_hd/index.txt')
end

function toggleMinimapPackDownload(animations)
    if not rows then
        return
    end
    if refreshEvent then
        g_minimap.cancelPackDownload()
        return
    end
    activeRow = rows[animations and 2 or 1]
    g_minimap.startPackDownload(animations)
    refresh()
end

function terminateMinimapAnimationDownload()
    if uninstallBox then
        uninstallBox:destroy()
        uninstallBox = nil
    end
    if refreshEvent then
        removeEvent(refreshEvent)
        refreshEvent = nil
        g_minimap.cancelPackDownload()
    end
    activeRow = nil
    rows = nil
end

function confirmMinimapPackUninstall(animations)
    if uninstallBox or refreshEvent or not g_minimap.canUninstallPack(animations) then
        return
    end

    local title = animations and tr('Uninstall Map Animations') or tr('Uninstall HD Map')
    local message = animations and tr('Remove the downloaded map animations?')
        or tr('Remove the downloaded HD map? Map animations require the HD map to play.')
    local function close()
        uninstallBox:destroy()
        uninstallBox = nil
    end
    local function accept()
        close()
        local error = g_minimap.uninstallPack(animations)
        refresh()
        if error ~= '' then
            displayErrorBox(title, error)
        elseif not animations then
            refreshMapPreferences()
        end
    end
    uninstallBox = displayGeneralBox(title, message, {
        { text = tr('Cancel'), callback = close },
        { text = tr('Uninstall'), callback = accept },
        anchor = AnchorHorizontalCenter
    }, nil, close)
end
