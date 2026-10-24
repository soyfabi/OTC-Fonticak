local PodiumWindow
local sexRadio
local optionsRadio
local colorBoxGroup
local colorModeGroup
local currentColorBox
local showOutfitCheck
local showMountCheck
local showAuraCheck
local showPodiumCheck
local addon1Check
local addon2Check
local femaleButton
local maleButton
local showFloorCheck
local CATEGORY_NORMAL = 0
local CATEGORY_CUSTOM = 1
local CATEGORY_BATTLEPASS = 2
local currentOutfitCategory = CATEGORY_NORMAL
local outfitCheck
local mountCheck
local presetCheck
local auraCheck
local podiumItem
local podiumItemWidget
local podiumCreaturePreview
local podiumData

local PREVIEW_CREATURE_MARGIN_TOP = -30
local PREVIEW_CREATURE_MARGIN_LEFT = -50

local function applyPodiumCreaturePreview(spriteWidget)
	if not spriteWidget then
		return
	end

	if spriteWidget.setCenter then
		spriteWidget:setCenter(true)
	end
	if spriteWidget.setCreatureSize then
		spriteWidget:setCreatureSize(64)
	end
	if spriteWidget.setAnimate then
		spriteWidget:setAnimate(false)
	end
	if spriteWidget.setIdleAnimate then
		spriteWidget:setIdleAnimate(false)
	end

	spriteWidget:setMarginTop(PREVIEW_CREATURE_MARGIN_TOP)
	spriteWidget:setMarginLeft(PREVIEW_CREATURE_MARGIN_LEFT)
end

local function callIf(item, method, ...)
	if item and item[method] then
		item[method](item, ...)
	end
end

local function syncPodiumPreviewWidgets()
	if not podiumItem or not showOutfitCheck then
		return
	end

	local outfit = podiumItem:getOutfit() or {}
	local showOutfit = showOutfitCheck:isChecked() and (outfit.type or 0) > 0

	if podiumCreaturePreview then
		if showOutfit then
			podiumCreaturePreview:setVisible(true)
			podiumCreaturePreview:setOutfit(outfit)
			applyPodiumCreaturePreview(podiumCreaturePreview)
			if podiumItem and podiumItem.getPodiumDir then
				podiumCreaturePreview:setDirection(podiumItem:getPodiumDir())
			end
		else
			podiumCreaturePreview:setVisible(false)
		end
	end

	if podiumItemWidget and showPodiumCheck then
		podiumItemWidget:setVisible(showPodiumCheck:isChecked())
	end

	local familiar = PodiumWindow and PodiumWindow:recursiveGetChildById('familiar')
	if familiar and showAuraCheck then
		familiar:setVisible(showAuraCheck:isChecked() and showOutfit)
	end
end
local availableOutfits = {}
local availableMounts = {}
local availableAuras = {}
local categoryNames = {
	[CATEGORY_NORMAL] = "defaultCategories",
	[CATEGORY_CUSTOM] = "customCategories",
	[CATEGORY_BATTLEPASS] = "battlepassCategories"
}

