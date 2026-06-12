local OPCODE_STORE_TRANSFER = 0xF8
local OPCODE_STORE_HISTORY = 0xFA
local OPCODE_STORE_OPEN = 0xFB
local OPCODE_STORE_BUY = 0xFC
local OPCODE_STORE_SEND = 0xFD

local DONATION_URL = "https://xangelserver.com/donate.php"

local RESP_ERROR = 0x00
local RESP_CATALOG = 0x01
local RESP_SUCCESS = 0x02
local RESP_HISTORY = 0x03

local CATEGORY_NONE = -1
local CATEGORY_PREMIUM = 0
local CATEGORY_ITEM = 1
local CATEGORY_BLESSING = 2
local CATEGORY_OUTFIT = 3
local CATEGORY_MOUNT = 4

local categoryIconClips = {
  store_equipment = 1,
  store_weapons = 1,
  store_potions = 10,
  store_consumables = 6,
  store_backpacks = 6,
  store_blessings = 8,
  store_mounts = 14,
  store_outfits = 15,
  store_premium = 20,
  store_cosmetics = 21,
  store_extras = 9,
  store_services = 7,
  store_prey = 9
}

local categories = {}
local offers = {}
local history = {}

local gameStoreWindow = nil
local gameStoreButton = nil
local transferWindow = nil
local changeNameWindow = nil
local selected = nil
local selectedOffer = nil
local msgWindow = nil
local pendingBuyOffer = nil

local premiumPoints = 0
local searchResultCategoryId = "Search Results"
local entriesPerPage = 26
local currentPage = 1
local totalPages = 1

