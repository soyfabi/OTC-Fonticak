local context = G.botContext

-- Spread script loading across frames so login/config switches don't freeze the UI.
-- eachFn(item) is called for every entry; onDone() runs when the queue finishes (or is cancelled).
context.loadScriptQueue = function(items, eachFn, onDone, opts)
  opts = opts or {}
  local budgetMs = opts.budgetMs or 6
  local generation = 0
  if modules.game_bot and modules.game_bot.getBotLoadGeneration then
    generation = modules.game_bot.getBotLoadGeneration()
  end
  context._asyncLoadStarted = true
  context._botLoading = true

  local i = 1
  local total = #items

  local function isCancelled()
    if modules.game_bot and modules.game_bot.getBotLoadGeneration then
      return generation ~= modules.game_bot.getBotLoadGeneration()
    end
    return false
  end

  local function step()
    if isCancelled() then
      return
    end
    if i > total then
      context._botLoading = false
      if onDone then
        local ok, err = pcall(onDone)
        if not ok then
          context.warn("Async load onDone error: " .. tostring(err))
        end
      end
      if context.markBotReady then
        context.markBotReady()
      end
      return
    end

    local started = g_clock.millis()
    while i <= total and (g_clock.millis() - started) < budgetMs do
      if isCancelled() then
        return
      end
      local item = items[i]
      i = i + 1
      local ok, err = pcall(eachFn, item, i - 1, total)
      if not ok then
        context.warn("Async load error (" .. tostring(item) .. "): " .. tostring(err))
      end
    end

    if context.onBotLoadProgress then
      context.onBotLoadProgress(math.min(i - 1, total), total)
    end
    addEvent(step)
  end

  addEvent(step)
end

context.loadScript = function(path, onLoadCallback)
  if type(path) ~= 'string' then
    return context.error("Invalid path for loadScript: " .. tostring(path))
  end
  if path:lower():find("http") == 1 then
    return context.loadRemoteScript(path)
  end
  if not g_resources.fileExists(path) then
    return context.error("File " .. path .. " doesn't exist")
  end
  local status, result = pcall(function()
    if _VERSION == "Lua 5.1" and type(jit) ~= "table" then
      local func = assert(loadstring(g_resources.readFileContents(path)))
      setfenv(func, context)
      func()
    else        
      assert(load(g_resources.readFileContents(path), path, nil, context))()
    end
  end)
  if not status then
    return context.error("Error while loading script from: " .. path .. ":\n" .. result)
  end
  if onLoadCallback then
    onLoadCallback()
  end
end

context.loadRemoteScript = function(url, onLoadCallback)
  if type(url) ~= 'string' or url:lower():find("http") ~= 1 then
    return context.error("Invalid url for loadRemoteScript: " .. tostring(url))
  end

  HTTP.get(url, function(data, err)
    if err or data:len() == 0 then
      -- try to load from cache
      if type(context.storage.scriptsCache) ~= 'table' then
        context.storage.scriptsCache = {}
      end
      local cache = context.storage.scriptsCache[url]
      if cache and type(cache) == 'string' and cache:len() > 0 then
        data = cache
      else
        return context.error("Can't load script from: " .. url .. ", error: " .. err)
      end
    end

    local status, result = pcall(function()
      if _VERSION == "Lua 5.1" and type(jit) ~= "table" then
        local func = assert(loadstring(data))
        setfenv(func, context)
        func()
      else        
        assert(load(data, url, nil, context))()
      end
    end)
    if not status then
      return context.error("Error while loading script from: " .. url .. ":\n" .. result)
    end
    -- cache script
    if type(context.storage.scriptsCache) ~= 'table' then
      context.storage.scriptsCache = {}
    end
    context.storage.scriptsCache[url] = data
    if onLoadCallback then
      onLoadCallback()
    end
  end)
end
