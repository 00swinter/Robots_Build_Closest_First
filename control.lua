local def = require("defines")
local SHORTCUT = "shortcut-toggle-robots-build-closest-first"
local prepare_done = false

local config = {
   update_pause = 10,
   grow_ratio = 0.85,        -- Grow when orders < 85% of non-charging robots
   shrink_ratio = 1.35,      -- Shrink when orders > 135% of robot capacity
   grow_speed = 0.22,        -- Max expansion speed (tiles per tick)
   shrink_speed = 0.20,      -- Max shrink speed (tiles per tick)
   move_decay = 1.5,         -- How fast anti-oscillation floor drops when player moves
   debug = true
}

local function clamp(min, max, val)
   return math.max(min, math.min(val, max))
end

local function get_eq_base(eq)
   return eq.prototype.take_result.place_as_equipment_result
end

local function get_eq_max_radius(eq)
   return math.floor(get_eq_base(eq).logistic_parameters.construction_radius)
end

local function get_grid_max_radius(grid)
   local sumsq = 0
   for _, eq in pairs(grid.equipment) do
      if eq.type == "roboport-equipment" then
         local r = get_eq_max_radius(eq)
         sumsq = sumsq + r * r
      end
   end
   return math.floor(math.sqrt(sumsq) + 0.5)
end

local function get_grid_any_inactive(grid)
   for _, eq in pairs(grid.equipment) do
      if eq.type == "roboport-equipment" and eq.energy < eq.max_energy * 0.2 then
         return true
      end
   end
   return false
end

local function set_eq_radius(grid, eq, desired_radius)
   local r = clamp(0, get_eq_max_radius(eq), math.floor(desired_radius + 0.5))
   local variant_name = get_eq_base(eq).name .. "-reduced-" .. r
   if eq.name == variant_name then return end

   local pos = eq.position
   local energy = eq.energy
   local quality = eq.quality.name

   grid.take { position = pos }
   local new_eq = grid.put { name = variant_name, position = pos, quality = quality }
   if new_eq then
      new_eq.energy = energy
   else
      game.print("(Robots_Build_Closest_First MOD) could not swap Roboport")
   end
end

local function set_grid_radius(grid, desired_radius)
   local needed_area = math.max(0, desired_radius) ^ 2 * 4

   for _, eq in pairs(grid.equipment) do
      if eq.type == "roboport-equipment" then
         local eq_max_area = get_eq_max_radius(eq) ^ 2 * 4
         local use_area = math.min(needed_area, eq_max_area)
         needed_area = needed_area - use_area

         local eq_radius = math.sqrt(use_area) / 2
         set_eq_radius(grid, eq, eq_radius)
      end
   end
end

local function get_order_count(logistic)
   local count = 0
   for _, robot in pairs(logistic.robots) do
      if robot.valid and robot.robot_order_queue then
         count = count + #robot.robot_order_queue
      end
   end
   return count
end

local function drawDebugVisuals(player, dt, radius, max_robots, current_orders)
   local p = player.position
   local s = player.surface

   rendering.draw_rectangle {
      color = { 1, 1, 1, 1 },
      width = 2,
      filled = false,
      left_top = { p.x - radius, p.y - radius },
      right_bottom = { p.x + radius, p.y + radius },
      surface = s,
      time_to_live = dt
   }

   local lines = {
      string.format("Radius: %d", radius),
      string.format("MaxRobots: %d", max_robots),
      string.format("Current Orders: %d", current_orders)
   }
   for i, text in ipairs(lines) do
      rendering.draw_text {
         text = text,
         scale = 2,
         surface = s,
         target = { x = p.x, y = p.y - 7 - i },
         color = { 1, 1, 1 },
         time_to_live = dt
      }
   end
end