local function trim(value)
  return (value or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function getCategoryId(name, icon)
  name = (name or ""):lower()
  icon = (icon or ""):lower()

  if name:find("premium", 1, true) or icon:find("premium", 1, true) then
    return CATEGORY_PREMIUM
  elseif name:find("bless", 1, true) or icon:find("bless", 1, true) then
    return CATEGORY_BLESSING
  elseif name:find("outfit", 1, true) or icon:find("outfit", 1, true) then
    return CATEGORY_OUTFIT
  elseif name:find("mount", 1, true) or icon:find("mount", 1, true) then
    return CATEGORY_MOUNT
  elseif name:find("extra", 1, true) or name:find("service", 1, true) then
    return CATEGORY_NONE
  elseif name:find("cosmetic", 1, true) or name:find("consumable", 1, true) then
    return CATEGORY_NONE
  end

  return CATEGORY_ITEM
end

local function getStoreImage(icon)
  if not icon or icon == "" then
    return nil
  end

  local source = "/images/store/" .. icon
  if g_resources.fileExists(source .. ".png") then
    return source
  end

  source = "/images/game/prey/" .. icon
  if g_resources.fileExists(source .. ".png") then
    return source
  end

  return nil
end

local function setOfferVisual(imagePanel, offer)
  local image = imagePanel:getChildById("image")
  local item = imagePanel:getChildById("item")
  local outfit = imagePanel:getChildById("outfit")
  local mount = imagePanel:getChildById("mount")

  image:hide()
  item:hide()
  outfit:hide()
  mount:hide()

  local imageSource = getStoreImage(offer.icon)
  if imageSource then
    image:setImageSource(imageSource)
    image:show()
    return
  end

  if offer.categoryId == CATEGORY_OUTFIT then
    local outfitData = { type = offer.id }
    local player = g_game.getLocalPlayer()
    if player then
      outfitData = player:getOutfit()
      outfitData.type = offer.id
    end
    outfit:setOutfit(outfitData)
    outfit:show()
  elseif offer.categoryId == CATEGORY_MOUNT then
    mount:setOutfit({ type = offer.id })
    mount:show()
  elseif offer.id and offer.id > 0 then
    item:setItemId(offer.id)
    item:show()
  else
    local fallback = getStoreImage("mount")
    if fallback then
      image:setImageSource(fallback)
      image:show()
    end
  end
end

function init()
  connect(g_game, {
    onGameStart = create,
    onGameEnd = destroy
  })

  ProtocolGame.registerOpcode(OPCODE_STORE_SEND, onStoreMessage)

  if g_game.isOnline() then
    create()
  end
end

function terminate()
  disconnect(g_game, {
    onGameStart = create,
    onGameEnd = destroy
  })

  ProtocolGame.unregisterOpcode(OPCODE_STORE_SEND)
  destroy()
end

function create()
  if gameStoreWindow then
    return
  end

  gameStoreWindow = g_ui.displayUI("game_store")
  gameStoreWindow:hide()

  createTransferWindow()
  requestCatalog()
end

function destroy()
  if msgWindow then
    msgWindow:destroy()
    msgWindow = nil
  end



  if gameStoreWindow then
    gameStoreWindow:destroy()
    gameStoreWindow = nil
  end

  if transferWindow then
    transferWindow:destroy()
    transferWindow = nil
  end

  if changeNameWindow then
    changeNameWindow:destroy()
    changeNameWindow = nil
  end

  categories = {}
  offers = {}
  history = {}
  selected = nil
  selectedOffer = nil
  pendingBuyOffer = nil
end

local function ensureStoreWindow()
  if gameStoreWindow then
    return true
  end

  if not g_game.isOnline() then
    return false
  end

  create()
  return gameStoreWindow ~= nil
end

function requestCatalog()
  local protocolGame = g_game.getProtocolGame()
  if not protocolGame then
    return
  end

  local msg = OutputMessage.create()
  msg:addU8(OPCODE_STORE_OPEN)
  protocolGame:send(msg)
end

function requestHistory()
  local protocolGame = g_game.getProtocolGame()
  if not protocolGame then
    return
  end

  local msg = OutputMessage.create()
  msg:addU8(OPCODE_STORE_HISTORY)
  protocolGame:send(msg)
end

function requestBuy(offerId, newName)
  local protocolGame = g_game.getProtocolGame()
  if not protocolGame then
    return
  end

  local msg = OutputMessage.create()
  msg:addU8(OPCODE_STORE_BUY)
  msg:addU32(offerId)
  if newName then
    msg:addString(newName)
  end
  protocolGame:send(msg)
end

function requestTransfer(target, amount)
  local protocolGame = g_game.getProtocolGame()
  if not protocolGame then
    return
  end

  local msg = OutputMessage.create()
  msg:addU8(OPCODE_STORE_TRANSFER)
  msg:addString(target)
  msg:addU32(amount)
  protocolGame:send(msg)
end

function onStoreMessage(protocol, msg)
  local response = msg:getU8()
  if response == RESP_CATALOG then
    parseCatalog(msg)
  elseif response == RESP_SUCCESS then
    parseSuccess(msg)
  elseif response == RESP_HISTORY then
    parseHistory(msg)
  elseif response == RESP_ERROR then
    parseError(msg)
  end
end

function parseCatalog(msg)
  premiumPoints = msg:getU32()
  categories = {}
  offers = {}

  local categoriesList = gameStoreWindow:getChildById("categoriesList")
  categoriesList:destroyChildren()
  selected = nil
  selectedOffer = nil

  local categoriesCount = msg:getU16()
  for i = 1, categoriesCount do
    local categoryName = msg:getString()
    local categoryIcon = msg:getString()
    local parentName = msg:getString()
    local categoryDescription = msg:getString()
    if parentName == "" then
      parentName = nil
    end

    local category = {
      title = categoryName,
      parent = parentName,
      icon = categoryIcon,
      categoryId = getCategoryId(categoryName, categoryIcon),
      description = categoryDescription
    }

    categories[category.title] = category
    offers[category.title] = {}

    local offerCount = msg:getU16()
    for j = 1, offerCount do
      local offer = {
        offerId = msg:getU32(),
        name = msg:getString(),
        icon = msg:getString(),
        price = msg:getU32(),
        id = msg:getU16(),
        count = msg:getU16(),
        description = msg:getString(),
        oftype = msg:getString(),
        categoryId = category.categoryId
      }
      table.insert(offers[category.title], offer)
    end

    addCategory(category)
  end

  -- Banners da home (servidor #93) vêm após as categorias: u8 count +
  -- (string imagem, u8 action, u32 target) por banner + u8 delay. Sem
  -- consumir, os bytes sobram e viram opcode fantasma (0x01). Guard de
  -- getUnreadSize mantém compat com servidor antigo sem banners.
  if msg:getUnreadSize() > 0 then
    local bannerCount = msg:getU8()
    for i = 1, bannerCount do
      msg:getString() -- caminho da imagem
      msg:getU8() -- action
      msg:getU32() -- target (offer id)
    end
    if msg:getUnreadSize() > 0 then
      msg:getU8() -- delay de rotação dos banners
    end
  end

  onGameStoreUpdatePoints({ points = premiumPoints })

  local firstCategory = categoriesList:getFirstChild()
  if firstCategory then
    select(firstCategory:getChildById("button"))
  else
    local offersPanel = gameStoreWindow:getChildById("offers")
    offersPanel:getChildById("offersList"):destroyChildren()
    offersPanel:getChildById("offerDetails"):hide()
  end
end

function parseSuccess(msg)
  local offerId = msg:getU32()
  local text = msg:getString()
  local newCoins = msg:getU32()

  premiumPoints = newCoins
  onGameStoreUpdatePoints({ points = newCoins })
  updateSelectedOfferState()
  requestCatalog()
  requestHistory()

  if transferWindow then
    transferWindow:hide()
  end

  if msgWindow then
    msgWindow:destroy()
    msgWindow = nil
  end

  displayInfoBoxWithCallback("Store Information", text, function()
    show()
  end)
end

function parseHistory(msg)
  history = {}

  local count = msg:getU16()
  for i = 1, count do
    local date = msg:getString()
    local amount = msg:getU32()
    local positive = msg:getU8()
    local isSecondPrice = msg:getU8()
    local title = msg:getString()
    local itemCount = msg:getU16()

    table.insert(history, {
      date = date,
      price = positive == 1 and amount or -amount,
      isSecondPrice = isSecondPrice == 1,
      name = title,
      count = itemCount
    })
  end

  currentPage = 1
  totalPages = math.max(1, math.ceil(#history / entriesPerPage))
  updateHistory()
end

function parseError(msg)
  local text = msg:getString()

  if msgWindow then
    msgWindow:destroy()
    msgWindow = nil
  end

  displayInfoBoxWithCallback("Store Error", text, function()
    show()
  end)
end

function hideTransferWindow()
  if transferWindow then
    transferWindow:hide()
  end
end

function show()
  hideTransferWindow()
  if not ensureStoreWindow() then
    return
  end

  hideHistory()
  requestCatalog()
  gameStoreWindow:show()
  gameStoreWindow:raise()
  gameStoreWindow:focus()
end

function hide()
  hideTransferWindow()
  if gameStoreWindow then
    gameStoreWindow:hide()
  end
end

function toggle()
  if not ensureStoreWindow() then
    return
  end

  if gameStoreWindow:isVisible() then
    hide()
  else
    show()
  end
end

function showHistory()
  if not gameStoreWindow then
    return
  end

  deselect()
  gameStoreWindow:getChildById("offers"):hide()
  gameStoreWindow:getChildById("history"):show()
  requestHistory()
  updateHistory()
end

function hideHistory()
  if not gameStoreWindow then
    return
  end

  gameStoreWindow:getChildById("offers"):show()
  gameStoreWindow:getChildById("history"):hide()
end

function updateHistory()
  if not gameStoreWindow then
    return
  end

  local historyPanel = gameStoreWindow:getChildById("history")
  local historyList = historyPanel:getChildById("list")
  historyList:destroyChildren()

  local index = ((currentPage - 1) * entriesPerPage) + 1
  for i = index, math.min(#history, index + entriesPerPage - 1) do
    local widget = g_ui.createWidget("HistoryWidget", historyList)
    widget:getChildById("date"):setText(history[i].date)
    widget:getChildById("price"):setText((history[i].price > 0 and "+" or "") .. comma_value(history[i].price))
    widget:getChildById("price"):setOn(history[i].price > 0)
    widget:getChildById("coin"):setOn(history[i].isSecondPrice)

    if history[i].count > 1 then
      widget:getChildById("description"):setText(history[i].count .. "x " .. history[i].name)
    else
      widget:getChildById("description"):setText(history[i].name)
    end
  end

  historyPanel:getChildById("pageLabel"):setText("Page " .. currentPage .. "/" .. totalPages)
  historyPanel:getChildById("nextPageButton"):setVisible(currentPage < totalPages)
  historyPanel:getChildById("prevPageButton"):setVisible(currentPage > 1)
end

function prevPage()
  if currentPage == 1 then
    return true
  end

  currentPage = currentPage - 1
  updateHistory()
end

function nextPage()
  if currentPage == totalPages then
    return true
  end

  currentPage = currentPage + 1
  updateHistory()
end

function deselect()
  if not selected then
    return
  end

  local oldSelected = selected
  local button = oldSelected:getChildById("button")
  if button then
    button:setChecked(false)
  end

  local arrow = oldSelected:getChildById("selectArrow")
  if arrow then
    arrow:hide()
  end

  local subCategories = oldSelected:getChildById("subCategories")
  if subCategories then
    oldSelected:setHeight(22)
    subCategories:hide()

    local expandArrow = oldSelected:getChildById("expandArrow")
    if expandArrow then
      expandArrow:show()
    end
  else
    local subPanel = oldSelected:getParent()
    local parentCategory = subPanel and subPanel:getParent()
    if parentCategory and parentCategory:getChildById("subCategories") then
      parentCategory:setHeight(22)
      parentCategory:getChildById("subCategories"):hide()

      local expandArrow = parentCategory:getChildById("expandArrow")
      if expandArrow then
        expandArrow:show()
      end
    end
  end

  selected = nil
end

function comma_value(n)
  local left, num, right = string.match(tostring(n), "^([^%d]*%d)(%d*)(.-)$")
  if not left then
    return tostring(n)
  end
  return left .. (num:reverse():gsub("(%d%d%d)", "%1,"):reverse()) .. right
end

function addCategory(data)
  local categoriesList = gameStoreWindow:getChildById("categoriesList")
  local category
  
  if data.parent then
    local parentPanel = categoriesList:getChildById(data.parent)
    if parentPanel then
      category = g_ui.createWidget("ShopSubCategory", parentPanel:getChildById("subCategories"))
      parentPanel:getChildById("expandArrow"):show()
    end
  end

  if not category then
    category = g_ui.createWidget("ShopCategory", categoriesList)
  end

  category:setId(data.title)

  local iconId = categoryIconClips[data.icon] or 1
  category:getChildById("button"):setIconClip(iconId * 13 .. " 0 13 13")
  category:getChildById("name"):setText(data.title)
end

function onGameStoreUpdatePoints(data)
  premiumPoints = tonumber(data.points) or 0

  local pointsWidget = gameStoreWindow:getChildById("balance"):getChildById("value")
  pointsWidget:setText(comma_value(premiumPoints))

  local balanceSecond = gameStoreWindow:getChildById("balanceSecond")
  if balanceSecond then
    balanceSecond:hide()
    balanceSecond:setWidth(1)
    balanceSecond:setMarginLeft(0)
  end

  if transferWindow then
    transferWindow:getChildById("coinsBalance"):setText(tr("Transferable Tibia Coins: ") .. comma_value(premiumPoints))
    transferWindow:getChildById("coinsAmountScrollbar"):setMaximum(premiumPoints)

    transferWindow:getChildById("taskPointsBalance"):hide()
    transferWindow:getChildById("taskPointsCoin"):hide()
    transferWindow:getChildById("taskPointsAmountLabel"):hide()
    transferWindow:getChildById("taskPointsLabelCoin"):hide()
    transferWindow:getChildById("taskPointsAmountScrollbar"):hide()
    transferWindow:setOn(false)
  end
end

function select(self, ignoreSearch)
  hideHistory()
  if not ignoreSearch then
    eraseSearchResults()
  end

  local selfParent = self:getParent()
  local panel = selfParent:getChildById("subCategories")
  if panel then
    deselect()
    selected = selfParent

    if panel:getChildCount() > 0 then
      panel:show()
      selfParent:setHeight((panel:getChildCount() + 1) * 22)
      selfParent:getChildById("expandArrow"):hide()
      select(panel:getChildren()[1]:getChildById("button"), true)
      return
    end

    self:setChecked(true)
    showOffers(selfParent:getId())
    return
  end

  if selected then
    local oldButton = selected:getChildById("button")
    if oldButton then
      oldButton:setChecked(false)
    end

    local arrow = selected:getChildById("selectArrow")
    if arrow then
      arrow:hide()
    end
  end

  selected = selfParent
  self:setChecked(true)

  local arrow = selfParent:getChildById("selectArrow")
  if arrow then
    arrow:show()
  end

  showOffers(selfParent:getId())
end

function selectOffer(self)
  if selectedOffer then
    selectedOffer:setChecked(false)
  end

  self:setChecked(true)
  selectedOffer = self

  updateDescription(self)
end

function showOffers(id)
  local offersCache = offers[id] or {}
  local offersPanel = gameStoreWindow:getChildById("offers")
  local offersList = offersPanel:getChildById("offersList")
  offersList:destroyChildren()

  selectedOffer = nil
  offersPanel:getChildById("offerDetails"):hide()

  for i = 1, #offersCache do
    local offer = offersCache[i]
    local widget = offersList:getChildById(offer.name)

    if widget then
      local additionalPriceWidget = widget:getChildById("additionalPrice")
      additionalPriceWidget:getChildById("coin"):setOn(false)
      additionalPriceWidget:getChildById("value"):setText(comma_value(offer.price))
      additionalPriceWidget:show()

      local additionalCountWidget = widget:getChildById("additionalCount")
      additionalCountWidget:setText(offer.count .. "x")
      additionalCountWidget:show()

      local primaryCountWidget = widget:getChildById("count")
      if widget.data.count > 1 and widget.data.categoryId == CATEGORY_ITEM then
        primaryCountWidget:show()
      else
        primaryCountWidget:hide()
      end
      widget.additionalData = offer
    else
      widget = g_ui.createWidget("OfferWidget", offersList)
      local priceWidget = widget:getChildById("price")
      priceWidget:getChildById("coin"):setOn(false)
      priceWidget:getChildById("value"):setText(comma_value(offer.price))

      widget:getChildById("name"):setText(offer.name)
      if offer.count > 1 and offer.categoryId == CATEGORY_ITEM then
        widget:getChildById("count"):setText(offer.count .. "x")
        widget:getChildById("count"):show()
      else
        widget:getChildById("count"):hide()
      end

      widget:setId(offer.name)
      widget.data = offer
      widget.categoryId = id
      widget.offerCategoryId = offer.categoryId

      setOfferVisual(widget:getChildById("imagePanel"), offer)

      if not selectedOffer then
        selectOffer(widget)
      end
    end
  end
end

function updateDescription(self)
  local offersPanel = gameStoreWindow:getChildById("offers")
  local offerDetails = offersPanel:getChildById("offerDetails")
  offerDetails:show()
  offerDetails:getChildById("name"):setText(self.data.name)

  local descriptionPanel = offerDetails:getChildById("description")
  descriptionPanel:destroyChildren()

  local description = self.data.description
  local category = categories[self.categoryId]
  if (not description or description == "") and category then
    description = category.description
  end

  local widget = g_ui.createWidget("OfferDescripionLabel", descriptionPanel)
  widget:setText(description or "")

  local buyButton = offerDetails:getChildById("buyButton")
  local priceWidget = offerDetails:getChildById("price")
  local additionalBuyButton = offerDetails:getChildById("additionalBuyButton")
  local additionalPriceWidget = offerDetails:getChildById("additionalPrice")

  if self.data.count > 1 and self.data.categoryId == CATEGORY_ITEM then
    buyButton:setText("Buy " .. self.data.count)
  else
    buyButton:setText("Buy")
  end
  buyButton:setEnabled(self.data.price <= premiumPoints)
  buyButton.price = self.data.price
  buyButton.count = self.data.count
  buyButton.offerData = self.data

  priceWidget:setOn(false)
  priceWidget:setText(comma_value(self.data.price))
  priceWidget:setEnabled(self.data.price <= premiumPoints)

  if self.additionalData then
    additionalBuyButton:setText("Buy " .. self.additionalData.count)
    additionalBuyButton:setEnabled(self.additionalData.price <= premiumPoints)
    additionalBuyButton.price = self.additionalData.price
    additionalBuyButton.count = self.additionalData.count
    additionalBuyButton.offerData = self.additionalData
    additionalBuyButton:show()

    additionalPriceWidget:setOn(false)
    additionalPriceWidget:setText(comma_value(self.additionalData.price))
    additionalPriceWidget:setEnabled(self.additionalData.price <= premiumPoints)
    additionalPriceWidget:show()
  else
    additionalBuyButton.offerData = nil
    additionalBuyButton:hide()
    additionalPriceWidget:hide()
  end

  setOfferVisual(offerDetails:getChildById("imagePanel"), self.data)
end

function updateSelectedOfferState()
  if selectedOffer then
    updateDescription(selectedOffer)
  end
end

function onOfferBuy(self)
  if not selectedOffer then
    displayInfoBox("Error", "Something went wrong, make sure to select a category and offer.")
    return
  end

  pendingBuyOffer = self and self.offerData or selectedOffer.data
  if not pendingBuyOffer then
    displayInfoBox("Error", "Something went wrong, make sure to select a category and offer.")
    return
  end

  hide()

  local itemText = pendingBuyOffer.name
  if pendingBuyOffer.count > 1 and pendingBuyOffer.categoryId == CATEGORY_ITEM then
    itemText = pendingBuyOffer.count .. "x " .. itemText
  end

  local msg = "Do you want to buy " .. itemText .. " for " .. comma_value(pendingBuyOffer.price) .. " Tibia Coins?"
  msgWindow = displayGeneralBox("Purchase Confirmation", msg, {
    { text = "Yes", callback = buyConfirmed },
    { text = "No", callback = buyCanceled },
    anchor = AnchorHorizontalCenter
  }, buyConfirmed, buyCanceled)
end

function buyConfirmed()
  if msgWindow then
    msgWindow:destroy()
    msgWindow = nil
  end

  if not pendingBuyOffer then
    show()
    return
  end

  if pendingBuyOffer.oftype == "changename" then
    changeName()
    return
  end

  requestBuy(pendingBuyOffer.offerId)
  pendingBuyOffer = nil
end

function buyCanceled()
  if msgWindow then
    msgWindow:destroy()
    msgWindow = nil
  end
  pendingBuyOffer = nil
  show()
end

function changeName()
  if changeNameWindow then
    changeNameWindow:destroy()
    changeNameWindow = nil
  end

  changeNameWindow = g_ui.displayUI("changename")
  changeNameWindow:show()
  changeNameWindow:raise()
  changeNameWindow:focus()
end

function confirmChangeName()
  if not changeNameWindow or not pendingBuyOffer then
    return
  end

  local newName = trim(changeNameWindow:getChildById("targetName"):getText())
  requestBuy(pendingBuyOffer.offerId, newName)

  changeNameWindow:destroy()
  changeNameWindow = nil
  pendingBuyOffer = nil
end

function cancelChangeName()
  if changeNameWindow then
    changeNameWindow:destroy()
    changeNameWindow = nil
  end

  pendingBuyOffer = nil
  show()
end

function displayInfoBoxWithCallback(title, message, callback)
  local messageBox
  local defaultCallback = function()
    if callback then
      callback()
    end
    messageBox:ok()
  end

  messageBox = UIMessageBox.display(title, message, {
    { text = "Ok", callback = defaultCallback }
  }, defaultCallback, defaultCallback)
  return messageBox
end

function buyPoints()
  g_platform.openUrl(DONATION_URL)
end

function createTransferWindow()
  if transferWindow then
    return
  end

  transferWindow = g_ui.displayUI("giftcoins")
  transferWindow:hide()
end

function toggleGiftCoins()
  if not transferWindow then
    return
  end

  hide()
  transferWindow:getChildById("coinsBalance"):setText(tr("Transferable Tibia Coins: ") .. comma_value(premiumPoints))
  transferWindow:getChildById("coinsAmountScrollbar"):setMaximum(premiumPoints)
  transferWindow:show()
  transferWindow:raise()
  transferWindow:focus()
  transferWindow:setOn(false)
end

function changeCoinsAmount(value)
  if transferWindow then
    transferWindow:getChildById("coinsAmountLabel"):setText("Amount to gift: " .. comma_value(value))
  end
end

function changeTaskPointsAmount(value)
  return true
end

function confirmGiftCoins()
  if not transferWindow then
    return
  end

  local target = trim(transferWindow:getChildById("recipient"):getText())
  local amount = tonumber(transferWindow:getChildById("coinsAmountScrollbar"):getValue()) or 0
  amount = math.floor(amount)

  if target == "" then
    displayInfoBoxWithCallback("Store Error", "Please enter the recipient character name.", function()
      toggleGiftCoins()
    end)
    return
  end

  if amount <= 0 then
    displayInfoBoxWithCallback("Store Error", "Please select an amount greater than zero.", function()
      toggleGiftCoins()
    end)
    return
  end

  requestTransfer(target, amount)
  transferWindow:getChildById("recipient"):setText("")
  transferWindow:getChildById("coinsAmountScrollbar"):setValue(0)
  transferWindow:hide()
end

function cancelGiftCoins()
  if transferWindow then
    transferWindow:hide()
    show()
  end
end

function onTypeSearch(self)
  gameStoreWindow:getChildById("searchButton"):setEnabled(#self:getText() > 2)
end

function eraseSearchResults()
  local widget = gameStoreWindow:getChildById("categoriesList"):getChildById(searchResultCategoryId)
  if widget then
    if selected == widget then
      selected = nil
    end
    widget:destroy()
  end
end

function onSearch()
  local searchTextEdit = gameStoreWindow:getChildById("searchTextEdit")
  local text = searchTextEdit:getText():lower()
  if #text < 3 then
    return
  end

  eraseSearchResults()
  addCategory({
    title = searchResultCategoryId,
    icon = "store_weapons",
    categoryId = CATEGORY_NONE
  })

  offers[searchResultCategoryId] = {}
  for categoryId, offerData in pairs(offers) do
    if categoryId ~= searchResultCategoryId then
      for _, offer in pairs(offerData) do
        if string.find(offer.name:lower(), text, 1, true) then
          table.insert(offers[searchResultCategoryId], offer)
        end
      end
    end
  end

  local children = gameStoreWindow:getChildById("categoriesList"):getChildren()
  select(children[#children]:getChildById("button"), true)
  searchTextEdit:clearText()
end