function init()
	PodiumWindow = g_ui.displayUI("podiumwindow")

	PodiumWindow:hide()
	podiumItemWidget = PodiumWindow:recursiveGetChildById("podiumItem")
	podiumCreaturePreview = PodiumWindow:recursiveGetChildById("podiumCreature")
	applyPodiumCreaturePreview(podiumCreaturePreview)

	sexRadio = UIRadioGroup.create()
	femaleButton = PodiumWindow:recursiveGetChildById("femaleButton")
	maleButton = PodiumWindow:recursiveGetChildById("maleButton")

	sexRadio:addWidget(femaleButton)
	sexRadio:addWidget(maleButton)
	sexRadio:selectWidget(maleButton, true)

	function sexRadio.onSelectionChange(widget, selected)
		changeOutfitSex(selected)
	end

	optionsRadio = UIRadioGroup.create()
	outfitCheck = PodiumWindow:recursiveGetChildById("outfitCheck")
	mountCheck = PodiumWindow:recursiveGetChildById("mountCheck")
	auraCheck = PodiumWindow:recursiveGetChildById("auraCheck")
	presetCheck = PodiumWindow:recursiveGetChildById("presetCheck")

	optionsRadio:addWidget(outfitCheck)
	optionsRadio:addWidget(mountCheck)
	optionsRadio:addWidget(auraCheck)
	optionsRadio:addWidget(presetCheck)
	optionsRadio:selectWidget(outfitCheck, true)

	function optionsRadio.onSelectionChange(widget, selected)
		onChangeOptions(selected)
	end

	colorBoxGroup = UIRadioGroup.create()

	for j = 0, 6 do
		for i = 0, 18 do
			local colorBox = g_ui.createWidget("ColorBox", PodiumWindow:recursiveGetChildById("panelcolor"))
			local outfitColor = getOutfitColor(j * 19 + i)

			colorBox:setBackgroundColor(outfitColor)
			colorBox:setId("colorBox" .. j * 19 + i)

			colorBox.colorId = j * 19 + i

			colorBoxGroup:addWidget(colorBox)
		end
	end

	colorBoxGroup.onSelectionChange = onColorCheckChange
	colorModeGroup = UIRadioGroup.create()

	local headButton = PodiumWindow:recursiveGetChildById("HeadButton")
	local primaryButton = PodiumWindow:recursiveGetChildById("PrimaryButton")
	local secondaryButton = PodiumWindow:recursiveGetChildById("SecondaryButton")
	local detailButton = PodiumWindow:recursiveGetChildById("DetailButton")

	colorModeGroup:addWidget(headButton)
	colorModeGroup:addWidget(primaryButton)
	colorModeGroup:addWidget(secondaryButton)
	colorModeGroup:addWidget(detailButton)

	colorModeGroup.onSelectionChange = onColorModeChange

	colorModeGroup:selectWidget(headButton, true)

	showFloorCheck = PodiumWindow:recursiveGetChildById("showfloorCheck")
	showOutfitCheck = PodiumWindow:recursiveGetChildById("showOutfitCheck")
	showMountCheck = PodiumWindow:recursiveGetChildById("mountedCheck")
	showAuraCheck = PodiumWindow:recursiveGetChildById("showAuraCheck")
	showPodiumCheck = PodiumWindow:recursiveGetChildById("podiumCheck")
	addon1Check = PodiumWindow:recursiveGetChildById("addon1Check")
	addon2Check = PodiumWindow:recursiveGetChildById("addon2Check")

	connect(g_game, {
		onOpenPodiumWindow = onOpenPodiumWindow,
		onGameEnd = close
	})
end

function terminate()
	PodiumWindow:hide()
	disconnect(g_game, {
		onOpenPodiumWindow = onOpenPodiumWindow,
		onGameEnd = close
	})
end

function show()
	PodiumWindow:show()
end

function close()
	PodiumWindow:hide()
	if g_client and g_client.setInputLockWidget then
		g_client.setInputLockWidget(nil)
	end
end

function requestPodiumOutfitData(item)
	g_game.requestPodiumData(item)
end

function getPodiumSendContext()
	return podiumData
end

function setMenuCheck(categoryName)
	PodiumWindow:recursiveGetChildById("defaultCategories"):setChecked(categoryName == "defaultCategories")
	PodiumWindow:recursiveGetChildById("customCategories"):setChecked(categoryName == "customCategories")
	PodiumWindow:recursiveGetChildById("battlepassCategories"):setChecked(categoryName == "battlepassCategories")
end

function loadMenu(category)
	if not outfitCheck:isChecked() and not mountCheck:isChecked() then
		return
	end

	setMenuCheck(category)

	if category == "defaultCategories" then
		currentOutfitCategory = CATEGORY_NORMAL
	elseif category == "customCategories" then
		currentOutfitCategory = CATEGORY_CUSTOM
	elseif category == "battlepassCategories" then
		currentOutfitCategory = CATEGORY_BATTLEPASS
	end

	if outfitCheck:isChecked() then
		onShowPodiumOutfits(false)
	elseif mountCheck:isChecked() then
		onShowPodiumMounts()
	end
end

