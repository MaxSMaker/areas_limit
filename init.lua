-- Check areas mod
if not areas or not areas.areas then
    error("Incorrect areas mod")
    return
end

local areas_exist = {}
local storage = minetest.get_mod_storage()
local S = minetest.get_translator(minetest.get_current_modname())
local mod_name = minetest.get_current_modname()

local areas_limit_free_count = tonumber(minetest.settings:get("areas_limit_free_count")) or 4
local areas_limit_cost_item_name = minetest.settings:get("areas_limit_cost_item_name") or "default:cobble"
local areas_limit_cost_item_count = tonumber(minetest.settings:get("areas_limit_cost_item_count")) or 99
local areas_limit_cost_multiplier = tonumber(minetest.settings:get("areas_limit_cost_multiplier")) or 2

local registered_cost_item_name = {description = "Unknown item", name = areas_limit_cost_item_name}

-- Check payment item (after full game load)
minetest.after(
    0,
    function()
        registered_cost_item_name = minetest.registered_items[areas_limit_cost_item_name]
        if not registered_cost_item_name then
            minetest.log("error", mod_name .. ": Incorrect limit cost (unknown item): " .. areas_limit_cost_item_name)
        end
    end
)

local get_limit = function(name)
    return storage:get_int("limit_" .. name) + areas_limit_free_count
end

local set_limit = function(name, count)
    if count > areas_limit_free_count then
        storage:set_int("limit_" .. name, count - areas_limit_free_count)
    else
        storage:set_int("limit_" .. name, 0)
    end
end

local available_count = function(name)
    return get_limit(name) - (areas_exist[name] or 0)
end

local next_limit_cost = function(name)
    local level = get_limit(name) - areas_limit_free_count
    local cost = areas_limit_cost_item_count
    while level > 0 do
        cost = cost * areas_limit_cost_multiplier
        level = level - 1
    end
    return cost
end

local inc_area_count = function(name)
    areas_exist[name] = (areas_exist[name] or 0) + 1
end

local dec_area_count = function(name)
    areas_exist[name] = (areas_exist[name] or 0) - 1
    if areas_exist[name] <= 0 then
        areas_exist[name] = nil
    end
end

for _, area in pairs(areas.areas) do
    inc_area_count(area.owner)
end

local rollback_add = function(id)
    local area = areas.areas[id]
    if area then
        minetest.chat_send_player(area.owner, S("Area @1 removed.", id))
        minetest.chat_send_player(
            area.owner,
            S("Area limit reached. Increase the area limit (see /areas_limit and /areas_limit_buy commands)")
        )

        areas:remove(id)
    end
end

areas:registerOnAdd(
    function(id, area)
        if area and not area.parent then
            inc_area_count(area.owner)
            if available_count(area.owner) < 0 then
                minetest.after(0, rollback_add, id)
            end
        end
    end
)

areas:registerOnRemove(
    function(id)
        area = areas.areas[id]
        if area and not area.parent then
            dec_area_count(area.owner)
        end
    end
)

minetest.register_on_chatcommand(
    function(name, command, params)
        if command == "protect" and params and available_count(name) <= 0 then
            minetest.chat_send_player(
                name,
                S("Area limit reached. Increase the area limit (see /areas_limit and /areas_limit_buy commands)")
            )
            return true
        end
        return false
    end
)

minetest.register_chatcommand(
    "areas_limit",
    {
        description = S("Get your area limit"),
        privs = {[areas.config.self_protection_privilege] = true},
        func = function(name, param)
            local next_cost = next_limit_cost(name)
            return true, S("Area limit used: @1/@2", areas_exist[name] or 0, get_limit(name)) ..
                S(
                    ", next limit price: @1 @2 (@3 @4)",
                    registered_cost_item_name.description,
                    next_cost,
                    registered_cost_item_name.name,
                    next_cost
                )
        end
    }
)

minetest.register_chatcommand(
    "areas_limit_buy",
    {
        description = S("Increase your area limit"),
        privs = {[areas.config.self_protection_privilege] = true},
        func = function(name, param)
            local next_cost = next_limit_cost(name)
            local inv = minetest.get_inventory({type = "player", name = name})

            local stack = ItemStack({name = areas_limit_cost_item_name, count = next_cost})
            if inv:contains_item("main", stack) then
                inv:remove_item("main", stack)
                set_limit(name, get_limit(name) + 1)

                local next_cost = next_limit_cost(name)
                return true, S("Your protect limit: @1", get_limit(name)) ..
                    S(
                        ", next limit price: @1 @2 (@3 @4)",
                        registered_cost_item_name.description,
                        next_cost,
                        registered_cost_item_name.name,
                        next_cost
                    )
            end

            return false, S(
                "Cannot take payment: @1 @2 (@3 @4)",
                registered_cost_item_name.description,
                next_cost,
                registered_cost_item_name.name,
                next_cost
            )
        end
    }
)

minetest.register_chatcommand(
    "admin_areas_limit",
    {
        params = S("<PlayerName> [<Limit>]"),
        description = S("Get or set areas limit for user"),
        privs = areas.adminPrivs,
        func = function(name, param)
            if param == "" then
                return false, S("Invalid usage, see /help @1.", "admin_areas_limit")
            end

            local name = param:match("^(%S+)$")
            if name then
                if not minetest.player_exists(name) then
                    return false, S("The player does not exist.")
                end
                return true, S("Areas limit for @1: @2", name, get_limit(name))
            end

            local name, limit = param:match("^(%S+)%s(%d+)$")
            if not name then
                return false, S("Invalid usage, see /help @1.", "admin_areas_limit")
            end

            if not minetest.player_exists(name) then
                return false, S("The player does not exist.")
            end

            set_limit(name, tonumber(limit))

            return true, S("Areas limit updated for @1: @2", name, get_limit(name))
        end
    }
)
