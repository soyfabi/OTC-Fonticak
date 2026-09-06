if not Categories then
	Categories = {}
	Categories.__index = Categories

	Categories.categoryTable = {}
	Categories.buttonSize = 20
	Categories.selectButton = nil
	Categories.selectTreeItem = nil
	Categories.name = ''
	Categories.signature = nil
	Categories.widgets = {}
	Categories.renderEvent = nil
	Categories.renderGeneration = 0
end

local CATEGORIES_SHEET = '/images/store/categories'
local categoryIconClips = {
	store_equipment = 1,
	store_weapons = 1,
	store_houses = 2,
	store_consumables = 6,
	store_backpacks = 6,
	store_services = 7,
	store_blessings = 8,
	store_prey = 9,
	xp_boost = 9,
	prey_wildcard = 9,
	store_potions = 10,
	store_mounts = 14,
	store_outfits = 15,
	store_extras = 16,
	store_premium = 20,
	store_cosmetics = 21,
	store_furniture = 22,
	store_beds = 22,
	store_decorations = 23,
	store_upgrades = 2,
}

local function resolveCategoryIconClip(icon, name)
	local key = tostring(icon or ''):lower():gsub('%.png$', '')
	if categoryIconClips[key] then
		return categoryIconClips[key]
	end

	local label = tostring(name or ''):lower()
	if label:find('premium', 1, true) or label:find('battle pass', 1, true) then
		return categoryIconClips.store_premium
	elseif label:find('boost', 1, true) then
		return categoryIconClips.xp_boost
	elseif label:find('consumable', 1, true) then
		return categoryIconClips.store_consumables
	elseif label:find('potion', 1, true) then
		return categoryIconClips.store_potions
	elseif label:find('bless', 1, true) then
		return categoryIconClips.store_blessings
	elseif label:find('prey', 1, true) then
		return categoryIconClips.store_prey
	elseif label:find('weapon', 1, true) then
		return categoryIconClips.store_weapons
	elseif label:find('backpack', 1, true) or label:find('container', 1, true) then
		return categoryIconClips.store_backpacks
	elseif label:find('equipment', 1, true) then
		return categoryIconClips.store_equipment
	elseif label:find('outfit', 1, true) then
		return categoryIconClips.store_outfits
	elseif label:find('mount', 1, true) then
		return categoryIconClips.store_mounts
	elseif label:find('cosmetic', 1, true) then
		return categoryIconClips.store_cosmetics
	elseif label:find('upgrade', 1, true) then
		return categoryIconClips.store_upgrades
	elseif label:find('bed', 1, true) then
		return categoryIconClips.store_beds
	elseif label:find('furniture', 1, true) then
		return categoryIconClips.store_furniture
	elseif label:find('decoration', 1, true) or label:find('decor', 1, true) then
		return categoryIconClips.store_decorations
	elseif label:find('house', 1, true) then
		return categoryIconClips.store_houses
	elseif label:find('extra', 1, true) or label:find('service', 1, true) then
		return categoryIconClips.store_extras
	end

	if key:find('house', 1, true) or key:find('upgrade', 1, true) then
		return categoryIconClips.store_houses
	end
	if key:find('bed', 1, true) then
		return categoryIconClips.store_beds
	end
	if key:find('decor', 1, true) or key:find('furniture', 1, true) or key:find('category_', 1, true) then
		return categoryIconClips.store_furniture
	end

	return nil
end

local function applyCategoryIcon(iconWidget, icon, name)
	if not iconWidget then
		return
	end

	iconWidget:setImageClip('0 0 13 13')

	if name == 'Home' then
		iconWidget:setImageSource('/images/store/icon-store-home')
		return
	end
	if name == 'Search' then
		iconWidget:setImageSource('/images/store/icon-store-search-result')
		return
	end

	local label = tostring(name or ''):lower()
	if label:find('boost', 1, true) then
		iconWidget:setImageSource('/images/icons/xp_boost')
		return
	end

	local clipId = resolveCategoryIconClip(icon, name)
	if clipId then
		iconWidget:setImageSource(CATEGORIES_SHEET)
		iconWidget:setImageClip(string.format('%d 0 13 13', clipId * 13))
		return
	end

	local iconPath = tostring(icon or '')
	if iconPath ~= '' and (g_resources.fileExists(iconPath) or g_resources.fileExists('/images/store/' .. iconPath) or g_resources.fileExists('/images/store/' .. iconPath .. '.png')) then
		if not iconPath:find('/', 1, true) then
			iconPath = '/images/store/' .. iconPath:gsub('%.png$', '')
		end
		iconWidget:setImageSource(iconPath)
		return
	end

	iconWidget:setImageSource(CATEGORIES_SHEET)
	iconWidget:setImageClip(string.format('%d 0 13 13', 13))