function onOpenPodiumWindow(outfit, outfitList, mountList, data, maleOutfits, femaleOutfits, auraList)
	if not PodiumWindow:isVisible() then
		show()
		PodiumWindow:focus()
		if g_client and g_client.setInputLockWidget then
			g_client.setInputLockWidget(PodiumWindow)
		end
	end

	availableOutfits = {}
	podiumData = data

	local femaleOutfitMap = {}

	for index, outfitId in pairs(femaleOutfits) do
		femaleOutfitMap[outfitId] = index
	end

	local maleOutfitMap = {}

	for index, outfitId in pairs(maleOutfits) do
		maleOutfitMap[outfitId] = index
	end

	for _, outfitData in pairs(outfitList) do
		if outfitData[4] > 0 then
			-- block empty
		else
			local outfitName = outfitData[2]
			local outfitId = outfitData[1]
			local addons = outfitData[3]
			local outfitCategory = outfitData[5]

			if outfitId == outfit.type then
				currentOutfitCategory = outfitCategory
			end

			if maleOutfitMap[outfitId] then
				local femaleId = femaleOutfits[maleOutfitMap[outfitId]]

				table.insert(availableOutfits, {
					name = outfitName,
					male = outfitId,
					female = femaleId,
					addons = addons,
					category = outfitCategory
				})
			elseif femaleOutfitMap[outfitId] then
				local maleId = maleOutfits[femaleOutfitMap[outfitId]]

				table.insert(availableOutfits, {
					name = outfitName,
					male = maleId,
					female = outfitId,
					addons = addons,
					category = outfitCategory
				})
			end
		end
	end

	availableMounts = mountList
	availableAuras = auraList

	local itemWidget = PodiumWindow:recursiveGetChildById("podiumItem")

	itemWidget:setItemId(podiumData.itemId)

	podiumItem = itemWidget:getItem()

	if podiumItem.setPodiumDirection then
		podiumItem:setPodiumDirection(podiumData.direction or 2)
	end
	if podiumItem.setOutfit then
		podiumItem:setOutfit(outfit)
	end
	podiumItem.cachedOutfitId = outfit.type
	if data.showCreature ~= nil and showOutfitCheck then
		showOutfitCheck:setChecked(data.showCreature)
	end
	if data.showPlatform ~= nil and showPodiumCheck then
		showPodiumCheck:setChecked(data.showPlatform)
	end
	PodiumWindow:recursiveGetChildById("searchfilter"):clearText(true)
	onShowPodiumOutfits(true)
	loadMenu(categoryNames[currentOutfitCategory])
	syncPodiumPreviewWidgets()
end