local function updatePlayer(player, dt)
   local char = player.character
   if not (char and char.valid) then return end

   local grid = char.grid
   local logistic = char.logistic_network
   if not (grid and grid.valid and logistic and logistic.valid) then return end

   local max_radius = get_grid_max_radius(grid)
   if max_radius <= 0 then
      set_grid_radius(grid, 0)
      return
   end

   -- Read player settings
   local p_settings = settings.get_player_settings(player)
   local limit = def.limited_radius_table[p_settings[def.limited_radius_setting].value]
   if limit == 0 then limit = max_radius end

   local min_radius = def.minimum_radius_table[p_settings[def.minimum_radius_setting].value]
   local max_allowed = math.max(limit, min_radius)

   -- Handle mod toggled OFF
   if not player.is_shortcut_toggled(SHORTCUT) then
      local off_radius = p_settings[def.use_limit_when_off_setting].value and limit or max_radius
      set_grid_radius(grid, off_radius)
      return
   end

   -- Load player state
   storage.player_data = storage.player_data or {}
   local data = storage.player_data[player.index] or {
      radius = min_radius,
      floor_radius = min_radius
   }

   -- Gather robot & order metrics
   local orders = get_order_count(logistic)
   local max_robots = math.min(logistic.all_construction_robots, logistic.robot_limit)
   local cell = logistic.cells[1]
   local charging = cell and (cell.charging_robot_count + cell.to_charge_robot_count) or 0
   local active_limit = max_robots - charging

   -- Measure player movement since last update
   local pos = player.position
   local move_dist = 0
   if data.last_pos then
      move_dist = math.sqrt((pos.x - data.last_pos.x) ^ 2 + (pos.y - data.last_pos.y) ^ 2)
   end
   data.last_pos = { x = pos.x, y = pos.y }

   -- Calculate GROW and SHRINK thresholds
   local grow_threshold = math.floor(active_limit * config.grow_ratio + 0.5)
   local shrink_threshold = math.max(max_robots + 3, math.ceil(max_robots * config.shrink_ratio))

   -- Anti-oscillation floor:
   -- Prevents shrinking back into a radius that just had too few orders.
   -- Decays as the player moves, and resets when all work is finished.
   local current_int_radius = math.floor(data.radius + 0.5)
   local floor_radius = clamp(min_radius, max_allowed, data.floor_radius or min_radius)

   if move_dist > 0 then
      floor_radius = math.max(min_radius, floor_radius - move_dist * config.move_decay)
   end
   if orders == 0 and current_int_radius >= max_allowed then
      floor_radius = min_radius
   end

   -- Decide: GROW, SHRINK, or STAY
   if get_grid_any_inactive(grid) then
      -- Low roboport power: shrink to save energy
      data.radius = data.radius - config.shrink_speed * dt
      floor_radius = min_radius

   elseif orders < grow_threshold then
      -- GROW: Not enough orders to keep non-charging robots busy
      floor_radius = math.max(floor_radius, current_int_radius + 1)

      local shortage = (grow_threshold - orders) / math.max(1, grow_threshold)
      local step = (config.grow_speed * shortage * dt) + (move_dist * 0.5)
      data.radius = math.max(data.radius, floor_radius) + step

   elseif orders > shrink_threshold then
      -- SHRINK: Too many queued orders, pull back down to floor_radius
      local overload = math.min(1, (orders - shrink_threshold) / math.max(1, max_robots))
      local step = (config.shrink_speed * overload * dt) + (move_dist * 0.5)
      data.radius = math.max(floor_radius, data.radius - step)

   else
      -- STAY: Orders are inside [grow_threshold, shrink_threshold]
      data.radius = current_int_radius
   end

   -- Clamp and apply
   data.floor_radius = clamp(min_radius, max_allowed, floor_radius)
   data.radius = clamp(min_radius, max_allowed, data.radius)

   local applied_radius = math.floor(data.radius + 0.5)
   set_grid_radius(grid, applied_radius)

   storage.player_data[player.index] = data

   if config.debug then
      drawDebugVisuals(player, dt, applied_radius, max_robots, orders)
   end
end

