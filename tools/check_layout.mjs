// Execute the actual, dependency-free Luau layout module in a Lua VM. These
// invariants catch disconnected doorways, missing treads and 100-door overflow.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import fengari from "fengari";

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const source = fs.readFileSync(path.join(root, "src/ReplicatedStorage/NocturneLayout.luau"), "utf8");
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const assertions = `
local Layout = (function()
${source}
end)()
assert(Layout.RoomWidth > Layout.StairWidth)
assert(Layout.StairWidth > Layout.DoorWidth)
assert(Layout.StairStart > 5 and Layout.StairEnd < Layout.RoomLength - 5)
assert(Layout.StoreyRise / Layout.StairSteps <= 1, "stairs too high for a Humanoid")
local climbs = 0
for index = 0, 99 do
    local entry = Layout.EntranceY(index)
    local exit = Layout.ExitY(index)
    assert(exit == Layout.EntranceY(index + 1), "doorway height mismatch at door " .. (index + 1))
    assert(Layout.RoomIndexAt(index * Layout.RoomLength + 5) == index)
    if Layout.IsStair(index) then
        climbs = climbs + 1
        assert(exit - entry == Layout.StoreyRise)
        assert(Layout.WalkwayY(index, 0) == entry)
        assert(Layout.WalkwayY(index, Layout.StairStart) == entry)
        assert(Layout.WalkwayY(index, Layout.StairEnd) == exit)
        assert(Layout.WalkwayY(index, Layout.RoomLength) == exit)
        local previous = entry
        for n = 1, 440 do
            local surface = Layout.WalkwayY(index, n / 10)
            assert(surface >= previous, "downward gap in stair room " .. index)
            assert(surface - previous <= Layout.StoreyRise / Layout.StairSteps + 0.0001,
                "unclimbable riser in room " .. index)
            previous = surface
        end
    else
        assert(exit == entry)
        for _, atZ in ipairs({0, 7, 15, 30, 37, 44}) do
            assert(Layout.WalkwayY(index, atZ) == entry)
        end
    end
end
assert(not Layout.IsStair(0) and Layout.IsStair(1))
assert(climbs == 17, "100 doors should cross exactly 17 stair flights")
assert(Layout.EntranceY(100) == 17 * Layout.StoreyRise)
return climbs
`;
const status = lauxlib.luaL_dostring(L, to_luastring(assertions));
if (status !== lua.LUA_OK) {
  throw new Error(`Physical route is broken: ${to_jsstring(lua.lua_tostring(L, -1))}`);
}
console.log(`Geometry OK: 100 connected doorways, ${lua.lua_tointeger(L, -1)} enclosed flights, ≤0.75-stud steps`);
