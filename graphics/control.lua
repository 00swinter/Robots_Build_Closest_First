-- storage == global


local function replace_roboport(grid, old, new_name)
   local pos = old.position
   local energy = old.energy
   grid.take { position = old.position }
   local new = grid.put { name = new_name, position = pos }
   if new then
      new.energy = energy
   else
      game.print("Error in closest-first: could not replace roboport. Please report it on the mod page.")
   end
end


local function restore(g)
   for _, eq in next, g.equipment do
      if eq.type == "roboport-equipment" and eq.prototype.order == "abctest" then
         replace_roboport(g, eq, eq.prototype.take_result.name)
      end
   end
end


local function get_eq_max_radius(eq)
   return eq.prototype.take_result.place_as_equipment_result.logistic_parameters.construction_radius
end

local function get_eq_max_area(eq)
   local max_radius = get_eq_max_radius(eq)
   return max_radius * max_radius * 4
end




local function find_close_entities_swinter(player, area)
   return player.surface.find_entities_filtered { area = area, force = { player.force, "neutral" } }
end

local function find_close_entities(player)
   local logistic = player.character.logistic_network
   local grid = player.character.grid
   if logistic and logistic.all_construction_robots > 0 and logistic.robot_limit > 0 and grid then
      local limit_area = 10 --d.range_setting_table[settings.get_player_settings(player)[d.limit_area_setting].value]
      local original_range = 2 * get_original_range(grid)
      if limit_area > 0 then
         original_range = math.min(original_range, limit_area)
      end
      original_range = original_range / 2
      if original_range <= 0 then return nil end
      local search_area_radius = 5 --d.range_setting_table[settings.global[d.search_area_setting].value] / 2;
      if search_area_radius <= 0 then search_area_radius = original_range end

      -- Search the smallest of the original range and the setting
      local radius = math.min(original_range, search_area_radius)
      local pos = player.position;
      local px = pos.x
      local py = pos.y -- I'm just unrolling everything now...
      local area = {
         { px - radius, py - radius },
         { px + radius, py + radius } }
      return player.surface.find_entities_filtered { area = area, force = { player.force, "neutral" } }
   end
   return nil
end



local function get_eq_radius(eq)
   return eq.prototype.take_result.place_as_equipment_result.logistic_parameters.construction_radius
end


local function get_grid_radius(grid)
   -- the area of each individual roboport is added to the total area.
   -- we then take the squareroot of the total area to get the edge -> /2 -> radius.
   local area = 0
   for _, eq in pairs(grid.equipment) do
      if eq.type == "roboport-equipment" then
         local radius = get_eq_radius(eq) * 2 -- the radius is half the edge length

         area = area + (radius * radius)
      end
   end
   game.print("total area: " .. area)
   local area_edge = math.sqrt(area)
   game.print("area_edge: " .. area_edge)
   -- /2 because we need the radius
   return math.floor((area_edge / 2) + 0.5) -- round
end

local function get_grid_area(grid)
   local r = get_grid_radius(grid)
   return r * r
end

local function get_eq_robot_limit(eq)
   return eq.prototype.logistic_parameters.robot_limit
end

local function get_grid_robot_limit(grid)
   local limit = 0
   for _, eq in next, grid.equipment do
      if eq.type == "roboport-equipment" then
         limit = limit + get_eq_robot_limit(eq)
      end
   end
   return limit
end

local function get_real_robot_limit(player)
   local logistic = player.character.logistic_network
   local robots_limit = logistic.robot_limit
   local robots_available = logistic.available_construction_robots
   return math.min(robots_available, robots_limit)
end

local function get_player_real_available_robots(player)
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