local function restore_grid(grid)
   if not (grid and grid.valid) then return 0 end
   local pending, restored = {}, 0

   for _, eq in pairs(grid.equipment) do
      if eq.type == "roboport-equipment" and string.find(eq.name, "%-reduced%-%d+$") then
         pending[#pending + 1] = {
            pos = eq.position,
            energy = eq.energy,
            quality = eq.quality.name,
            name = eq.name,
            original = get_eq_base(eq).name
         }
      end
   end

   for _, eq in pairs(pending) do
      grid.take { position = eq.pos }
      local put = grid.put { name = eq.original, position = eq.pos, quality = eq.quality }
               or grid.put { name = eq.name, position = eq.pos, quality = eq.quality }
      if put then put.energy = eq.energy end
      if put and put.name == eq.original then restored = restored + 1 end
   end
   return restored
end

local function restore_inventory(inv, restored)
   if not inv then return restored end
   for i = 1, #inv do
      if inv[i].valid_for_read then
         restored = restored + restore_grid(inv[i].grid)
      end
   end
   return restored
end

local function restore_all()
   local restored = 0
   for _, p in pairs(game.players) do
      if p.cursor_stack and p.cursor_stack.valid_for_read then
         restored = restored + restore_grid(p.cursor_stack.grid)
      end
      for _, id in pairs(defines.inventory) do
         restored = restore_inventory(p.get_inventory(id), restored)
      end
   end
   for _, surface in pairs(game.surfaces) do
      for _, entity in pairs(surface.find_entities()) do
         restored = restored + restore_grid(entity.grid)
         if entity.type == "item-entity" and entity.stack and entity.stack.valid_for_read then
            restored = restored + restore_grid(entity.stack.grid)
         end
         for _, id in pairs(defines.inventory) do
            restored = restore_inventory(entity.get_inventory(id), restored)
         end
      end
   end
   return restored
end

script.on_event(defines.events.on_tick, function()
   if settings.global[def.prepare_for_uninstallation_setting].value then
      if not prepare_done then
         prepare_done = true
         game.print("Robots Build Closest First: Preparation successful. Restored " .. restore_all() .. " personal roboport(s). Save the game, then uninstall.", { 1, 0.85, 0.2 })
      elseif game.tick % 500 == 0 then
         game.print("Robots Build Closest First: Prepare for uninstallation is ON. The mod will not work as intended. Turn this setting off, or SAVE your game and uninstall the mod now.", { 1, 0.3, 0.2 })
      end
      return
   end
   prepare_done = false

   local players = game.connected_players
   local player_count = #players
   if player_count == 0 then return end

   local cycle_length = player_count + config.update_pause
   local step = game.tick % cycle_length

   if step < player_count then
      local player = players[step + 1]
      if player and player.valid then
         updatePlayer(player, cycle_length)
      end
   end
end)

local function shortcutToggle(e)
   if e.prototype_name == SHORTCUT or e.input_name == "input-toggle-robots-build-closest-first" then
      local p = game.get_player(e.player_index)
      if p then
         p.set_shortcut_toggled(SHORTCUT, not p.is_shortcut_toggled(SHORTCUT))
      end
   end
end

script.on_event(defines.events.on_lua_shortcut, shortcutToggle)
script.on_event("input-toggle-robots-build-closest-first", shortcutToggle)

script.on_init(function()
   storage.player_data = storage.player_data or {}
end)

script.on_event(defines.events.on_player_created, function(e)
   local p = game.get_player(e.player_index)
   if p then p.set_shortcut_toggled(SHORTCUT, true) end
end)

commands.add_command("rbcf_clear_data", "clears the storage for the mod robots build closest first", function()
   storage.player_data = {}
   game.print("(Robots_Build_Closest_First MOD) Data cleared")
end)

script.on_configuration_changed(function(data)
   if data.mod_changes and data.mod_changes["Robots_Build_Closest_First"] then
      for _, p in pairs(game.players) do
         p.set_shortcut_toggled(SHORTCUT, true)
      end
   end
end)
