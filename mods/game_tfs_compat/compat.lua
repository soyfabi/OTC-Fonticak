-- Compat com o TFS downgrade 1.8/8.60 (família Mateuzkl).
-- O Fonticak já fala quase todo o dialeto nativamente (features estáticas a 860,
-- tier byte via marker OTCv8TierByte, quiver count, kill tracker 0xD1, imbuement
-- 0xEB, proficiency 0x5A/0x5B, party analyzer 0x2B). Aqui ficam só os pacotes
-- que o engine não cobre.

-- 0x2F (custom unjustified points): JÁ tratado pelo Fonticak em
-- modules/game_market/market_protocol_custom.lua (skipBytes(12), mesmo
-- formato 6x u8 + u32 + 2x u8) — registrar de novo dá "opcode already
-- registered" e derruba o módulo.

-- 0x8C (extended): ícones de condição de 64 bits (Player::sendIcons manda
-- u64 little-endian com os bits >= 16: Hex, Rooted, Feared, Goshnar, Agony...).
-- O pacote nativo de icons (u16) chega antes e zera os bits altos; aqui
-- reaplicamos os bits altos por cima dos 16 baixos.
local HIGH_STATES_OPCODE = 0x8C

-- Procs do misc_analyzer (data/scripts/network/misc_analyzer/miscanalyzer.lua),
-- enviados a qualquer client OTC. Sem case nativo, cairiam no default (que
-- descarta o resto da mensagem com warning).
-- TODO: integrar com a UI de analyser.
local CHARM_ACTIVATED_OPCODE = 0x2D         -- u8 charmId
local IMBUEMENT_ACTIVATED_OPCODE = 0x30     -- u8 imbuementId + u32 amount
local SPECIAL_SKILL_ACTIVATED_OPCODE = 0x31 -- u8 skillId

local function parseHighStates(protocol, opcode, buffer)
    if #buffer < 8 then
        return
    end

    local lo = string.byte(buffer, 1) + string.byte(buffer, 2) * 256 +
        string.byte(buffer, 3) * 65536 + string.byte(buffer, 4) * 16777216
    local hi = string.byte(buffer, 5) + string.byte(buffer, 6) * 256 +
        string.byte(buffer, 7) * 65536 + string.byte(buffer, 8) * 16777216
    local highStates = lo + hi * 4294967296
    if highStates == 0 then
        return
    end

    local player = g_game.getLocalPlayer()
    if player then
        -- bits 0-15 vêm do pacote nativo; 0x8C é autoridade nos bits altos
        player:setStates((player:getStates() % 65536) + highStates)
    end
end

local function parseCharmActivated(protocol, msg)
    msg:getU8() -- charmId
end

local function parseImbuementActivated(protocol, msg)
    msg:getU8() -- imbuementId
    msg:getU32() -- amount
end

local function parseSpecialSkillActivated(protocol, msg)
    msg:getU8() -- skillId
end

function init()
    ProtocolGame.registerOpcode(CHARM_ACTIVATED_OPCODE, parseCharmActivated)
    ProtocolGame.registerOpcode(IMBUEMENT_ACTIVATED_OPCODE, parseImbuementActivated)
    ProtocolGame.registerOpcode(SPECIAL_SKILL_ACTIVATED_OPCODE, parseSpecialSkillActivated)
    ProtocolGame.registerExtendedOpcode(HIGH_STATES_OPCODE, parseHighStates)
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(HIGH_STATES_OPCODE)
    ProtocolGame.unregisterOpcode(SPECIAL_SKILL_ACTIVATED_OPCODE)
    ProtocolGame.unregisterOpcode(IMBUEMENT_ACTIVATED_OPCODE)
    ProtocolGame.unregisterOpcode(CHARM_ACTIVATED_OPCODE)
end