function onShowPodiumOutfits(startup, searchText)
	local typeList = PodiumWindow.ScrollBar.selectionList
	local currentItemOutfit = podiumItem:getOutfit()

	typeList:destroyChildren()

	typeList.onChildFocusChange = nil

	sexRadio:selectWidget(maleButton)

	local currentOutfitChild
	local selectFemale = false

	for _, outfitInfo in pairs(availableOutfits) do
		local outfitCategory = outfitInfo.category

		if currentItemOutfit.type == outfitInfo.female then
			selectFemale = true
		end

		if outfitCategory ~= currentOutfitCategory then
			-- block empty
		elseif searchText and not string.empty(searchText) and not matchText(searchText, outfitInfo.name) then
			-- block empty
		else
			local button = g_ui.createWidget("SelectionButton", typeList)

			button.outfit:setOutfit({
				type = outfitInfo.male,
				head = currentItemOutfit.head,
				body = currentItemOutfit.body,
				legs = currentItemOutfit.legs,
				feet = currentItemOutfit.feet,
				addons = outfitInfo.addons
			})
			button.name:setText(outfitInfo.name)

			button.outfitInfo = outfitInfo

			if currentItemOutfit.type == outfitInfo.male or currentItemOutfit.type == outfitInfo.female then
				currentOutfitChild = button
			end
		end
	end

	local mountLabel = PodiumWindow:recursiveGetChildById("mountName")

	if #availableMounts > 0 then
		if podiumData.mounted then
			for _, data in pairs(availableMounts) do
				if currentItemOutfit.mount == data[1] then
					mountLabel:setText(data[2])

					podiumItem.cachedMountId = currentItemOutfit.mount
					podiumItem.cachedOutfitId = currentItemOutfit.type

					break
				end
			end
		else
			mountLabel:setText(availableMounts[1][2])
		end
	end

	if startup then
		optionsRadio:selectWidget(PodiumWindow:recursiveGetChildById("outfitCheck"))
		local showCreature = podiumData.showCreature
		if showCreature == nil then
			showCreature = podiumData.showOutfit
		end
		showOutfitCheck:setChecked(showCreature ~= false, false)
		showMountCheck:setChecked(podiumData.mounted == true, false)
		showAuraCheck:setChecked(currentItemOutfit.aura, false)
		local showPlatform = podiumData.showPlatform
		if showPlatform == nil then
			showPlatform = podiumData.showPodium
		end
		showPodiumCheck:setChecked(showPlatform ~= false, false)
		showFloorCheck:setChecked(true)

		local addons = currentItemOutfit.addons

		if addons == 3 then
			addon1Check:setChecked(true)
			addon2Check:setChecked(true)
		elseif addons == 2 then
			addon1Check:setChecked(false)
			addon2Check:setChecked(true)
		elseif addons == 1 then
			addon1Check:setChecked(true)
			addon2Check:setChecked(false)
		else
			addon1Check:setChecked(false)
			addon2Check:setChecked(false)
		end
	end

	if selectFemale then
		sexRadio:selectWidget(femaleButton)
	end

	local targetFocus = currentOutfitChild == nil and typeList:getFirstChild() or currentOutfitChild

	typeList.onChildFocusChange = onOutfitFocusChange

	typeList:focusChild(nil)
	typeList:focusChild(targetFocus)
	typeList:ensureChildVisible(targetFocus)
	colorModeGroup:selectWidget(nil)
	colorModeGroup:selectWidget(PodiumWindow:recursiveGetChildById("HeadButton"))
end

function onShowPodiumMounts(searchText)
	if not podiumItem then
		return
	end

	local typeList = PodiumWindow.ScrollBar.selectionList
	local currentOutfit = podiumItem:getOutfit()

	typeList:destroyChildren()
	typeList:updateScrollBars()

	typeList.onChildFocusChange = nil

	local currentMountChild

	for _, mountInfo in pairs(availableMounts) do
		if searchText and not string.empty(searchText) and not matchText(searchText, mountInfo[2]) then
			-- block empty
		elseif mountInfo[4] ~= currentOutfitCategory then
			-- block empty
		else
			local button = g_ui.createWidget("SelectionButton", typeList)

			button.outfit:setOutfit({
				type = mountInfo[1]
			})
			button.name:setText(mountInfo[2])

			button.mountInfo = mountInfo

			if currentOutfit.mount == mountInfo[1] then
				currentMountChild = button
			end
		end
	end

	typeList.onChildFocusChange = onMountFocusChange

	typeList:focusChild(nil)
	typeList:focusChild(currentMountChild and currentMountChild or typeList:getFirstChild())
end

function onShowPodiumAuras(searchText)
	if not podiumItem then
		return
	end

	local typeList = PodiumWindow.ScrollBar.selectionList
	local currentOutfit = podiumItem:getOutfit()

	typeList:destroyChildren()
	typeList:updateScrollBars()

	typeList.onChildFocusChange = nil

	local currentAuraChild

	for _, auraInfo in pairs(availableAuras) do
		if searchText and not string.empty(searchText) and not matchText(searchText, auraInfo[4]) then
			-- block empty
		else
			local button = g_ui.createWidget("SelectionButton", typeList)
			local outfit = table.copy(currentOutfit)

			outfit.aura = auraInfo[3]
			outfit.auraCategory = auraInfo[2]

			button.outfit:setOutfit(outfit)
			button.name:setText(auraInfo[4])

			button.auraInfo = auraInfo

			if currentOutfit.aura == auraInfo[3] then
				currentAuraChild = button
			end
		end
	end

	typeList.onChildFocusChange = onAuraFocusChange

	typeList:focusChild(nil)
	typeList:focusChild(currentAuraChild and currentAuraChild or typeList:getFirstChild())
