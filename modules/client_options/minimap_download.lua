local rows
local refreshEvent
local activeRow

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

    if downloading then
        refreshEvent = scheduleEvent(refresh, 250)
    elseif activeRow then
        local row = activeRow
        activeRow = nil
        local status = row.status
        if status == 'installed' and not row.animations then
            local minimap = modules.game_minimap
            local cyclopedia = modules.game_cyclopedia
            if minimap and minimap.refreshMinimapPreferences then
                minimap.refreshMinimapPreferences()
            end
            if cyclopedia and cyclopedia.refreshMapMinimapPreferences then
                cyclopedia.refreshMapMinimapPreferences()
            end
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
        { animations = false, title = tr('Download Map HD'), button = panel.downloadHdMap, label = panel.hdDownloadStatus },
        { animations = true, title = tr('Download Animation Map'), button = panel.downloadAnimationMap, label = panel.animationDownloadStatus }
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

function toggleMinimapPackDownload(animations)
    if refreshEvent then
        g_minimap.cancelPackDownload()
        return
    end
    activeRow = rows[animations and 2 or 1]
    g_minimap.startPackDownload(animations)
    refresh()
end

function terminateMinimapAnimationDownload()
    if refreshEvent then
        removeEvent(refreshEvent)
        refreshEvent = nil
        g_minimap.cancelPackDownload()
    end
    activeRow = nil
    rows = nil
end
