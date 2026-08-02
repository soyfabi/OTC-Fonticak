-- @docclass
UIButton = extends(UIWidget, 'UIButton')

local function releaseButtonCursor(self)
    if not self.cursorPushed then
        return
    end
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.restoreMouseCursor()
    else
        g_mouse.popCursor('pointerbutton')
    end
    self.cursorPushed = false
end

function UIButton.create()
    local button = UIButton.internalCreate()
    button:setFocusable(false)
    button.cursorPushed = false
    return button
end

function UIButton:onMouseRelease(pos, button)
    return self:isPressed()
end

function UIButton:onDestroy()
    releaseButtonCursor(self)
end

function UIButton:onVisibilityChange(visible)
    if not visible then
        releaseButtonCursor(self)
    end
end

function UIButton:onHoverChange(hovered)
    if not modules.client_options then
        UIWidget.onHoverChange(self, hovered)
        return
    end

    -- Popup menus / drag grab the mouse; always release the hover cursor or it sticks as Link Select
    if g_ui.getDraggingWidget() or g_ui.isMouseGrabbed() then
        releaseButtonCursor(self)
        UIWidget.onHoverChange(self, hovered)
        return
    end

    local nativeCursor = modules.client_options.getOption('nativeCursor')
    local animatedCursor = modules.client_options.getOption('showAnimatedCursor')

    -- Animated cursor mode - show pointer button on hover
    if animatedCursor and not nativeCursor then
        if hovered then
            if not self.cursorPushed then
                g_mouse.pushCursor('pointerbutton')
                self.cursorPushed = true
            end
        else
            releaseButtonCursor(self)
        end
    elseif nativeCursor then
        if hovered then
            if not self.cursorPushed then
                g_window.setSystemCursor('hand')
                self.cursorPushed = true
            end
        else
            releaseButtonCursor(self)
        end
    end
    UIWidget.onHoverChange(self, hovered)
end