end

function changeOutfitSex(selected)
	local typeList = PodiumWindow.ScrollBar.selectionList

	for i, widget in pairs(typeList:getChildren()) do
		local currentOutfit = widget.outfit:getOutfit()

		currentOutfit.type = selected:getId() == "maleButton" and widget.outfitInfo.male or widget.outfitInfo.female

		widget.outfit:setOutfit(currentOutfit)
		widget.name:setText(widget.outfitInfo.name)
	end

	local currentItemOutfit = podiumItem:getOutfit()

	for _, outfitInfo in pairs(availableOutfits) do
		if currentItemOutfit.type == outfitInfo.female or currentItemOutfit.type == outfitInfo.male then
			local outfitSex = selected:getId() == "maleButton" and outfitInfo.male or outfitInfo.female

			podiumItem:setOutfit({
				type = outfitSex,
				head = currentItemOutfit.head,
				body = currentItemOutfit.body,
				legs = currentItemOutfit.legs,
				feet = currentItemOutfit.feet,
				addons = outfitInfo.addons
			})
			onUpdatePreview(podiumItem:getOutfit())
		end
	end
end

function onUpdatePreview(newOutfit)
	if not podiumItem then
		return
	end

	if newOutfit then
		podiumItem:setOutfit(newOutfit)
	end

	callIf(podiumItem, "setOutfitVisible", showOutfitCheck:isChecked())
	callIf(podiumItem, "setMountVisible", showMountCheck:isChecked())
	callIf(podiumItem, "setAuraVisible", showAuraCheck:isChecked())
	callIf(podiumItem, "setPodiumVisible", showPodiumCheck:isChecked())
	syncPodiumPreviewWidgets()

	if newOutfit and newOutfit.type > 0 then
		podiumItem.cachedOutfitId = newOutfit.type
	end
end

function onOutfitFocusChange(list, focused)
	if not focused or not podiumItem then
		return
	end

	local outfitInfo = focused.outfitInfo

	PodiumWindow:recursiveGetChildById("outfitName"):setText(outfitInfo.name)

	local outfitLabel = outfitInfo.addons

	addon1Check:setEnabled(outfitLabel >= 1)
	addon2Check:setEnabled(outfitLabel >= 2)

	local addons = table.copy(focused.outfit:getOutfit())

	if addons then
		if addon1Check:isChecked() and addon2Check:isChecked() and outfitLabel == 3 then
			addons.addons = 3
		elseif addon2Check:isChecked() and outfitLabel > 1 then
			addons.addons = 2
		elseif addon1Check:isChecked() and outfitLabel > 0 then
			addons.addons = 1
		else
			addons.addons = 0
		end

		if podiumItem:getOutfit().mount > 0 then
			addons.mount = podiumItem:getOutfit().mount
		end

		addons.aura = podiumItem:getOutfit().aura
		addons.auraCategory = podiumItem:getOutfit().auraCategory

		onUpdatePreview(addons)
	end
end

function onMountFocusChange(list, focused)
	if not focused or not podiumItem then
		return true
	end

	local tmpOutfit = podiumItem:getOutfit()

	PodiumWindow:recursiveGetChildById("mountName"):setText(focused.mountInfo[2])

	if showMountCheck:isChecked() and not showOutfitCheck:isChecked() then
		tmpOutfit.type = focused.mountInfo[1]
	elseif showMountCheck:isChecked() and showOutfitCheck:isChecked() then
		tmpOutfit.mount = focused.mountInfo[1]
	end

	podiumItem:setOutfit(tmpOutfit)
	callIf(podiumItem, "setOutfitVisible", true)
	syncPodiumPreviewWidgets()

	podiumItem.cachedMountId = focused.mountInfo[1]
end

