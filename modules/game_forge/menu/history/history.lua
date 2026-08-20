-- chunkname: @/game_forge/menu/history/history.lua

Forge.History = {}

local History = Forge.History

History.mainWindow = nil

function History:get()
	return self
end

function History:createButton()
	local buttonPanel = g_ui.createWidget("ForgeHistoryButton", Forge.mainWindow)

	buttonPanel:addAnchor(AnchorTop, "FusionButton", AnchorTop)
	buttonPanel:addAnchor(AnchorLeft, "ConversionButton", AnchorRight)
	buttonPanel:setId("HistoryButton")

	self.buttonPanel = buttonPanel
	self.mainButton = buttonPanel:getChildById("button")

	self.mainButton:setText("History")
	self.mainButton:setWidth(self.mainButton:getWidth() + 2)
	Forge.setupTabButtonIcon(buttonPanel, "/images/icons_big/icon-history", 6, 3)

	if not self.mainWindow then
		g_ui.importStyle("History")

		self.mainWindow = g_ui.createWidget("HistoryWindow", Forge.mainWindow)

		self.mainWindow:setVisible(false)
		self.mainWindow:addAnchor(AnchorTop, "TransferButton", AnchorBottom)
		self.mainWindow:addAnchor(AnchorLeft, "FusionButton", AnchorLeft)
		self.mainWindow:addAnchor(AnchorRight, "parent", AnchorRight)
		self.mainWindow:addAnchor(AnchorBottom, "parent", AnchorBottom)

		self.historyListContainer = self.mainWindow:getChildById("historyListContainer")
		self.contentPanel = self.historyListContainer:getChildById("contentPanel")
		self.prevButton = self.mainWindow:getChildById("historyPrevButton")
		self.nextButton = self.mainWindow:getChildById("historyNextButton")
		self.pageLabel = self.mainWindow:getChildById("historyPageLabel")

		if self.prevButton then
			function self.prevButton.onClick()
				self:requestPage(self.pageIndex - 1)
			end
		end

		if self.nextButton then
			function self.nextButton.onClick()
				self:requestPage(self.pageIndex + 1)
			end
		end
	end

	self.pageIndex = 0
	self.pageCount = 1

	function self.mainButton.onClick(widget, mousePos, mouseButton)
		self:showWindow()
	end
end

function History:clearList()
	if self.contentPanel then
		self.contentPanel:destroyChildren()
	end

	local scrollBar = self.historyListContainer and self.historyListContainer:getChildById("historyListScrollbar")

	if scrollBar and scrollBar.setValue then
		scrollBar:setValue(0)
	end
end

function History:requestPage(pageIndex)
	pageIndex = tonumber(pageIndex) or 0

	if pageIndex < 0 then
		pageIndex = 0
	end

	local pageCount = math.max(self.pageCount or 1, 1)

	if pageCount <= pageIndex then
		pageIndex = pageCount - 1
	end

	self.pageIndex = pageIndex

	forgeSendHistory(pageIndex)
end

function History:updatePagination()
	local pageIndex = self.pageIndex or 0
	local pageCount = math.max(self.pageCount or 1, 1)
	local displayPage = pageIndex + 1

	if self.pageLabel then
		self.pageLabel:setText(string.format("Page %d/%d", displayPage, pageCount))
	end

	if self.prevButton then
		-- Only show Previous when there is a page before the current one.
		self.prevButton:setVisible(pageIndex > 0)
		self.prevButton:setEnabled(pageIndex > 0)
	end

	if self.nextButton then
		-- Only show Next when there is a page after the current one.
		self.nextButton:setVisible(displayPage < pageCount)
		self.nextButton:setEnabled(displayPage < pageCount)
	end
end

function History:showWindow()
	if Forge.currentPanel then
		Forge.currentPanel:setVisible(false)
	end

	if Forge.currentButton then
		Forge.currentButton:setEnabled(true)
		Forge.onTabButtonEnabled(Forge.currentButton, nil, true)
	end

	Forge.currentPanel = self.mainWindow
	Forge.currentButton = self.mainButton

	Forge.firstTooltip:setVisible(false)
	self:clearList()

	self.pageIndex = 0

	self:updatePagination()
	self.mainWindow:setVisible(true)
	self.mainWindow:raise()
	self.mainButton:setEnabled(false)
	Forge.onTabButtonEnabled(nil, self.buttonPanel, false)
	self:requestPage(0)
end

local TOOLTIP_BULLET_PREFIX = "     \x95 "

local function stripInlineHtml(s)
	s = s:gsub("<[bB][rR]%s*/?>", " ")
	s = s:gsub("<[^>]+>", "")
	s = s:gsub("&nbsp;", " ")
	s = s:gsub("&lt;", "<")
	s = s:gsub("&gt;", ">")
	s = s:gsub("&quot;", "\"")
	s = s:gsub("&amp;", "&")
	s = s:gsub("%s+", " ")

	return s:match("^%s*(.-)%s*$") or ""
