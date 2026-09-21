local function releaseHandCursor(widget)
	if not widget.cursorPushed then
		return
	end

	if modules.client_options and modules.client_options.getOption("nativeCursor") then
		g_window.restoreMouseCursor()
	else
		g_mouse.popCursor("pointerbutton")
	end

	widget.cursorPushed = false
end

local function pushHandCursor(widget)
	if widget.cursorPushed or not modules.client_options then
		return
	end

	local nativeCursor = modules.client_options.getOption("nativeCursor")
	local animatedCursor = modules.client_options.getOption("showAnimatedCursor")

	if animatedCursor and not nativeCursor then
		g_mouse.pushCursor("pointerbutton")
		widget.cursorPushed = true
	elseif nativeCursor then
		g_window.setSystemCursor("hand")
		widget.cursorPushed = true
	end
end

local function applyHandCursorHover(widget, hovered)
	if widget.cursorPushed == nil then
		widget.cursorPushed = false
	end

	if modules.game_clienthelp and modules.game_clienthelp.isClientHelpActive() then
		releaseHandCursor(widget)
		return
	end

	if not modules.client_options then
		releaseHandCursor(widget)
		return
	end

	if g_ui.getDraggingWidget() or g_ui.isMouseGrabbed() then
		releaseHandCursor(widget)
		return
	end

	if hovered then
		pushHandCursor(widget)
	else
		releaseHandCursor(widget)
	end
end

function onSkillRowHoverChange(widget, hovered)
	if SKILL_HAND_CURSOR_IDS[widget:getId()] then
		applyHandCursorHover(widget, hovered)
	else
		releaseHandCursor(widget)
	end
end

function onXpBoostHoverChange(widget, hovered)
	applyHandCursorHover(widget, hovered)
end

function bindSkillsHoverHandlers()
	if not skillsWindow or skillsWindow:isDestroyed() then
		return
	end

	local contentsPanel = skillsWindow:getChildById("contentsPanel")

	if not contentsPanel then
		return
	end

	local function walk(widget)
		if widget:getClassName() == "UIButton" then
			widget.onHoverChange = onSkillRowHoverChange

			if widget.cursorPushed == nil then
				widget.cursorPushed = false
			end
		end

		for _, child in ipairs(widget:getChildren()) do
			walk(child)
		end
	end

	walk(contentsPanel)

	local xpBoostButton = skillsWindow:recursiveGetChildById("xpBoostButton")

	if xpBoostButton then
		xpBoostButton.onHoverChange = onXpBoostHoverChange

		if xpBoostButton.cursorPushed == nil then
			xpBoostButton.cursorPushed = false
		end
	end
end