function onAuraFocusChange(list, focused)
	if not focused or not podiumItem then
		return true
	end

	local tmpOutfit = podiumItem:getOutfit()

	PodiumWindow:recursiveGetChildById("auraName"):setText(focused.auraInfo[4])

	if showAuraCheck:isChecked() then
		tmpOutfit.aura = focused.auraInfo[3]
		tmpOutfit.auraCategory = focused.auraInfo[2]

		if showMountCheck:isChecked() then
			showMountCheck:setChecked(false)
		end
	end

	podiumItem:setOutfit(tmpOutfit)
	callIf(podiumItem, "setOutfitVisible", showAuraCheck:isChecked() and showOutfitCheck:isChecked())
	syncPodiumPreviewWidgets()

	podiumItem.cachedAuraId = focused.auraInfo[1]
	podiumItem.cachedAuraCid = focused.auraInfo[3]
	podiumItem.cachedAuraCat = focused.auraInfo[2]
end

function onChangeOptions(focused)
	local grayHover = PodiumWindow:recursiveGetChildById("grayHover")

	if focused:getId() == "outfitCheck" then
		onShowPodiumOutfits(false)
		grayHover:setVisible(false)
		femaleButton:setVisible(true)
		maleButton:setVisible(true)
	elseif focused:getId() == "mountCheck" then
		onShowPodiumMounts()
		grayHover:setVisible(true)
		femaleButton:setVisible(false)
		maleButton:setVisible(false)
	elseif focused:getId() == "presetCheck" then
		-- block empty
	elseif focused:getId() == "auraCheck" then
		onShowPodiumAuras()
		grayHover:setVisible(true)
		femaleButton:setVisible(false)
		maleButton:setVisible(false)
	end
end

function onVisibleOutfit(state)
	if not podiumItem then
		return
	end

	if not showMountCheck:isChecked() then
		callIf(podiumItem, "setOutfitVisible", state)
		syncPodiumPreviewWidgets()

		return
	end

	callIf(podiumItem, "setOutfitVisible", true)

	local tmpOutfit = podiumItem:getOutfit()

	tmpOutfit.type = state and podiumItem.cachedOutfitId or tmpOutfit.mount
	tmpOutfit.mount = state and podiumItem.cachedMountId or 0

	podiumItem:setOutfit(tmpOutfit)
	syncPodiumPreviewWidgets()
end

function onVisibleMount(state)
	if not podiumItem then
		return
	end

	local typeList = PodiumWindow.ScrollBar.selectionList:getFocusedChild()

	if not typeList then
		return
	end

	callIf(podiumItem, "setMountVisible", state)
	syncPodiumPreviewWidgets()

	podiumData.mounted = state

	if optionsRadio:getSelectedWidget():getId() ~= "mountCheck" then
		local focusedWidget = podiumItem:getOutfit()

		focusedWidget.mount = state and podiumItem.cachedMountId or 0

		if focusedWidget.mount > 0 then
			podiumItem.cachedMountId = focusedWidget.mount
		end

		podiumItem:setOutfit(focusedWidget)

		return
	end

	local tmpOutfit = podiumItem:getOutfit()

	if showOutfitCheck:isChecked() then
		tmpOutfit.mount = state and typeList.mountInfo[1] or 0
		podiumItem.cachedMountId = tmpOutfit.mount
	else
		podiumItem.cachedOutfitId = tmpOutfit.type
		tmpOutfit.type = state and typeList.mountInfo[1] or 0
	end

	podiumItem:setOutfit(tmpOutfit)
end

function onVisibleFloor(state)
	local widget = PodiumWindow:recursiveGetChildById("previewoutfit")

	if not widget then
		return
	end

	widget:setImageSource(state and "/images/game/outfit_ground" or "")
end

function onAuraButton(state)
	if not podiumItem then
		return
	end

	callIf(podiumItem, "setAuraVisible", state)
	syncPodiumPreviewWidgets()
end

function onAddon1Button(state)
	if not podiumItem then
		return
	end

	local tmpOutfit = podiumItem:getOutfit()
	applyAddonChecksToOutfit(tmpOutfit, getFocusedOutfitAddonCap())
	podiumItem:setOutfit(tmpOutfit)
	syncPodiumPreviewWidgets()
end

function onAddon2Button(state)
	if not podiumItem then
		return
	end

	local tmpOutfit = podiumItem:getOutfit()
	applyAddonChecksToOutfit(tmpOutfit, getFocusedOutfitAddonCap())
	podiumItem:setOutfit(tmpOutfit)
	syncPodiumPreviewWidgets()