local function tick()
   if true then
      return
   end
   --only firee every 10 ticks
   if game.tick % 10 ~= 0 then
      --return
   end
   game.print("tick");

   --local found = find_close_entities(game.players[1])
   --game.print("found: ".. #found)
   local player = game.players[1]
   local player_pos = player.position
   local grid = player.character.grid
   local grid_radius = get_grid_radius(grid)
   game.print("grid radius: " .. grid_radius)
   local area = {
      { player_pos.x - grid_radius, player_pos.y - grid_radius },
      { player_pos.x + grid_radius, player_pos.y + grid_radius }
   }
   local found_entitys = find_close_entities_swinter(game.players[1], area)
   --for every item found draw a circle as around it
   for _, entity in pairs(found_entitys) do
      if entity.valid and entity.type ~= "character" then
         local pos = entity.position

         rendering.draw_circle {
            color = { r = 1, g = 0, b = 0, a = 1 },
            radius = 0.3,     -- tiles (small)
            filled = true,
            target = pos,     -- center at player
            surface = entity.surface,
            time_to_live = 1, -- 5 seconds
            draw_on_ground = false
         }
      end
   end

   --draw range

   rendering.draw_rectangle {
      surface = player.surface,
      left_top = area[1],
      right_bottom = area[2],
      color = { 1, 1, 1 },
      time_to_live = 1
   }



   --local n = math.random(1, 5)



   for _, eq in pairs(grid.equipment) do
      if eq.type == "roboport-equipment" then
         --game.print("range: ".. eq.prototype.take_result.place_as_equipment_result.logistic_parameters.construction_radius)
         --local new_name = "personal-roboport-equipment" .. "-reduced-" .. n;
         --replace_roboport(grid, eq, new_name)
      end
   end

   --replace_roboport(g, )

   --local logistic = game.players[1].character.logistic_network
   --game.print("tick");
   --if logistic and logistic.all_construction_robots > 0 and logistic.robot_limit > 0 then

   --game.print("available: " .. logistic.available_construction_robots)
   --game.print("range: " .. logistic.cells[1].construction_radius)
   --end
end

local function get_orig_name(eq)
   return eq.prototype.take_result.place_as_equipment_result.name
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





local function set_radius(grid, desired)
   if not (grid and desired and desired >= 0) then return end

   -- Collect all personal roboports with their current & original radii.
   local eqs = {}
   local max_sumsq = 0
   local cur_sumsq = 0
   for _, eq in pairs(grid.equipment) do
      if eq.type == "roboport-equipment" then
         local orig = get_eq_max_radius(eq) -- radius from the original prototype
         local curr = get_eq_radius(eq)     -- radius of the currently installed variant
         table.insert(eqs, { eq = eq, orig = orig, curr = curr })
         max_sumsq = max_sumsq + orig * orig
         cur_sumsq = cur_sumsq + curr * curr
      end
   end
   if #eqs == 0 then return end

   local max_possible = math.floor(math.sqrt(max_sumsq) + 0.5)
   desired = math.floor(desired + 0.5) -- ensure integer radius
   local target2 = desired * desired

   -- If desired >= max achievable, just restore full-strength and exit.
   if desired >= max_possible then
      restore(grid)
      return
   end

   -- If our current radius is below target (because we were previously reduced),
   -- try restoring first to give ourselves headroom.
   if cur_sumsq < target2 then
      restore(grid)
      -- recompute current sums after restore
      cur_sumsq = max_sumsq
      if cur_sumsq <= target2 then
         -- Can't exceed target even at full strength; nothing else to do.
         return
      end
   end

   -- Sort roboports by current radius descending.
   table.sort(eqs, function(a, b) return a.curr > b.curr end)

   -- Reduce the biggest ones first. For each equipment, compute the exact radius
   -- needed so that Σ r_i^2 ≈ target2, clamped to [0, orig].
   for i, e in ipairs(eqs) do
      if cur_sumsq <= target2 then break end

      local others2 = cur_sumsq - e.curr * e.curr
      -- Choose the largest integer new_r such that others2 + new_r^2 <= target2
      local new_r = math.floor(math.sqrt(math.max(0, target2 - others2)) + 1e-9)

      -- Clamp to valid range and avoid pointless swaps.
      if new_r > e.orig then new_r = e.orig end
      if new_r < 0 then new_r = 0 end
      if new_r == e.curr then goto continue end

      -- Build the prototype name. If equal to original radius, use the original.
      local new_name
      if new_r == e.orig then
         new_name = get_orig_name(e.eq)
      else
         new_name = get_orig_name(e.eq) .. "-reduced-" .. new_r
      end

      replace_roboport(grid, e.eq, new_name)

      -- Update running total with the radius we just set.
      cur_sumsq = others2 + new_r * new_r
      e.curr = new_r

      ::continue::
   end
end


local function newTickOLD()
   -- get max possible radius

   --get real available robots

   if game.tick % 15 ~= 0 then
      return
   end
   --if av = 0
   -- make smaller
   --else make bigger

   if storage.radius == nil then
      storage.radius = 3
   end

   local player = game.players[1]
   local player_pos = player.position
   local grid = player.character.grid


   local real_available = get_player_real_available_robots(player)

   game.print(real_available)




   if real_available > 0 then
      if storage.radius < 30 then
         storage.radius = storage.radius + 3
      end
   else
      if storage.radius > 3 then
         storage.radius = storage.radius - 3
      end
   end


   local radius = storage.radius

   local area = {
      { player_pos.x - radius, player_pos.y - radius },
      { player_pos.x + radius, player_pos.y + radius }
   }

   rendering.draw_rectangle {
      surface = player.surface,
      left_top = area[1],
      right_bottom = area[2],
      color = { 1, 1, 1 },
      time_to_live = 15
   }

   set_radius(grid, math.ceil(radius) + 2)
end


--local CFG = {
--   poll_interval_ticks   = 10, -- you already poll every 15 ticks
--   min_radius            = 3,  -- floor radius we’ll allow
--   pad_radius            = 1,  -- small padding to avoid being “just too small”
--   step_up               = 2,  -- how much to grow per action
--   step_down             = 2,  -- how much to shrink per action
--   grow_hold_ticks       = 40, -- need 120 ticks (~2.0s) of bots available to grow
--   shrink_hold_ticks     = 40, -- need 240 ticks (~4.0s) of no bots to shrink
--   cooldown_after_grow   = 60, -- lock changes for 2.0s after growing
--   cooldown_after_shrink = 60, -- lock changes for 5.0s after shrinking
--   reserve_bots          = 1,  -- require > this many bots idle to grow
--}


local function newTickTEMP()
   if (game.tick % 10) ~= 0 then return end

   local p = game.players[1]
   if not (p and p.valid and p.character and p.character.valid) then return end

   local grid = p.character.grid
   if not grid then return end

   local max_radius = math.floor((get_grid_max_radius(grid) or 0))

   -- sanitize storage.radius (reset if NaN/inf/non-number/negative)
   if type(storage.radius) ~= "number" or storage.radius ~= storage.radius
       or storage.radius < 0 or storage.radius == math.huge or storage.radius == -math.huge then
      storage.radius = 0
   end

   -- if no roboports, collapse radius and bail (prevents % 0 => NaN)
   if max_radius <= 0 then
      storage.radius = 0
      set_grid_radius(grid, 0)
      return
   end

   -- wrap without using % (so we never risk % 0)
   storage.radius = storage.radius + 1
   if storage.radius >= max_radius then storage.radius = 0 end

   game.print(storage.radius)
   set_grid_radius(grid, storage.radius + 10)
end

--adding a new valueto the buffer while also returning the average of the ringbuffer
local function moving_average_ringbuffer_push(rb, value)
   local next_idx = (rb.index % rb.max) + 1
   local old = rb.buffer[next_idx] or 0
   rb.buffer[next_idx] = value
   rb.sum = rb.sum - old + value
   rb.index = next_idx
   return (rb.sum / rb.max ) or value
end



local config = {
  update_interval = 5,
  reserve_bots    = 1,    -- keep this many idle
  accel_gain      = 0.2*16, -- how strongly radius reacts to idle bots
  damping         = 0.4, -- velocity factor (0..1)
  max_speed       = 3,  -- clamp velocity (tiles/tick)
  min_radius      = 3
}

--working values
--local config = {
--  update_interval = 5,
--  reserve_bots    = 1,    -- keep this many idle
--  accel_gain      = 0.2*5, -- how strongly radius reacts to idle bots
--  damping         = 0.2, -- velocity factor (0..1)
--  max_speed       = 0.8,  -- clamp velocity (tiles/tick)
--  min_radius      = 3
--}

local function clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

local testnum = 15

local function newTick()
  if game.tick % config.update_interval ~= 0 then return end
 
  testnum = testnum + 1

  game.print(testnum)

  local p = game.players[1]
  if not (p and p.valid and p.character and p.character.valid) then return end

  local grid = p.character.grid
  if not grid then return end

  local maxR = get_grid_max_radius(grid) or 0
  if maxR <= 0 then
    set_grid_radius(grid, 0)
    return
  end
  --storage.ctrl = nil
  storage.avg_rb = storage.avg_rb or { buffer = {}, max = 50, index = 0, sum=0}
  storage.ctrl = storage.ctrl or { radius = config.min_radius, velocity = 0.0 }
  local s = storage.ctrl

  local avail = get_player_real_available_robots(p) or 0
  

  local moving_average_avail = moving_average_ringbuffer_push(storage.avg_rb, avail)
  game.print(moving_average_avail)

  -- error: positive if we have more idle bots than we want -> grow radius
  local err = (avail - config.reserve_bots)


  -- integrate acceleration into velocity
  local a = config.accel_gain * err
  s.velocity = s.velocity + a

  -- damping (friction) to prevent oscillation/runaway
  s.velocity = s.velocity * config.damping

  -- clamp speed
  if s.velocity >  config.max_speed then s.velocity =  config.max_speed end
  if s.velocity < -config.max_speed then s.velocity = -config.max_speed end

  -- integrate velocity into radius
  s.radius = s.radius + s.velocity

  -- clamp radius and zero velocity at bounds
  if s.radius <= config.min_radius then
    s.radius, s.velocity = config.min_radius, 0.0
  elseif s.radius >= maxR then
    s.radius, s.velocity = maxR, 0.0
  end

  set_grid_radius(grid, s.radius)
  --draw_area

  local area = {
      { p.position.x - s.radius, p.position.y - s.radius },
      { p.position.x + s.radius, p.position.y + s.radius }
   }

   rendering.draw_rectangle {
      surface = p.surface,
      left_top = area[1],
      right_bottom = area[2],
      color = { 1, 1, 1 },
      time_to_live = config.update_interval
   }

  storage.ctrl = s
end



local function newTickOLD()
   -- run on your 15-tick cadence
   if (game.tick % CFG.poll_interval_ticks) ~= 0 then return end

   local p = game.players[1]
   if not (p and p.valid and p.character and p.character.valid) then return end

   local grid = p.character.grid
   if not grid then return end

   -- compute availability
   local real_available = get_player_real_available_robots(p) or 0
   local maxR = get_grid_max_radius(grid)
   if maxR <= 0 then return end

   -- init controller state
   storage.ctrl = storage.ctrl or {
      radius = math.min(math.max(CFG.min_radius, 3), maxR),
      avail_streak = 0,
      zero_streak = 0,
      cooldown_until = 0,
   }

   local s = storage.ctrl
   -- clamp radius in case your gear changed
   if s.radius > maxR then s.radius = maxR end
   if s.radius < CFG.min_radius then s.radius = CFG.min_radius end

   local now = game.tick
   local in_cooldown = now < (s.cooldown_until or 0)

   -- update streaks
   if real_available > CFG.reserve_bots then
      s.avail_streak = s.avail_streak + CFG.poll_interval_ticks
      s.zero_streak = 0
   else
      s.zero_streak = s.zero_streak + CFG.poll_interval_ticks
      s.avail_streak = 0
   end

   -- act only if not cooling down
   if not in_cooldown then
      -- shrink rule
      if s.zero_streak >= CFG.shrink_hold_ticks and s.radius > CFG.min_radius then
         s.radius = math.max(CFG.min_radius, s.radius - CFG.step_down)
         s.cooldown_until = now + CFG.cooldown_after_shrink
         s.zero_streak, s.avail_streak = 0, 0
         -- grow rule
      elseif s.avail_streak >= CFG.grow_hold_ticks and s.radius < maxR then
         s.radius = math.min(maxR, s.radius + CFG.step_up)
         s.cooldown_until = now + CFG.cooldown_after_grow
         s.zero_streak, s.avail_streak = 0, 0
      end
   end

   -- apply with a tiny pad so we don’t hover exactly on the edge
   local desired = math.min(maxR, s.radius + CFG.pad_radius)
   set_grid_radius(grid, desired)

   -- (optional) draw the current box for visual feedback
   local pos = p.position
   local r = s.radius
   rendering.draw_rectangle {
      surface = p.surface,
      left_top = { pos.x - r, pos.y - r },
      right_bottom = { pos.x + r, pos.y + r },
      color = { 1, 1, 1 },
      time_to_live = CFG.poll_interval_ticks
   }

   -- persist
   storage.ctrl = s
end


local function setup()
   storage.radius = 2;
   storage.ctrl = {
      radius         = 3,
      idle_streak    = 0,     -- time with (almost) all bots idle
      expand_streak  = 0,     -- time with some bots idle (enough to allow growth)
      busy_streak    = 0,     -- time with 0 idle bots
      cooldown_until = 0,
      was_all_idle   = false, -- for edge detection "new job started"
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

script.on_configuration_changed(setup)

--script.on
