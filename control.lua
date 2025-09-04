local function get_eq_max_radius(eq)
   return eq.prototype.take_result.place_as_equipment_result.logistic_parameters.construction_radius
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




local function get_player_available_robots(player)
   local logistic = player.character.logistic_network
   local cell = logistic.cells[1]

   local robots_limit = logistic.robot_limit
   local robots_all = logistic.all_construction_robots

   local real_limit = math.min(robots_all, robots_limit)

   local ava = logistic.available_construction_robots
   --game.print("--------------- "..ava)

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

local function get_player_robots_ready_to_start(player)
   local logistic = player.character.logistic_network
   local cell = logistic.cells[1]

   local robots_limit = logistic.robot_limit
   local robots_available = logistic.available_construction_robots
   local robots_all = logistic.all_construction_robots




   --local charging = cell.charging_robot_count + cell.to_charge_robot_count

   --local avail_temp = robots_limit - charging

   --return avail_temp

   local robots_real_available = robots_limit - (robots_all - robots_available)
   return math.min(robots_available, robots_real_available)
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
   grid.take { position = eq_pos }
   local new_eq = grid.put { name = variant_name, position = eq_pos }
   if new_eq then
      new_eq.energy = eq_energy
   else
      game.print(
         "ERROR in mod Robots-Build-Closest-First: 'could not swap Roboport'... pls report it on the mod portal.")
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


--adding a new valueto the buffer while also returning the average of the ringbuffer
local function moving_average_ringbuffer_push(rb, value)
   local next_idx = (rb.index % rb.max) + 1
   local old = rb.buffer[next_idx] or 0
   rb.buffer[next_idx] = value
   rb.sum = rb.sum - old + value
   rb.index = next_idx
   return (rb.sum / rb.max) or value
end

local function lerp(a, b, t)
   t = math.max(0, math.min(t, 1))
   return a + t * (b - a)
end

local function clamp(min, max, value)
   return math.max(min, math.min(value, max))
end
--working values
local config = {
   update_interval = 10,
   order_buffer = 50,
   min_radius = 3,
   change_rate = 0.0025,
   snap_back_threshold = 100
}

local dataOLD = {
   radius = config.min_radius,
   velocity = 0,
   no_orders_streak = 0
}


