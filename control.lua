

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
   
   local order_count = 0 

   for _,entity in next, logistic.robots do
      order_count = order_count + #entity.robot_order_queue
   end

   return order_count 

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
   update_interval = 5,
   order_buffer = 50,
   min_radius = 3
}

local ctrl = {
   lerped_radius = config.min_radius,
   radius = config.min_radius,
   velocity = 0,
   no_orders_streak = 0
}


local function newTick()
   if game.tick % config.update_interval ~= 0 then return end


   local p = game.players[1]
   if not (p and p.valid and p.character and p.character.valid) then return end

   local grid = p.character.grid
   if not grid then return end

   local maxR = get_grid_max_radius(grid) or 0
   if maxR <= 0 then
      set_grid_radius(grid, 0)
      return
   end

   local current_orders = get_player_all_robot_order_count(p)
   local max_robots = get_player_real_robot_limit(p)



   if current_orders == 0 then
      ctrl.no_orders_streak = ctrl.no_orders_streak + 1
      --game.print("no orders streak: "..ctrl.no_orders_streak)
   else
      if ctrl.no_orders_streak > 90 then
         ctrl.radius = config.min_radius
         game.print("reset radius to min")
      end
      ctrl.no_orders_streak = 0
   end

   --information
   -- allow error for desired order level -> bigger radius bigger error threshold allowed

   local desired_order = max_robots * 1

   local order_error = desired_order - current_orders

   --clamp order_error
   order_error = clamp(-40, 40, order_error)

   --game.print("order_error: "..order_error)

   if math.abs(order_error) > 20 then
      ctrl.radius = ctrl.radius + (order_error * 0.005)
   end

   
   
   --clamp
   ctrl.radius = clamp(3,maxR, ctrl.radius)

   --lerp
   ctrl.lerped_radius = lerp(ctrl.lerped_radius, ctrl.radius, 0.08)

   set_grid_radius(grid, ctrl.lerped_radius)
   --draw_area

   local area = {
      { p.position.x - ctrl.radius, p.position.y - ctrl.radius },
      { p.position.x + ctrl.radius, p.position.y + ctrl.radius }
   }
   local area_lerped = {
      { p.position.x - ctrl.lerped_radius, p.position.y - ctrl.lerped_radius },
      { p.position.x + ctrl.lerped_radius, p.position.y + ctrl.lerped_radius }
   }

   rendering.draw_rectangle {
      surface = p.surface,
      left_top = area[1],
      right_bottom = area[2],
      color = { 1, 0.2, 0.2 },
      time_to_live = config.update_interval
   }

   rendering.draw_rectangle {
      surface = p.surface,
      left_top = area_lerped[1],
      right_bottom = area_lerped[2],
      color = { 1,1,1 },
      time_to_live = config.update_interval
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





script.on_event({ defines.events.on_tick }, newTick)



script.on_event(defines.events.on_lua_shortcut, shortcutToggle)

script.on_event("input-toggle-robots-build-closest-first", shortcutToggle)