end

local function formatForgeHistoryTooltip(raw)
	if not raw or raw == "" then
		return nil
	end

	local text = raw

	text = text:gsub("Unsuccessful", "Failed")
	text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
	text = text:gsub("<[lL][iI][^>]*>([%s%S]-)</[lL][iI]>", function(content)
		return "\n@@LI@@" .. stripInlineHtml(content) .. "\n"
	end)
	text = text:gsub("<[bB][rR]%s*/?>", "\n")
	text = text:gsub("</?[uUoO][lL][^>]*>", "\n")
	text = text:gsub("<[^>]+>", "")
	text = text:gsub("&nbsp;", " ")
	text = text:gsub("&lt;", "<")
	text = text:gsub("&gt;", ">")
	text = text:gsub("&quot;", "\"")
	text = text:gsub("&amp;", "&")

	local tokens = {}

	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		line = line:gsub("^[%s\t]+", ""):gsub("[%s\t]+$", "")

		if line ~= "" then
			if line:sub(1, 6) == "@@LI@@" then
				local content = line:sub(7):gsub("^[%s\t]+", "")

				if content ~= "" then
					tokens[#tokens + 1] = {
						type = "li",
						text = content
					}
				end
			elseif line:find(":$") then
				tokens[#tokens + 1] = {
					type = "section",
					text = line
				}
			else
				tokens[#tokens + 1] = {
					type = "title",
					text = line
				}
			end
		end
	end

	if #tokens == 0 then
		return nil
	end

	local out = {}

	for _, token in ipairs(tokens) do
		if token.type == "title" then
			if #out > 0 and out[#out] ~= "" then
				out[#out + 1] = ""
			end

			out[#out + 1] = token.text
			out[#out + 1] = ""
		elseif token.type == "section" then
			if #out > 0 and out[#out] ~= "" then
				out[#out + 1] = ""
			end

			out[#out + 1] = token.text
		elseif token.type == "li" then
			out[#out + 1] = TOOLTIP_BULLET_PREFIX .. token.text
		end
	end

	while #out > 0 and out[#out] == "" do
		table.remove(out)
	end

	return table.concat(out, "\n")
end

local function stripDetailsPlainText(details)
	if not details or details == "" then
		return ""
	end

	return stripInlineHtml(details)
end

local function resolveHistoryDetails(details, actionType)
	actionType = tonumber(actionType) or 0

	if not details or details == "" then
		return "", nil
	end

	if actionType >= 2 then
		return stripDetailsPlainText(details), nil
	end

	local summary

	summary = (details:find("Unsuccessful", 1, true) or details:find("Failed", 1, true)) and "Failed" or details:find("Successful", 1, true) and "Successful" or stripDetailsPlainText(details)

	return summary, formatForgeHistoryTooltip(details)
end

function History:addDate(date, action, detailsSummary, detailsTooltip, rowIndex, hasBonus)
	local row = g_ui.createWidget("ForgeHistoryRow", self.contentPanel)
	local dateLabel = row:getChildById("date")

	if dateLabel then
		dateLabel:setText(date or "")
	end

	local actionLabel = row:getChildById("action")

	if actionLabel then
		actionLabel:setText(action or "")

		if hasBonus and action == "Fusion" then
			actionLabel:setColor("#3FBBCA")
		else
			actionLabel:setColor("#C0C0C0")
		end
	end

	local detailsLabel = row:getChildById("details")

	if detailsLabel then
		detailsLabel:setText(detailsSummary or "")
	end

	local detailsHit = row:getChildById("detailsHit")

	if detailsHit then
		if detailsTooltip and detailsTooltip ~= "" then
			detailsHit:setTooltip(detailsTooltip)
		elseif detailsHit.removeTooltip then
			detailsHit:removeTooltip()
		else
			detailsHit.tooltip = nil
		end
	end

	row:setBackgroundColor((rowIndex or 1) % 2 == 0 and "#414141" or "#484848")
end

function getStringByActionType(value)
	if value == 0 then
		return "Fusion"
	end

	if value == 1 then
		return "Transfer"
	end

	if value >= 2 then
		return "Conversion"
	end

	return "Unknown"
end

function History:parse(currentPage, lastPage, data)
	currentPage = tonumber(currentPage) or 0
	lastPage = math.max(tonumber(lastPage) or 1, 1)
	self.pageIndex = math.max(currentPage, 0)

	if lastPage <= self.pageIndex then
		self.pageIndex = lastPage - 1
	end

	self.pageCount = lastPage

	self:clearList()

	for i, v in ipairs(data or {}) do
		local actionType = tonumber(v.action) or 0
		local summary, tip = resolveHistoryDetails(v.details, actionType)
		local hasBonus = v.bonus == true or v.bonus == 1

		self:addDate(v.date, getStringByActionType(actionType), summary, tip, i, hasBonus)
	end

	self:updatePagination()
end
