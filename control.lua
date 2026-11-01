local def = require("defines")


local function errorLog(errorText)
   game.print("(Robots_Build_Closest_First MOD) " .. errorText)
   game.print("Please report this on the mod portal with steps to reproduce it, thank you!")
   game.print("If you use other mods that add new types of roboport equipment, pls add a links to the exact mods you are using.")
end


local function get_eq_max_radius(eq)
   return math.floor(eq.prototype.take_result.place_as_equipment_result.logistic_parameters.construction_radius)
end

local function get_eq_max_area(eq)
   local max_radius = get_eq_max_radius(eq)
   return max_radius * max_radius * 4
end

local function get_grid_max_radius(grid)
   if not grid then return 0 end
   local sumsq = 0
   for _, eq in pairs(grid.equipment) do
      if eq.type == "roboport-equipment" then
         local r = get_eq_max_radius(eq) -- original full radius
         sumsq = sumsq + r * r
      end
   end
   return math.floor(math.sqrt(sumsq) + 0.5)
end

local function get_variant_name(eq, desired_radius)
   local max_radius = get_eq_max_radius(eq)
   local variant_radius = math.min(desired_radius, max_radius)
   return eq.prototype.take_result.place_as_equipment_result.name .. "-reduced-" .. variant_radius
end

local function get_player_real_robot_limit(player)
   local logistic = player.character.logistic_network
   local cell = logistic.cells[1]

   local robots_limit = logistic.robot_limit
   local robots_all = logistic.all_construction_robots

   return math.min(robots_all, robots_limit)
end

local function get_player_max_minus_charging(player)
   local logistic = player.character.logistic_network
   local cell = logistic.cells[1]

   local max = get_player_real_robot_limit(player)

   local charging = cell.charging_robot_count + cell.to_charge_robot_count

   return max - charging
end

local function get_player_available_robots(player)
   local logistic = player.character.logistic_network
   local cell = logistic.cells[1]

   local robots_limit = logistic.robot_limit
   local robots_all = logistic.all_construction_robots

   local real_limit = math.min(robots_all, robots_limit)

   local ava = logistic.available_construction_robots

   local charging = cell.charging_robot_count + cell.to_charge_robot_count

   return real_limit - charging
end

local function get_player_all_robot_order_count(player)
   local logistic = player.character.logistic_network

   local count = 0
   for _, robot in pairs(logistic.robots) do
      if robot.valid and robot.robot_order_queue then
         count = count + #robot.robot_order_queue
      end
   end
   return count
end

local function get_grid_any_inactive(grid)
   for _, eq in pairs(grid.equipment) do
      if eq.type == "roboport-equipment" then
         local spawn_minimum = eq.max_energy * 0.2
         if eq.energy < spawn_minimum then
            return true
         end
      end
   end
   return false
end

local function set_eq_radius(grid, eq, desired_radius)
   if desired_radius < 0 then
      return;
   end

   local eq_max_radius = get_eq_max_radius(eq)

   local desired_radius_rounded = math.floor(desired_radius + 0.5)

   desired_radius_rounded = math.min(desired_radius_rounded, eq_max_radius)

   local variant_name = get_variant_name(eq, desired_radius_rounded)
   if eq.name == variant_name then
      return
   end

   local eq_pos = eq.position
   local eq_energy = eq.energy
   local eq_quality = eq.quality.name

   grid.take { position = eq_pos }
   local new_eq = grid.put { name = variant_name, position = eq_pos, quality = eq_quality}

   if new_eq then
      new_eq.energy = eq_energy
   else
      errorLog('could not swap Roboport')
   end
end