local function newTick()
   if game.tick % config.update_interval ~= 0 then return end


   local connected_players = game.connected_players
   if #connected_players == 0 then return end




   --has player
   local player = game.players[1]
   if not (player and player.valid and player.character and player.character.valid) then return end



   --has grid
   local grid = player.character.grid
   if not (grid and grid.valid) then return end

   --has roboport

   local logistic = player.character.logistic_network
   if not (logistic and logistic.valid) then return end




   local max_Radius = get_grid_max_radius(grid) or 0
   if max_Radius <= 0 then
      set_grid_radius(grid, 0)
      return
   end


   --is shortcut enabled

   if not player.is_shortcut_toggled("shortcut-toggle-robots-build-closest-first") then
      set_grid_radius(grid, max_Radius)
      return
   end

   --SETTINGS
   -- limit radius 0 = no limit
   -- use limit when mod is toggled off (else is using max radius)
   -- updaterate? not realy needed


   --load / init storage
   local data = storage.player_data[1] or
       {
          radius = config.min_radius,
          velocity = 0,
          no_orders_streak = 0
       }

   local current_orders = get_player_all_robot_order_count(player)
   local max_robots = get_player_real_robot_limit(player)
   local available_robots = get_player_available_robots(player)

   --update streak
   if current_orders == 0 and available_robots >= max_robots / 4 then
      data.no_orders_streak = data.no_orders_streak + config.update_interval
      --game.print("no orders streak: "..data.no_orders_streak)
   else
      if data.no_orders_streak > config.snap_back_threshold then
         data.radius = config.min_radius
         game.print("reset radius to min")
      end
      data.no_orders_streak = 0
   end

   --information
   -- allow error for desired order level -> bigger radius bigger error threshold allowed

   local radius_progress = data.radius / max_Radius

   local desired_orders = max_robots * 1.3 -- + (radius_progress * 8)


   desired_orders = math.floor(desired_orders + 0.5)

   local order_error = desired_orders - current_orders

   local allowed_error = desired_orders * 0.2

   --clamp order_error
   --order_error = clamp(-allowed_error-1, 1+allowed_error, order_error)

   --game.print("order_error: "..order_error)

   if math.abs(order_error) > allowed_error then
      data.radius = data.radius + order_error * (config.change_rate / (data.radius / 7)) * config.update_interval
   end


   --clamp
   data.radius = clamp(3, max_Radius, data.radius)

   --lerp
   --data.lerped_radius = lerp(data.lerped_radius, data.radius, config.lerp_rate * config.update_interval)

   set_grid_radius(grid, data.radius)

   --save data

   storage.player_data[1] = data

   --debug drawing

   local area = {
      { player.position.x - data.radius, player.position.y - data.radius },
      { player.position.x + data.radius, player.position.y + data.radius }
   }
   --local area_lerped = {
   --   { player.position.x - data.lerped_radius, player.position.y - data.lerped_radius },
   --   { player.position.x + data.lerped_radius, player.position.y + data.lerped_radius }
   --}

   rendering.draw_rectangle {
      surface = player.surface,
      left_top = area[1],
      right_bottom = area[2],
      color = { 0, 0.1, 0.8 },
      time_to_live = config.update_interval,
      width = 5
   }
   --rendering.draw_rectangle {
   --   surface = player.surface,
   --   left_top = area_lerped[1],
   --   right_bottom = area_lerped[2],
   --   color = { 1, 1, 1 },
   --   time_to_live = config.update_interval,
   --   width = 5
   --}

   rendering.draw_text {
      text = { "", "current_orders: " .. current_orders },
      surface = player.surface,
      target = {
         player.position.x - 2,
         player.position.y - 8
      },
      scale = 3,
      color = { 1, 1, 1 },
      time_to_live = config.update_interval,
   }

   rendering.draw_text {
      text = { "", "desired_orders: " .. desired_orders },
      surface = player.surface,
      target = {
         player.position.x - 2,
         player.position.y - 9
      },
      scale = 3,
      color = { 1, 1, 1 },
      time_to_live = config.update_interval,
   }


   local order_error_color = order_error > 0 and { 0.7, 1, 0.7 } or { 1, 0.7, 0.7 }
   rendering.draw_text {
      text = { "", "order_error: " .. order_error },
      surface = player.surface,
      target = {
         player.position.x - 2,
         player.position.y - 10
      },
      scale = 3,
      color = order_error_color,
      time_to_live = config.update_interval,
   }

   rendering.draw_text {
      text = { "", "allowed_error: " .. allowed_error },
      surface = player.surface,
      target = {
         player.position.x - 2,
         player.position.y - 11
      },
      scale = 3,
      color = { 1, 1, 1 },
      time_to_live = config.update_interval,
   }
end






local SHORTCUT = "shortcut-toggle-robots-build-closest-first"

local function toggle_shortcut(e)
   local p = game.get_player(e.player_index)
   local new_state = not p.is_shortcut_toggled(SHORTCUT)
   p.set_shortcut_toggled(SHORTCUT, new_state) -- <- makes it yellow when true
end


local function shortcutToggle(e)
   if e.prototype_name == SHORTCUT then
      game.print("toggle!!!!")
      toggle_shortcut(e)
   end
end


local function setup()
   if not storage.player_data then
      storage.player_data = {}
   end
end





script.on_event({ defines.events.on_tick }, newTick)

script.on_event(defines.events.on_lua_shortcut, shortcutToggle)

script.on_event("input-toggle-robots-build-closest-first", shortcutToggle)

script.on_init(setup)

--script.on_configuration_changed