end

function rotatePreview(isRight)
	if not podiumItem then
		return true
	end

	local currentDirection = podiumItem:getPodiumDir()

	if isRight then
		if currentDirection == 0 then
			podiumItem:setPodiumDirection(3)
		else
			podiumItem:setPodiumDirection(currentDirection - 1)
		end
	elseif currentDirection >= 3 then
		podiumItem:setPodiumDirection(0)
	else
		podiumItem:setPodiumDirection(currentDirection + 1)
	end

	syncPodiumPreviewWidgets()
end

local function getAppearancePanel()
	return PodiumWindow and PodiumWindow:recursiveGetChildById("appearance")
end

local function getColorBoxWidget(colorId)
	if not PodiumWindow then
		return nil
	end
	return PodiumWindow:recursiveGetChildById("colorBox" .. (colorId or 0))
end

function onColorModeChange(widget, selectedWidget)
	if not podiumItem or not selectedWidget then
		return
	end

	local colorMode = selectedWidget:getId()
	local tmpOutfit = podiumItem:getOutfit()

	local appearance = getAppearancePanel()
	local mountMode = appearance and optionsRadio:getSelectedWidget() == appearance:getChildById("mountCheck")

	if colorMode == "HeadButton" then
		selectedWidget:getParent():setImageClip("0 0 253 18")
		colorBoxGroup:selectWidget(getColorBoxWidget(mountMode and tmpOutfit.mountHead or tmpOutfit.head))
	elseif colorMode == "PrimaryButton" then
		selectedWidget:getParent():setImageClip("0 18 253 18")
		colorBoxGroup:selectWidget(getColorBoxWidget(mountMode and tmpOutfit.mountBody or tmpOutfit.body))
	elseif colorMode == "SecondaryButton" then
		selectedWidget:getParent():setImageClip("0 36 253 18")
		colorBoxGroup:selectWidget(getColorBoxWidget(mountMode and tmpOutfit.mountLegs or tmpOutfit.legs))
	elseif colorMode == "DetailButton" then
		selectedWidget:getParent():setImageClip("0 54 253 18")
		colorBoxGroup:selectWidget(getColorBoxWidget(mountMode and tmpOutfit.mountFeet or tmpOutfit.feet))
	end
end

function onColorCheckChange(widget, selectedWidget)
	local colorId = selectedWidget.colorId
	local colorMode = colorModeGroup:getSelectedWidget():getId()

	if currentColorBox then
		currentColorBox:setBorderWidth(0)
		currentColorBox:setBorderColor("alpha")
		currentColorBox:setChecked(false)
	end

	selectedWidget:setBorderWidth(1)
	selectedWidget:setBorderColor("white")

	currentColorBox = selectedWidget

	if not podiumItem then
		return
	end

	local tmpOutfit = podiumItem:getOutfit()

	local appearance = getAppearancePanel()
	local mountMode = appearance and optionsRadio:getSelectedWidget() == appearance:getChildById("mountCheck")

	if colorMode == "HeadButton" then
		if mountMode then
			tmpOutfit.mountHead = colorId
		else
			tmpOutfit.head = colorId
		end
	elseif colorMode == "PrimaryButton" then
		if mountMode then
			tmpOutfit.mountBody = colorId
		else
			tmpOutfit.body = colorId
		end
	elseif colorMode == "SecondaryButton" then
		if mountMode then
			tmpOutfit.mountLegs = colorId
		else
			tmpOutfit.legs = colorId
		end
	elseif colorMode == "DetailButton" then
		if mountMode then
			tmpOutfit.mountFeet = colorId
		else
			tmpOutfit.feet = colorId
		end
	end

	podiumItem:setOutfit(tmpOutfit)
	syncPodiumPreviewWidgets()

	local typeList = PodiumWindow.ScrollBar.selectionList

	for i, widget in pairs(typeList:getChildren()) do
		local widgetOutfit = widget.outfit:getOutfit()

		widgetOutfit.mountHead = tmpOutfit.mountHead
		widgetOutfit.mountBody = tmpOutfit.mountBody
		widgetOutfit.mountLegs = tmpOutfit.mountLegs
		widgetOutfit.mountFeet = tmpOutfit.mountFeet
		widgetOutfit.head = tmpOutfit.head
		widgetOutfit.body = tmpOutfit.body
		widgetOutfit.legs = tmpOutfit.legs
		widgetOutfit.feet = tmpOutfit.feet

		widget.outfit:setOutfit(widgetOutfit)
	end