local function set_grid_radius(grid, desired_radius)
   --game.print("set g r: "..desired_radius)
   if desired_radius < 0 then
      return
   end


   local desired_area = desired_radius * desired_radius * 4
   local summed_area = 0

   local roboports = {}
   for _, eq in next, grid.equipment do
      if eq.type == "roboport-equipment" then
         roboports[#roboports + 1] = eq
      end
   end
   table.sort(roboports, function(a, b)
      if a.position.y ~= b.position.y then
         return a.position.y < b.position.y
      end
      return a.position.x < b.position.x
   end)

   for i = 1, #roboports do
      local eq = roboports[i]
      if summed_area < desired_area then
         local needed_area = desired_area - summed_area
         local eq_max_area = get_eq_max_area(eq)
         local result_area = math.ceil(math.min(needed_area, eq_max_area))

         summed_area = summed_area + result_area

         local result_radius = math.sqrt(result_area) / 2
         set_eq_radius(grid, eq, result_radius)
      else
         set_eq_radius(grid, eq, 0)
      end
   end
end

local function clamp(min, max, value)
   return math.max(min, math.min(value, max))
end





local function addPositions(pos1, pos2)
    local x1 = pos1.x or pos1[1]
    local y1 = pos1.y or pos1[2]
    local x2 = pos2.x or pos2[1]
    local y2 = pos2.y or pos2[2]

    return { x = x1 + x2, y = y1 + y2 }
end


local function drawDebugVisuals(player, delta_time, radius, max_robots, avg_available, current_orders)
   local left_top = { player.position.x - radius, player.position.y - radius }
   local right_bottom = { player.position.x + radius, player.position.y + radius }

   local text_offset = -8

   local radiusTextPos = addPositions(player.position, {0,text_offset})
   text_offset = text_offset - 1

   local maxRobotsTextPos = addPositions(player.position, {0, text_offset})
   text_offset = text_offset - 1

   local avgAvailableTextPos = addPositions(player.position, {0, text_offset})
   text_offset = text_offset - 1

   local avgAvailableNumberTextPos = addPositions(player.position, {0, text_offset})
   text_offset = text_offset - 1

   local currentOrdersTextPos = addPositions(player.position, {0, text_offset})



   rendering.draw_rectangle {
      color = {1, 1, 1, 1},
      width = 2,
      filled = false,
      left_top = left_top,
      right_bottom = right_bottom,
      surface = player.surface,
      time_to_live = delta_time
   }
   rendering.draw_text{
      text = string.format("Radius: %.1f", radius),
      scale = 2,
      surface = player.surface,
      target = radiusTextPos,
      color = {1, 1, 1},
      time_to_live = delta_time
   }
   rendering.draw_text{
      text = string.format("MaxRobots: %d", max_robots),
      scale = 2,
      surface = player.surface,
      target = maxRobotsTextPos,
      color = {1, 1, 1},
      time_to_live = delta_time
   }
   rendering.draw_text{
        text = string.format("Avg Available: %d%%", avg_available / max_robots * 100),
        scale = 2,
        surface = player.surface,
        target = avgAvailableTextPos,
        color = {1, 1, 1},
        time_to_live = delta_time
   }
   rendering.draw_text{
        text = string.format("Avg Available: %d", avg_available),
        scale = 2,
        surface = player.surface,
        target = avgAvailableNumberTextPos,
        color = {1, 1, 1},
        time_to_live = delta_time
   }
   rendering.draw_text{
        text = string.format("Current Orders: %d", current_orders),
        scale = 2,
        surface = player.surface,
        target = currentOrdersTextPos,
        color = {1, 1, 1},
        time_to_live = delta_time
    }
   
   
end


--working values
local config = {
   update_pause = 10,            -- How many empty ticks between updates

   -- CONTROL SETTINGS
   grow_ratio = 0.85,            -- Grow when queued orders are below 85% of active non-charging robots
   shrink_ratio = 0.35,          -- Shrink when queued orders exceed capacity by more than 35% (min +3)

   base_grow_speed = 0.045,      -- Gentle grow speed when nearly all robots are busy (tiles/tick)
   max_grow_speed = 0.24,        -- Brisk grow speed when no/few orders are in range (tiles/tick)

   base_shrink_speed = 0.05,     -- Gentle shrink speed near the stay band (tiles/tick)
   max_shrink_speed = 0.22,      -- Brisk shrink speed when heavily overloaded (tiles/tick)

   move_floor_decay = 1.5,       -- How fast the anti-oscillation floor drops per tile of player movement
   move_speed_factor = 0.65,     -- Extra grow/shrink responsiveness per tile of player movement

   debug = false
}

local function updatePlayer(player, delta_time)
   -- validation checks
   if not (player and player.valid and player.character and player.character.valid) then return end

   local grid = player.character.grid
   if not (grid and grid.valid) then return end

   local logistic = player.character.logistic_network
   if not (logistic and logistic.valid) then return end

   local max_Radius = get_grid_max_radius(grid) or 0
   if max_Radius <= 0 then
      set_grid_radius(grid, 0)
      return
   end

   -- settings and shortcut
   local radius_limit_setting = def.limited_radius_table[settings.get_player_settings(player)[def.limited_radius_setting].value]
   if radius_limit_setting == 0 then
      radius_limit_setting = max_Radius
   end
   local radius_minimum_setting = def.minimum_radius_table[settings.get_player_settings(player)[def.minimum_radius_setting].value]

   local clamp_min = radius_minimum_setting
   local clamp_max = math.max(radius_limit_setting, clamp_min)

   if not player.is_shortcut_toggled("shortcut-toggle-robots-build-closest-first") then
      local use_limit = settings.get_player_settings(player)[def.use_limit_when_off_setting].value
      if use_limit then
         set_grid_radius(grid, radius_limit_setting)
      else
         set_grid_radius(grid, max_Radius)
      end
      return
   end

   -- load data
   local player_data = storage.player_data or {}
   local data = player_data[player.index] or {
      radius = clamp_min,
      applied_radius = clamp_min,
      floor_radius = clamp_min,
      last_orders = 0,
      no_orders_streak = 0,
      last_error = 0,
      avg_available_robots = 0 -- for debugging
   }

   -- robot order metrics
   local current_orders = get_player_all_robot_order_count(player)
   local max_robots = get_player_real_robot_limit(player)
   local available_robots = get_player_available_robots(player)
   local max_minus_charging = get_player_max_minus_charging(player)
   local charging_robots = max_robots - max_minus_charging

   local available_robots_inventory = player.character.logistic_network.available_construction_robots
   -- calculate moving average
   if data.avg_available_robots == 0 then
      data.avg_available_robots = available_robots_inventory
   else
      local smoothing = math.min(1, 0.003 * delta_time)
      data.avg_available_robots = data.avg_available_robots + (available_robots_inventory - data.avg_available_robots) * smoothing
   end

   -- track player movement so the radius responds immediately when walking/running/flying
   local pos = player.position
   local move_dist = 0
   if data.last_pos then
      local dx = pos.x - data.last_pos.x
      local dy = pos.y - data.last_pos.y
      move_dist = math.sqrt(dx * dx + dy * dy)
   end
   data.last_pos = { x = pos.x, y = pos.y }

   -- Compute GROW / STAY / SHRINK thresholds:
   -- 1. grow_limit is based on non-charging robots (charging robots cannot take orders,
   --    so we shouldn't grow the area just because robots paused to recharge).
   local grow_limit = math.floor(max_minus_charging * config.grow_ratio + 0.5)
   if max_minus_charging > 0 and grow_limit < 1 then
      grow_limit = 1
   end

   -- 2. shrink_limit is buffered above capacity and only lightly affected by charging
   --    so robots stopping to charge don't cause false shrinking.
   local effective_cap = math.max(max_minus_charging, math.floor(max_robots - charging_robots * 0.3 + 0.5))
   local shrink_margin = math.max(3, math.ceil(effective_cap * config.shrink_ratio))
   local shrink_limit = effective_cap + shrink_margin

   local applied_radius = clamp(clamp_min, clamp_max, data.applied_radius or math.floor(data.radius + 0.5))
   local last_applied_radius = data.last_applied_radius or applied_radius
   local last_orders = data.last_orders or 0
   local order_delta = current_orders - last_orders
   local floor_radius = clamp(clamp_min, clamp_max, data.floor_radius or clamp_min)

   -- Update anti-oscillation floor:
   -- When stationary and consuming work, any radius that already had < grow_limit orders
   -- still has < grow_limit orders, so never shrink back into it.
   -- Unlock the floor when the player moves or when new work appears inside the current radius.
   if move_dist > 0.05 then
      floor_radius = math.max(clamp_min, floor_radius - move_dist * config.move_floor_decay)
   end

   local new_work_spike = (applied_radius <= last_applied_radius)
      and (order_delta >= math.max(4, math.floor(effective_cap * 0.3)))

   if new_work_spike or (current_orders == 0 and applied_radius >= clamp_max) then
      floor_radius = clamp_min
   end

   if current_orders == 0 and applied_radius >= clamp_min + 6 then
      data.from_idle_scan = true
   elseif current_orders > 0 and current_orders <= shrink_limit then
      data.from_idle_scan = false
   end

   -- Decide GROW, SHRINK, or STAY
   if current_orders < grow_limit then
      -- GROW: Not enough orders in current applied_radius to keep available robots busy.
      -- Record that applied_radius was too small so we don't oscillate back down to it.
      if current_orders == 0 and applied_radius >= clamp_max then
         floor_radius = clamp_min
      else
         floor_radius = math.max(floor_radius, math.min(clamp_max, applied_radius + 1))
      end

      local shortage = (grow_limit - current_orders) / math.max(1, grow_limit)
      local radius_scale = 1.0
      if current_orders > 0 then
         -- Slow down gently at larger radii when already touching work so we don't overshoot
         radius_scale = math.max(1.0, math.sqrt(data.radius / 8))
      else
         -- Scan empty space briskly even at larger radii
         radius_scale = 1.0 + (data.radius / 60) * 0.35
      end

      local speed = (config.base_grow_speed + (config.max_grow_speed - config.base_grow_speed) * (shortage * shortage)) / radius_scale

      -- One-way brake: if orders are already jumping up, damp growth so we settle smoothly
      if order_delta > 0 then
         local rise_ratio = order_delta / math.max(1, grow_limit)
         local brake = math.max(0.15, 1.0 - rise_ratio * 0.85)
         speed = speed * brake
      end

      local step = speed * delta_time + (move_dist * config.move_speed_factor * shortage)
      local max_step = config.max_grow_speed * delta_time + (move_dist * config.move_speed_factor)
      step = math.min(step, max_step)

      data.radius = math.max(data.radius, floor_radius) + step

   elseif current_orders > shrink_limit then
      -- SHRINK: More queued orders than needed. Pull back toward floor_radius, but never below it.
      if data.radius > floor_radius then
         local overload = math.min(2.0, (current_orders - shrink_limit) / math.max(1, effective_cap))
         local speed = config.base_shrink_speed + (config.max_shrink_speed - config.base_shrink_speed) * (overload / 2.0)

         -- One-way brake: once shrinking starts cutting into the work (order_delta < 0),
         -- slow down so we land inside the STAY band instead of undershooting.
         if order_delta < 0 then
            data.from_idle_scan = false
            local drop_ratio = (-order_delta) / math.max(1, (current_orders - shrink_limit) + (-order_delta))
            local brake = math.max(0.2, 1.0 - drop_ratio * 0.8)
            speed = speed * brake
         end

         local step = speed * delta_time + (move_dist * config.move_speed_factor)
         local max_step = config.max_shrink_speed * delta_time + (move_dist * config.move_speed_factor)
         step = math.min(step, max_step)

         -- If closing in from a wide idle scan and orders haven't started dropping yet, close the empty outer gap quickly
         if data.from_idle_scan and order_delta >= -2 then
            step = math.max(step, (data.radius - floor_radius) * 0.35)
         elseif move_dist < 0.2 and (data.radius - floor_radius) <= 3.0 then
            -- When stationary and trimming near floor_radius, step at most 1 tile at a time to lock onto the exact ring
            step = math.min(step, 1.0)
         end

         data.radius = math.max(floor_radius, data.radius - step)
      else
         data.from_idle_scan = false
         data.radius = floor_radius
      end

   else
      -- STAY: Orders are in the sweet spot [grow_limit, shrink_limit].
      -- Hold the currently applied integer radius steady with zero drift.
      data.from_idle_scan = false
      data.radius = applied_radius
   end

   -- Low roboport energy protection (< 20% internal buffer)
   if get_grid_any_inactive(grid) then
      local shrink = config.max_shrink_speed * delta_time
      data.radius = data.radius - shrink
      floor_radius = math.min(floor_radius, math.max(clamp_min, math.floor(data.radius)))
   end

   -- Clamp and apply with hysteresis to prevent boundary chatter between adjacent integers
   floor_radius = clamp(clamp_min, clamp_max, floor_radius)
   data.radius = clamp(clamp_min, clamp_max, data.radius)

   local new_applied = applied_radius
   if data.radius >= applied_radius + 0.55 then
      new_applied = math.floor(data.radius + 0.45)
   elseif data.radius <= applied_radius - 0.55 then
      new_applied = math.ceil(data.radius - 0.45)
   end
   new_applied = clamp(clamp_min, clamp_max, new_applied)

   set_grid_radius(grid, new_applied)

   -- Save state
   data.last_applied_radius = applied_radius
   data.applied_radius = new_applied
   data.floor_radius = floor_radius
   data.last_orders = current_orders
   data.last_error = grow_limit - current_orders

   storage.player_data = storage.player_data or {}
   storage.player_data[player.index] = data

   if config.debug then
      drawDebugVisuals(player, delta_time, new_applied, max_robots, data.avg_available_robots, current_orders)
   end
end


local prepare_done = false

local function restore_grid(grid)
   if not (grid and grid.valid) then return 0 end
   local pending, restored = {}, 0
   for _, eq in pairs(grid.equipment) do
      if eq.type == "roboport-equipment" and string.find(eq.name, "%-reduced%-%d+$") then
         pending[#pending + 1] = {
            pos = { x = eq.position.x, y = eq.position.y }, energy = eq.energy, quality = eq.quality.name, name = eq.name,
            original = eq.prototype.take_result.place_as_equipment_result.name
         }
      end
   end
   for _, eq in pairs(pending) do
      grid.take { position = eq.pos }
      local put = grid.put { name = eq.original, position = eq.pos, quality = eq.quality }
      if not put then put = grid.put { name = eq.name, position = eq.pos, quality = eq.quality } end
      if put then put.energy = eq.energy end
      if put and put.name == eq.original then restored = restored + 1 end
   end
   return restored
end

local function restore_inventory(inventory, restored)
   if not inventory then return restored end
   for i = 1, #inventory do
      local stack = inventory[i]
      if stack.valid_for_read then restored = restored + restore_grid(stack.grid) end
   end
   return restored
end

local function restore_all()
   local restored = 0
   for _, player in pairs(game.players) do
      if player.cursor_stack and player.cursor_stack.valid_for_read then restored = restored + restore_grid(player.cursor_stack.grid) end
      for _, id in pairs(defines.inventory) do restored = restore_inventory(player.get_inventory(id), restored) end
   end
   for _, surface in pairs(game.surfaces) do
      for _, entity in pairs(surface.find_entities()) do
         restored = restored + restore_grid(entity.grid)
         if entity.type == "item-entity" and entity.stack and entity.stack.valid_for_read then
            restored = restored + restore_grid(entity.stack.grid)
         end
         for _, id in pairs(defines.inventory) do restored = restore_inventory(entity.get_inventory(id), restored) end
      end
   end
   return restored
end

local function tick()
   if settings.global[def.prepare_for_uninstallation_setting].value then
      if not prepare_done then
         local restored = restore_all()
         prepare_done = true
         game.print("Robots Build Closest First: Preparation successful. Restored " .. restored .. " personal roboport(s). Save the game, then uninstall.", {1, 0.85, 0.2})
      elseif game.tick % 500 == 0 then
         game.print("Robots Build Closest First: Prepare for uninstallation is ON. The mod will not work as intended. Turn this setting off, or SAVE your game and uninstall the mod now.", {1, 0.3, 0.2})
      end
      return
   end
   prepare_done = false

   -- get list of players
   local players = game.connected_players
   local player_count = #players
   if player_count == 0 then return end

   local cycle_length = player_count + config.update_pause

   -- get current step in cycle
   local step = game.tick % cycle_length

   -- check if update or pause phase
   if step < player_count then
      -- UPDATE PHASE
      local player = players[step + 1]

      if player and player.valid then
         local deltaTime = cycle_length
         
         updatePlayer(player, deltaTime)
         
      end

   else
      -- PAUSE PHASE
      -- do nothing
   end
end






local SHORTCUT = "shortcut-toggle-robots-build-closest-first"

local function toggle_shortcut(e)
   local p = game.get_player(e.player_index)
   local new_state = not p.is_shortcut_toggled(SHORTCUT)
   p.set_shortcut_toggled(SHORTCUT, new_state) -- <- makes it yellow when true
end


local function shortcutToggle(e)
   if e.prototype_name == SHORTCUT or e.input_name == "input-toggle-robots-build-closest-first" then
      toggle_shortcut(e)
   end
end


local function setup()
   if not storage.player_data then
      storage.player_data = {}
   end
end





script.on_event({ defines.events.on_tick }, tick)

script.on_event(defines.events.on_lua_shortcut, shortcutToggle)

script.on_event("input-toggle-robots-build-closest-first", shortcutToggle)

script.on_init(setup)

commands.add_command("rbcf_clear_data", "clears the storage for the mod robots build closest first", function(command)
   storage.player_data = {}
   game.print("(Robots_Build_Closest_First MOD) Data cleared")
end)

script.on_configuration_changed(function(data)

   if data.mod_changes["Robots_Build_Closest_First"] then
      
      if storage.player_data then
         for player_index, p_data in pairs(storage.player_data) do
            
            local player_name = game.players[player_index] and game.players[player_index].name or "unknownPlayerName"

            if p_data.radius == nil then
               p_data.radius = def.minimum_radius_table[settings.get_player_settings(player_name)[def.minimum_radius_setting].value]
               game.print("(Robots_Build_Closest_First MOD) Migrated player " .. player_name .. ": Added radius")
            end

            if p_data.no_orders_streak == nil then
               p_data.no_orders_streak = 0
               game.print("(Robots_Build_Closest_First MOD) Migrated player " .. player_name .. ": Added no_orders_streak")
            end

            if p_data.last_error == nil then
               p_data.last_error = 0
               game.print("(Robots_Build_Closest_First MOD) Migrated player " .. player_name .. ": Added last_error")
            end

            if p_data.avg_available_robots == nil then
               p_data.avg_available_robots = 0
               game.print("(Robots_Build_Closest_First MOD) Migrated player " .. player_name .. ": Added avg_available_robots")
            end
         end
      end
   end
end)


local shortcut_name = "shortcut-toggle-robots-build-closest-first"

script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if player then
        player.set_shortcut_toggled(shortcut_name, true)
    end
end)

script.on_configuration_changed(function(event)
    if event.mod_changes and event.mod_changes["Robots_Build_Closest_First"] then
        for _, player in pairs(game.players) do
            player.set_shortcut_toggled(shortcut_name, true)
        end
    end
end)