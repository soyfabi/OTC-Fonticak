ConfigShare = {
  url = "https://servicesbot-config-apisrcindexjs.fabiotserver.workers.dev/",
  timeout = 15,
  maxBytes = 1024 * 1024,
  hashLength = 12,
}

local function encodeQuery(value)
  return tostring(value or ""):gsub("\n", "\r\n"):gsub("([^%w%-_%.~])", function(char)
    return string.format("%%%02X", string.byte(char))
  end)
end

function ConfigShare.normalizeHash(value)
  local text = tostring(value or ""):trim():lower()
  local hash = text:match("^([a-f0-9]+)$")
  if not hash then
    hash = text:match("config hash:%s*([a-f0-9]+)")
  end
  if not hash or hash:len() ~= ConfigShare.hashLength then
    return nil
  end
  return hash
end

function ConfigShare.parseUploadResponse(data, err)
  if err then
    return nil, tostring(err)
  end
  if type(data) ~= "table" then
    return nil, "Invalid response from config server."
  end
  if data.error then
    return nil, tostring(data.error)
  end
  local hash = ConfigShare.normalizeHash(data.hash or data.message)
  if not hash then
    return nil, "Config server returned an invalid hash."
  end
  return hash, nil, data
end

function ConfigShare.upload(kind, name, contents, callback)
  if kind ~= "bot" and kind ~= "options" then
    return nil, "Invalid config kind."
  end
  if type(contents) ~= "string" or contents:len() == 0 then
    return nil, "Config is empty."
  end
  if contents:len() > ConfigShare.maxBytes then
    return nil, string.format("Config is too big (%d KB). Maximum is 1024 KB.", math.floor(contents:len() / 1024))
  end

  local url = ConfigShare.url .. "?config=" .. encodeQuery(name) .. "&kind=" .. kind
  if kind == "bot" then
    return HTTP.postBinaryJSON(url, contents, callback, ConfigShare.timeout)
  end
  return HTTP.postJSON(url, contents, callback, ConfigShare.timeout)
end

function ConfigShare.download(kind, value, extension, callback, progressCallback)
  if kind ~= "bot" and kind ~= "options" then
    return nil, "Invalid config kind."
  end
  local hash = ConfigShare.normalizeHash(value)
  if not hash then
    return nil, "Enter a valid 12-character config hash."
  end
  local fileName = string.format("%s_%s.%s", kind, hash, extension or (kind == "bot" and "zip" or "json"))
  local url = ConfigShare.url .. "?hash=" .. hash .. "&kind=" .. kind
  local operation = HTTP.download(url, fileName, callback, progressCallback, ConfigShare.timeout)
  return operation, nil, hash
end