end

local function resolvePodiumSendAddons(outfitLabel)
	if not addon1Check or not addon2Check then
		return 0
	end

	outfitLabel = outfitLabel or 0
	local addon1 = addon1Check:isChecked() and outfitLabel >= 1
	local addon2 = addon2Check:isChecked() and outfitLabel >= 2
	if addon1 and addon2 then
		return 3
	end
	if addon2 then
		return 2
	end
	if addon1 then
		return 1
	end
	return 0
end

local function applyAddonChecksToOutfit(tmpOutfit, outfitLabel)
	tmpOutfit.addons = resolvePodiumSendAddons(outfitLabel)
	return tmpOutfit
end

local function getFocusedOutfitAddonCap()
	local typeList = PodiumWindow and PodiumWindow.ScrollBar and PodiumWindow.ScrollBar.selectionList
	if not typeList then
		return 0
	end
	local focused = typeList:getFocusedChild()
	if focused and focused.outfitInfo then
		return focused.outfitInfo.addons or 0
	end
	return resolvePodiumOutfitLabel((podiumItem and podiumItem:getOutfit() or {}).type)
end

local function resolvePodiumOutfitLabel(lookType)
	if not lookType or lookType <= 0 then
		return 0
	end

	for _, outfitInfo in pairs(availableOutfits or {}) do
		if lookType == outfitInfo.male or lookType == outfitInfo.female then
			return outfitInfo.addons or 0
		end
	end
	return 0
end

function onChoosePodiumOutfit()
	if not podiumItem or not podiumData then
		return
	end

	local outfit = table.copy(podiumItem:getOutfit() or {})
	local showOutfit = showOutfitCheck:isChecked()
	local lookType = showOutfit and (podiumItem.cachedOutfitId or outfit.type or 0) or 0

	if showOutfit and lookType <= 0 then
		g_logger.warning("Renown podium: select an outfit before confirming.")
		return
	end

	outfit.type = lookType
	outfit.addons = resolvePodiumSendAddons(resolvePodiumOutfitLabel(lookType))
	outfit.mount = showMountCheck:isChecked() and (podiumItem.cachedMountId or outfit.mount or 0) or 0

	if not showAuraCheck:isChecked() then
		outfit.auraId = 0
		outfit.aura = 0
	else
		outfit.auraId = podiumItem.cachedAuraId
		outfit.auraCategory = podiumItem.cachedAuraCat
		outfit.aura = podiumItem.cachedAuraCid
	end

	local pos = podiumData.position or podiumData.pos
	local itemId = podiumData.itemId or podiumData.itemClientId
	local stackPos = podiumData.stackpos or podiumData.stackPos or 0
	local direction = podiumItem.getPodiumDir and podiumItem:getPodiumDir() or podiumData.direction or 2
	local showPodium = showPodiumCheck:isChecked()

	if not pos or pos.x == 65535 then
		g_logger.warning("Renown podium: invalid podium position; cannot save.")
		return
	end

	if g_game.changeOutfitPodium then
		g_game.changeOutfitPodium(outfit, pos, itemId, stackPos, direction, showPodium, showOutfit)
	elseif g_game.sendPlayerPodiumOutfit then
		g_game.sendPlayerPodiumOutfit(lookType, outfit.head or 0, outfit.body or 0, outfit.legs or 0, outfit.feet or 0,
			outfit.addons or 0, outfit.mount or 0, pos, itemId or 0, stackPos, direction, showPodium, showOutfit)
	end
	close()
end

function onFilterSearch(widget)
	if outfitCheck:isChecked() then
		onShowPodiumOutfits(false, widget:getText())
	elseif mountCheck:isChecked() then
		onShowPodiumMounts(widget:getText())
	end
end
