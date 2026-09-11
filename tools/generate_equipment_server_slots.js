const fs = require('fs');
const path = require('path');

const SLOT_MAP = {
  head: 1,
  neck: 2,
  necklace: 2,
  amulet: 2,
  backpack: 3,
  armor: 4,
  body: 4,
  shield: 5,
  'right-hand': 5,
  hand: 6,
  'left-hand': 6,
  legs: 7,
  feet: 8,
  ring: 9,
  ammo: 10,
};

const WEAPON_TYPE_SLOT = {
  shield: 5,
  ammo: 10,
  ammunition: 10,
  sword: 6,
  axe: 6,
  club: 6,
  distance: 6,
  wand: 6,
  fist: 6,
  quiver: 5,
};

function parseItemIds(openTag) {
  const single = openTag.match(/\bid="(\d+)"/);
  if (single) return [parseInt(single[1], 10)];
  const from = openTag.match(/\bfromid="(\d+)"/);
  const to = openTag.match(/\btoid="(\d+)"/);
  if (from && to) {
    const start = parseInt(from[1], 10);
    const end = parseInt(to[1], 10);
    if (end - start > 5000) return [];
    const ids = [];
    for (let i = start; i <= end; i++) ids.push(i);
    return ids;
  }
  return [];
}

function attrValues(block, key) {
  const re = new RegExp(`<attribute key="${key}" value="([^"]+)"`, 'gi');
  const out = [];
  let m;
  while ((m = re.exec(block)) !== null) out.push(m[1]);
  return out;
}

function itemName(openTag) {
  const m = openTag.match(/\bname="([^"]+)"/i);
  return m ? m[1].toLowerCase() : '';
}

function resolveSlot(block, openTag) {
  const slotTypes = attrValues(block, 'slotType').map((s) => s.toLowerCase());
  const weaponTypes = attrValues(block, 'weaponType').map((w) => w.toLowerCase());
  const name = itemName(openTag);

  for (const slot of attrValues(block, 'slot')) {
    const mapped = SLOT_MAP[slot.toLowerCase()];
    if (mapped) return mapped;
  }

  for (const weaponType of weaponTypes) {
    const mapped = WEAPON_TYPE_SLOT[weaponType];
    if (mapped) return mapped;
  }

  if (slotTypes.includes('two-handed')) {
    for (const weaponType of weaponTypes) {
      if (['distance', 'sword', 'axe', 'club', 'wand'].includes(weaponType)) {
        return 6;
      }
    }
  }

  return null;
}

function classifyItem(block, openTag, invSlot) {
  const slotTypes = attrValues(block, 'slotType').map((s) => s.toLowerCase());
  const weaponTypes = attrValues(block, 'weaponType').map((w) => w.toLowerCase());
  const name = itemName(openTag);
  const kinds = {};

  if (weaponTypes.includes('quiver') || name.includes('quiver') || attrValues(block, 'slot').includes('right-hand')) {
    if (name.includes('quiver') || weaponTypes.includes('quiver')) {
      kinds.quiver = true;
    }
  }

  if (weaponTypes.includes('shield') || attrValues(block, 'slot').includes('shield')) {
    kinds.shield = true;
  }

  if (
    weaponTypes.includes('distance') &&
    (slotTypes.includes('two-handed') || name.includes('bow') || name.includes('crossbow'))
  ) {
    kinds.twoHandedDistance = true;
  }

  if (invSlot === 5 && !kinds.quiver && !kinds.shield && name.includes('quiver')) {
    kinds.quiver = true;
  }

  if (invSlot === 5 && !kinds.quiver && kinds.shield !== true && weaponTypes.length === 0 && attrValues(block, 'slot').includes('shield')) {
    kinds.shield = true;
  }

  return kinds;
}

function parseItemsXml(filePath) {
  const text = fs.readFileSync(filePath, 'utf8');
  const slots = {};
  const quivers = {};
  const shields = {};
  const twoHandedDistance = {};
  let pos = 0;

  while (true) {
    const start = text.indexOf('<item ', pos);
    if (start === -1) break;
    const openEnd = text.indexOf('>', start);
    if (openEnd === -1) break;
    const close = text.indexOf('</item>', openEnd);
    if (close === -1) break;

    const openTag = text.slice(start, openEnd + 1);
    const block = text.slice(openEnd + 1, close);
    pos = close + '</item>'.length;

    const itemIds = parseItemIds(openTag);
    if (!itemIds.length) continue;

    const invSlot = resolveSlot(block, openTag);
    if (invSlot === null) continue;

    const kinds = classifyItem(block, openTag, invSlot);

    for (const itemId of itemIds) {
      slots[itemId] = invSlot;
      if (kinds.quiver) quivers[itemId] = true;
      if (kinds.shield) shields[itemId] = true;
      if (kinds.twoHandedDistance) twoHandedDistance[itemId] = true;
    }
  }

  return { slots, quivers, shields, twoHandedDistance };
}

function emitLua(data, outPath) {
  const lines = ['return {', '  slots = {'];
  for (const itemId of Object.keys(data.slots).map(Number).sort((a, b) => a - b)) {
    lines.push(`    [${itemId}] = ${data.slots[itemId]},`);
  }
  lines.push('  },', '  quivers = {');
  for (const itemId of Object.keys(data.quivers).map(Number).sort((a, b) => a - b)) {
    lines.push(`    [${itemId}] = true,`);
  }
  lines.push('  },', '  shields = {');
  for (const itemId of Object.keys(data.shields).map(Number).sort((a, b) => a - b)) {
    lines.push(`    [${itemId}] = true,`);
  }
  lines.push('  },', '  twoHandedDistance = {');
  for (const itemId of Object.keys(data.twoHandedDistance).map(Number).sort((a, b) => a - b)) {
    lines.push(`    [${itemId}] = true,`);
  }
  lines.push('  },', '}');
  fs.writeFileSync(outPath, lines.join('\n') + '\n', 'utf8');
}

const itemsXml = process.argv[2] || path.join(
  'C:', 'Users', 'fabim', 'Downloads', 'forgottenserver-downgrade-1.8-8.60', 'data', 'items', 'items.xml'
);
const outLua = process.argv[3] || path.join(
  'C:', 'Users', 'fabim', 'Downloads', 'OTC-Fonticak', 'modules', 'game_actionbar', 'logics', 'EquipmentServerSlots.lua'
);

const data = parseItemsXml(itemsXml);
emitLua(data, outLua);

const checks = [3350, 3349, 3409, 3051, 3552, 35562];
console.log(`Wrote ${Object.keys(data.slots).length} slot entries to ${outLua}`);
for (const itemId of checks) {
  console.log(
    `  [${itemId}] slot=${data.slots[itemId] ?? 'MISSING'} quiver=${!!data.quivers[itemId]} shield=${!!data.shields[itemId]} 2hDist=${!!data.twoHandedDistance[itemId]}`
  );
}
