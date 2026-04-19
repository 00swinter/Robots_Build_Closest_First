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

   for _, eq in next, grid.equipment do
      if eq.type == "roboport-equipment" then
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
   update_pause = 10,          -- How many empty ticks between updates
   min_radius = 3,
   snap_back_threshold = 300,

   -- CONTROL SETTINGS
   change_rate = 0.003,  --how much it grows
   damping_factor = 1.0,      -- how much it slows down
   max_expansion_speed = 0.5,   -- speedlimit

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
      radius = config.min_radius,
      no_orders_streak = 0,
      last_error = 0,  -- Tracks previous error for the "Brake" logic
      avg_available_robots = 0 -- for debugging
   }

   -- robot order metrics
   local current_orders = get_player_all_robot_order_count(player)
   local max_robots = get_player_real_robot_limit(player)
   local available_robots = get_player_available_robots(player)
   local max_minus_charging = get_player_max_minus_charging(player)

   local available_robots_inventory = player.character.logistic_network.available_construction_robots
   -- calculate moving average
   if data.avg_available_robots == 0 then
      data.avg_available_robots = available_robots_inventory
   else
      local smoothing = math.min(1, 0.003 * delta_time)
      data.avg_available_robots = data.avg_available_robots + (available_robots_inventory - data.avg_available_robots) * smoothing
      --game.print("Avg Available Robots: " .. math.floor(player.character.logistic_network.available_construction_robots))
   end

   -- snap back logic
   if current_orders == 0 and available_robots >= max_robots / 4 and math.abs(data.radius - radius_limit_setting) < 4 then
      if data.no_orders_streak <= config.snap_back_threshold then
         data.no_orders_streak = data.no_orders_streak + delta_time
      end
   else
      if data.no_orders_streak > config.snap_back_threshold then
         data.radius = config.min_radius
         data.last_error = 0 -- reset error on snap back
      end
      data.no_orders_streak = 0
   end

   -- PID controller logic for radius adjustment
   local charging_robots_diff = max_robots - max_minus_charging
   local desired_orders = max_robots - (charging_robots_diff * 0.5) * 1.7
   desired_orders = math.floor(desired_orders + 0.5)

   local current_error = desired_orders - current_orders
   local allowed_error = desired_orders * 0.2

   if math.abs(current_error) > allowed_error then
      
      local sensitivity = config.change_rate / math.max(1, (data.radius / 6))
      
      local p_term = current_error * sensitivity

      local error_delta = (current_error - data.last_error) / delta_time
      local d_term = error_delta * (sensitivity * config.damping_factor)

      local adjustment = (p_term + d_term) * delta_time

      local max_change = config.max_expansion_speed * delta_time
      adjustment = clamp(-max_change, max_change, adjustment)

      data.radius = data.radius + adjustment
   end
   
   -- save
   data.last_error = current_error

   if get_grid_any_inactive(grid) then
      data.radius = data.radius - (config.change_rate * 35) * delta_time
   end

   -- apply changes
   data.radius = clamp(3, radius_limit_setting, data.radius)
   set_grid_radius(grid, data.radius)

   storage.player_data = storage.player_data or {}
   storage.player_data[player.index] = data

   if config.debug then
      drawDebugVisuals(player, delta_time, data.radius, max_robots, data.avg_available_robots, current_orders)
   end
   

end


local function tick()

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
               p_data.radius = config.min_radius
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