end

local function getCategoriesSignature(categories)
	local parts = {}
	for _, category in ipairs(categories or {}) do
		parts[#parts + 1] = table.concat({
			tostring(category.name or ""),
			tostring(category.icon or ""),
			tostring(category.parent or ""),
			tostring(category.description or "")
		}, "\31")
	end
	return table.concat(parts, "\30")
end

function Categories:cancelRender()
	removeEvent(Categories.renderEvent)
	Categories.renderEvent = nil
	Categories.renderGeneration = Categories.renderGeneration + 1
end

function Categories:configure(categories)
	local categoryPanel = StoreWindow.categories
	local signature = getCategoriesSignature(categories)
	if Categories.signature == signature and not Categories.renderEvent and categoryPanel:getChildCount() > 0 then
		return
	end

	Categories:cancelRender()
	local generation = Categories.renderGeneration
	for _, treeItem in pairs(Categories.widgets or {}) do
		if treeItem and not treeItem:isDestroyed() and g_effects then
			g_effects.cancelValue(treeItem)
		end
	end
	categoryPanel:destroyChildren()
	Categories.widgets = {}
	Categories.selectTreeItem = nil

	Categories.categoryTable = {
		[0] = {name = "Home", icon = "/images/store/icon-store-home"},
	}

	local createdCategories = {Home = true}
	local categoryByName = {Home = Categories.categoryTable[0]}

	for _, category in ipairs(categories or {}) do
		local parentName = category.parent or ''
		if #parentName == 0 then
			local existing = categoryByName[category.name]
			if existing then
				existing.icon = category.icon
			elseif not createdCategories[category.name] then
				local entry = {name = category.name, icon = category.icon}
				createdCategories[category.name] = true
				categoryByName[category.name] = entry
				Categories.categoryTable[#Categories.categoryTable + 1] = entry
			end
		else
			local parent = categoryByName[parentName]
			if parent and not createdCategories[category.name] then
				parent.childs = parent.childs or {}
				createdCategories[category.name] = true
				parent.childs[#parent.childs + 1] = {name = category.name, icon = category.icon}
			end
		end
	end

	Categories.categoryTable[#Categories.categoryTable + 1] = {
		name = "Search",
		icon = "/images/store/icon-store-search-result",
		disabled = true
	}

	local id = 0
	local function renderNextBatch()
		if generation ~= Categories.renderGeneration or categoryPanel:isDestroyed() then
			return
		end

		local lastId = math.min(id + 2, #Categories.categoryTable)
		while id <= lastId do
			local cat = Categories.categoryTable[id]
			local widget = g_ui.createWidget('TreeItem', categoryPanel)
			widget:setId(id)
			Categories.widgets[id] = widget
			widget.mainButton.text:setText(cat.name)
			if cat.childs and #cat.childs > 0 then
				widget.mainButton.scroll:setVisible(true)
			else
				widget.mainButton.scroll:setHeight(0)
			end

			if cat.disabled then
				widget:setVisible(false)
			end

			applyCategoryIcon(widget.mainButton.icon, cat.icon, cat.name)

			widget.mainButton.onClick = function()
				Categories:onSelectCategory(widget.mainButton)
			end
			id = id + 1
		end

		if id <= #Categories.categoryTable then
			Categories.renderEvent = scheduleEvent(renderNextBatch, 1)
			return
		end

		Categories.renderEvent = nil
		Categories.signature = signature

		if Categories.pendingCategory then
			local pending = Categories.pendingCategory
			Categories.pendingCategory = nil
			Categories:selectCategoryByName(pending.category, pending.subCategory)
		end
	end

	renderNextBatch()
end

local STORE_ACCORDION_MS = 240
local STORE_ARROW_CLOSED = '/images/arrows/icon-arrow7x7-right'
local STORE_ARROW_OPEN = '/images/arrows/icon-arrow7x7-down'

local function storeSlideEnabled()
	return modules.client_options
		and modules.client_options.isSlideAnimationEnabled
		and modules.client_options.isSlideAnimationEnabled('showStoreAnimation')
end

local function storeSlideDuration(baseMs)
	if modules.client_options and modules.client_options.getSlideAnimationDuration then
		return modules.client_options.getSlideAnimationDuration(baseMs or STORE_ACCORDION_MS)
	end
	return baseMs or STORE_ACCORDION_MS
end

local function setStoreCategoryScroll(treeItem, isOpen)
	if not treeItem or treeItem:isDestroyed() or not treeItem.mainButton then
		return
	end
	local scroll = treeItem.mainButton.scroll
	if not scroll or scroll:isDestroyed() or not scroll:isVisible() then
		return
	end
	scroll:setImageSource(isOpen and STORE_ARROW_OPEN or STORE_ARROW_CLOSED)
end

local function finishCollapseTreeItem(treeItem)
	if not treeItem or treeItem:isDestroyed() then
		return
	end
	if g_effects then
		g_effects.cancelValue(treeItem)
	end
	treeItem:setHeight(Categories.buttonSize)
	treeItem:setClipping(false)
	local panel = treeItem:getChildById('panel')
	local arrow = treeItem:getChildById('arrow')
	if panel and not panel:isDestroyed() then
		panel:setVisible(false)
		panel:setHeight(0)
		for _, child in pairs(panel:getChildren()) do
			if child and not child:isDestroyed() then
				child:setOpacity(1)
				child:destroy()
			end
		end
	end
	if arrow and not arrow:isDestroyed() then
		arrow:setVisible(false)
	end
	setStoreCategoryScroll(treeItem, false)
end

function Categories:collapseTreeItem(treeItem, animated)
	if not treeItem or treeItem:isDestroyed() then
		return
	end

	local closedH = Categories.buttonSize
	local from = treeItem:getHeight() or closedH
	if from <= closedH + 1 then
		finishCollapseTreeItem(treeItem)
		return
	end

	if not animated or not storeSlideEnabled() or not g_effects then
		finishCollapseTreeItem(treeItem)
		return
	end

	local panel = treeItem:getChildById('panel')
	-- Only the panel clips subcategories; TreeItem must not clip (header/icon overflow).
	treeItem:setClipping(false)
	setStoreCategoryScroll(treeItem, false)
	g_effects.cancelValue(treeItem)
	g_effects.animateValue(treeItem, from, closedH, storeSlideDuration(STORE_ACCORDION_MS), function(height)
		if not treeItem or treeItem:isDestroyed() then
			return
		end

		treeItem:setHeight(math.floor(height + 0.5))
		local span = from - closedH
		local t = math.abs(span) < 0.01 and 1 or ((from - height) / span)
		t = math.max(0, math.min(1, t))

		if panel and not panel:isDestroyed() then
			panel:setHeight(math.max(0, math.floor(height - closedH - 6 + 0.5)))
			for _, child in pairs(panel:getChildren()) do
				if child and not child:isDestroyed() then
					child:setOpacity(1 - t)
				end
			end
		end

		if math.abs(height - closedH) < 0.5 then
			finishCollapseTreeItem(treeItem)
		end
	end)
end

function Categories:collapseAll(animated)
	for _, treeItem in pairs(Categories.widgets or {}) do
		Categories:collapseTreeItem(treeItem, animated)
	end
	Categories.selectTreeItem = nil
end

function Categories:expandTreeItem(thisParent, category, name)
	if not thisParent or thisParent:isDestroyed() or not category or not category.childs then
		return nil
	end

	local childCount = #category.childs
	local panel = thisParent:getChildById('panel')
	local arrow = thisParent:getChildById('arrow')
	if not panel then
		return nil
	end

	-- TreeButton is 20px tall with margin-top 2 on every item ($first and $!first).
	-- Old formula (n*20+2) was short by ~2px per extra child and clipped the last row.
	local panelH = (childCount * (Categories.buttonSize + 2)) + 2
	local closedH = Categories.buttonSize
	local openedH = Categories.buttonSize + panelH + 6
	local printed = false
	local selectedButton = nil
	local isFirstButton = true

	for index, child in ipairs(category.childs) do
		local newWidget = g_ui.createWidget('TreeButton', panel)
		if not newWidget then
			break
		end
		newWidget:setId('TreeButton' .. tostring(index))
		newWidget:setOpacity(0)
		applyCategoryIcon(newWidget.icon, child.icon, child.name)

		local pos = (index - 1) * Categories.buttonSize + (Categories.buttonSize / 3)
		if not name and not printed then
			printed = true
			if arrow then
				arrow:setMarginTop(pos)
			end
		end

		newWidget.onClick = function()
			if selectedButton == newWidget then
				return true
			end
			if selectedButton then
				selectedButton:setOn(false)
				selectedButton.text:setColor("$var-text-cip-color")
			end
			selectedButton = newWidget
			selectedButton:setOn(true)
			selectedButton.text:setColor("$var-text-cip-color-highlight")
			if arrow then
				arrow:setMarginTop(pos)
			end
			g_game.requestStoreOffers(OPEN_CATEGORY, child.name, 0)
		end
		newWidget:getChildById('text'):setText(short_text(child.name, 16))
		if isFirstButton then
			isFirstButton = false
			selectedButton = newWidget
			selectedButton:setOn(true)
			selectedButton.text:setColor("$var-text-cip-color-highlight")
		end
	end

	if arrow then
		arrow:setVisible(true)
	end
	setStoreCategoryScroll(thisParent, true)

	local function finishExpand()
		if not thisParent or thisParent:isDestroyed() then
			return
		end
		thisParent:setHeight(openedH)
		thisParent:setClipping(false)
		if panel and not panel:isDestroyed() then
			panel:setHeight(panelH)
			panel:setVisible(true)
			for _, child in pairs(panel:getChildren()) do
				if child and not child:isDestroyed() then
					child:setOpacity(1)
				end
			end
		end
	end

	local animated = storeSlideEnabled() and g_effects
	if not animated then
		finishExpand()
		return selectedButton
	end

	-- Do not clip TreeItem: it cuts the category header and first subcategory.
	-- Panel already has clipping for the slide reveal.
	thisParent:setClipping(false)
	thisParent:setHeight(closedH)
	panel:setHeight(0)
	panel:setVisible(true)
	g_effects.cancelValue(thisParent)
	g_effects.animateValue(thisParent, closedH, openedH, storeSlideDuration(STORE_ACCORDION_MS), function(height)
		if not thisParent or thisParent:isDestroyed() then
			return
		end

		thisParent:setHeight(math.floor(height + 0.5))
		local span = openedH - closedH
		local t = math.abs(span) < 0.01 and 1 or ((height - closedH) / span)
		t = math.max(0, math.min(1, t))

		if panel and not panel:isDestroyed() then
			panel:setHeight(math.max(0, math.floor(height - closedH - 6 + 0.5)))
			for _, child in pairs(panel:getChildren()) do
				if child and not child:isDestroyed() then
					child:setOpacity(t)
				end
			end
		end

		if math.abs(height - openedH) < 0.5 then
			finishExpand()
		end
	end)

	return selectedButton
end

function Categories:onSelectCategory(widget, name)
	if not widget or not widget:getParent() then
		return
	end
	local id = tonumber(widget:getParent():getId())
	local category = Categories.categoryTable[id]
	if not category then
		return
	end

	if Categories.selectTreeItem == widget then
		return true
	end

	Categories:collapseAll(true)

	local thisParent = widget:getParent()

	if category.childs and thisParent then
		Categories:expandTreeItem(thisParent, category, name)
	elseif widget then
		widget.scroll:setHeight(0)
	end

	if not name then
		g_game.doThing(false)
		if category.name == "Home" then
			g_game.requestStoreOffers(OPEN_HOME, "", 0)
		elseif category.childs and #category.childs > 0 then
			g_game.requestStoreOffers(OPEN_CATEGORY, category.childs[1].name, 0)
		else
			g_game.requestStoreOffers(OPEN_CATEGORY, category.name, 0)
		end
		g_game.doThing(true)
	end

	if Categories.selectTreeItem and Categories.selectTreeItem ~= widget then
		if Categories.selectTreeItem.setOn then
			Categories.selectTreeItem:setOn(false)
		end
		if Categories.selectTreeItem.text then
			Categories.selectTreeItem.text:setColor("$var-text-cip-color")
		end
	end
	if widget.setOn then
		widget:setOn(true)
	end
	if widget.text then
		widget.text:setColor("$var-text-cip-color-highlight")
	end

	Categories.selectTreeItem = widget
	Categories.name = name
end

function Categories:findCategory(categoryName)
	if not categoryName then
		return nil, nil, nil
	end

	local target = tostring(categoryName):lower()

	-- 1. Exact match on main category
	for id, cat in pairs(Categories.categoryTable or {}) do
		if cat.name and cat.name:lower() == target then
			return id, cat, nil
		end
	end

	-- 2. Exact match on subcategory
	for id, cat in pairs(Categories.categoryTable or {}) do
		if cat.childs then
			for _, child in ipairs(cat.childs) do
				if child.name and child.name:lower() == target then
					return id, cat, child.name
				end
			end
		end
	end

	-- 3. Substring match on main category
	for id, cat in pairs(Categories.categoryTable or {}) do
		local catName = cat.name and cat.name:lower() or ""
		if catName ~= "" and (catName:find(target, 1, true) or target:find(catName, 1, true)) then
			return id, cat, nil
		end
	end

	-- 4. Substring match on subcategory
	for id, cat in pairs(Categories.categoryTable or {}) do
		if cat.childs then
			for _, child in ipairs(cat.childs) do
				local childName = child.name and child.name:lower() or ""
				if childName ~= "" and (childName:find(target, 1, true) or target:find(childName, 1, true)) then
					return id, cat, child.name
				end
			end
		end
	end

	return nil, nil, nil
end

function Categories:selectCategoryByName(categoryName, subCategoryName)
	if not categoryName or categoryName == "" then
		return false
	end

	if not Categories.categoryTable or #Categories.categoryTable == 0 then
		Categories:setPendingCategory(categoryName, subCategoryName)
		return false
	end

	local id, cat, matchedChild = Categories:findCategory(subCategoryName or categoryName)
	if not cat and subCategoryName then
		id, cat, matchedChild = Categories:findCategory(categoryName)
	end

	if not cat or not id then
		return false
	end

	local treeItem = Categories.widgets[id]
	if not treeItem or treeItem:isDestroyed() or not treeItem.mainButton then
		Categories:setPendingCategory(categoryName, subCategoryName)
		return false
	end

	if cat.childs and #cat.childs > 0 then
		local targetChild = subCategoryName or matchedChild
		Categories:collapseAll(false)
		Categories:expandTreeItem(treeItem, cat, targetChild)
		local panel = treeItem:getChildById('panel')
		if panel then
			for _, childBtn in pairs(panel:getChildren()) do
				if childBtn and not childBtn:isDestroyed() then
					local textWidget = childBtn:getChildById('text')
					local btnText = textWidget and textWidget:getText() or ""
					if not targetChild or btnText:lower() == tostring(targetChild):lower() then
						if childBtn.onClick then
							childBtn.onClick()
						end
						return true
					end
				end
			end
		end
	else
		Categories:onSelectCategory(treeItem.mainButton)
	end

	return true
end

function Categories:setPendingCategory(category, subCategory)
	Categories.pendingCategory = {
		category = category,
		subCategory = subCategory
	}
end

function Categories:clearPendingCategory()
	Categories.pendingCategory = nil
end

function Categories:setupSearch(disabled)
	Categories.categoryTable[#Categories.categoryTable].disabled = disabled
	local searchWidget = Categories.widgets[#Categories.categoryTable]
	if searchWidget and not searchWidget:isDestroyed() then
		searchWidget:setVisible(not disabled)
	end
end

function Categories:reset()
	Categories:cancelRender()
	for _, treeItem in pairs(Categories.widgets or {}) do
		if treeItem and not treeItem:isDestroyed() and g_effects then
			g_effects.cancelValue(treeItem)
		end
	end
	Categories.signature = nil
	Categories.widgets = {}
	Categories.selectButton = nil
	Categories.selectTreeItem = nil
	Categories.name = ''
	Categories.pendingCategory = nil
end
