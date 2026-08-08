-- Fonticak compatibility shims for the Astra store UI.

local storeOtuiVars = {
  ['$var-cip-font'] = 'verdana-11px-antialised',
  ['$var-cip-font-off'] = 'verdana-11px-antialised',
  ['$var-cip-main-font'] = 'Verdana Bold-11px',
  ['$var-text-color'] = '#dfdfdf',
  ['$var-text-cip-color'] = '#c0c0c0',
  ['$var-text-cip-color-highlight'] = '#f4f4f4',
  ['$var-text-cip-color-white'] = '#f7f7f7',
  ['$var-text-cip-color-grey'] = '#909090',
  ['$var-text-cip-color-green'] = '#44ad25',
  ['$var-text-cip-color-orange'] = '#ff9854',
  ['$var-text-cip-color-yellow'] = '#ffda34',
  ['$var-text-cip-color-light-red'] = '#f75f5f',
  ['$var-text-cip-color-blue'] = '#1872c3',
  ['$var-text-cip-color-green-disabled'] = '#255f15',
  ['$var-text-color-disabled'] = '#dfdfdf88',
  ['$var-cip-inactive-color'] = '#707070',
  ['$var-text-cip-store-disabled'] = '#565656',
  ['$var-text-cip-store-red'] = '#D33C3C',
  ['$var-text-cip-store-red-disabled'] = '#6d2626',
  ['$var-text-cip-store-sale'] = '#ffda34',
  ['$var-text-cip-store-sale-disabled'] = '#6f5f18',
  ['$var-text-cip-store-timed'] = '#1872c3',
  ['$var-text-cip-store-timed-disabled'] = '#183f63',
  ['$var-textlist-selected'] = '#585858',
  ['$var-textlist-even'] = '#414141',
  ['$var-textlist-odd'] = '#484848',
}

if not tovar then
  function tovar(key)
    return storeOtuiVars[key] or tostring(key or ''):gsub('^%$', '')
  end
else
  local previousTovar = tovar
  function tovar(key)
    return storeOtuiVars[key] or previousTovar(key)
  end
end

local function resolveStyleValue(value)
  if type(value) == 'string' and value:sub(1, 1) == '$' then
    return tovar(value)
  end
  return value
end

if UIWidget then
  UIWidget.insertLuaCall = UIWidget.insertLuaCall or function(self) return self end
  UIWidget.removeLuaCall = UIWidget.removeLuaCall or function(self) return self end
  UIWidget.setClickSound = UIWidget.setClickSound or function(self) return self end
  UIWidget.addSound = UIWidget.addSound or function(self) return self end
  UIWidget.setHTML = UIWidget.setHTML or function(self, html)
    if self.setText then
      local text = tostring(html or '')
      text = text:gsub('<br%s*/?>', '\n')
      text = text:gsub('</p>', '\n')
      text = text:gsub('<[^>]->', '')
      self:setText(text)
    end
    return self
  end
  UIWidget.setImageVisible = UIWidget.setImageVisible or function(self, visible)
    self.imageVisible = visible
    return self
  end
  UIWidget.isImageVisible = UIWidget.isImageVisible or function(self)
    return self.imageVisible ~= false
  end
  UIWidget.getImageVisible = UIWidget.getImageVisible or UIWidget.isImageVisible
  UIWidget.setImageShader = UIWidget.setImageShader or function(self, shader)
    self.imageShader = shader
    return self
  end
  UIWidget.getImageShader = UIWidget.getImageShader or function(self)
    return self.imageShader or ''
  end
  UIWidget.setShader = UIWidget.setShader or UIWidget.setImageShader
  UIWidget.hook = UIWidget.hook or function(self) return self end

  if UIWidget.setColor and not UIWidget._storeSetColorWrapped then
    local rawSetColor = UIWidget.setColor
    UIWidget.setColor = function(self, color)
      return rawSetColor(self, resolveStyleValue(color))
    end
    UIWidget._storeSetColorWrapped = true
  end
end

-- Astra UIItem:hook() applies rarity/tier borders; Fonticak can no-op safely.
if UIItem then
  UIItem.hook = UIItem.hook or function(self) return self end
end

-- Store OTUI uses animate/idle-animate. Provide Lua helpers that drive
-- Creature:setStaticWalking so previews animate even before a C++ rebuild.
if UICreature and not UICreature._storeAnimateCompat then
  local rawSetOutfit = UICreature.setOutfit

  local function applyPreviewWalk(self)
    local creature = self.getCreature and self:getCreature()
    if not creature or not creature.setStaticWalking then
      return
    end
    local shouldAnimate = self._storeAnimate or self._storeIdleAnimate or self._storeStaticWalking
    creature:setStaticWalking(shouldAnimate and 1000 or 0)
  end

  function UICreature:setAnimate(value)
    self._storeAnimate = value and true or false
    applyPreviewWalk(self)
  end

  function UICreature:setIdleAnimate(value)
    self._storeIdleAnimate = value and true or false
    applyPreviewWalk(self)
  end

  function UICreature:setStaticWalking(value)
    if type(value) == 'boolean' then
      self._storeStaticWalking = value
      applyPreviewWalk(self)
      return
    end
    local creature = self.getCreature and self:getCreature()
    if creature and creature.setStaticWalking then
      creature:setStaticWalking(value or 0)
    end
    self._storeStaticWalking = (tonumber(value) or 0) > 0
  end

  function UICreature:enableStorePreviewAnimation()
    self._storeAnimate = true
    self._storeIdleAnimate = true
    applyPreviewWalk(self)
  end

  if rawSetOutfit then
    function UICreature:setOutfit(outfit)
      rawSetOutfit(self, outfit)
      if self._storeAnimate or self._storeIdleAnimate or self._storeStaticWalking then
        applyPreviewWalk(self)
      end
    end
  end

  UICreature._storeAnimateCompat = true
end

if g_game then
  g_game.doThing = g_game.doThing or function() end
end

if g_client and not g_client.setInputLockWidget then
  g_client.setInputLockWidget = function() end
end

if not short_text then
  function short_text(text, chars_limit)
    text = tostring(text or '')
    chars_limit = chars_limit or 20
    if #text <= chars_limit then
      return text
    end
    return text:sub(1, math.max(0, chars_limit - 3)) .. '...'
  end
end

-- Astra store scripts expect m_settings / client_settings.
m_settings = m_settings or modules.client_options
if not modules.client_settings then
  modules.client_settings = modules.client_options
end

if HTTP and not HTTP.downloadConditionalImage then
  function HTTP.downloadConditionalImage(url, data, callback)
    if callback then
      callback(nil, 'downloadConditionalImage is not supported')
    end
  end
end
