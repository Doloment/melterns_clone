
local furnaces = {}

local function update_timer (pos)
	local t = minetest.get_node_timer(pos)
	if not t:is_started() then
		t:start(1.0)
	end
end

-----------------------
-- Buffer operations --
-----------------------

-- List liquids in the controller
local function all_liquids (pos)
	local meta = minetest.get_meta(pos)
	local count = meta:get_int("buffers")
	local stacks = {}
	local total = 0

	if count == 0 then return stacks, total end

	for i = 1, count do
		stacks[i] = ItemStack(meta:get_string("buffer" .. i))
		total = total + stacks[i]:get_count()
	end

	return stacks, total
end

-- Set the bottom-most buffer
local function set_hot (pos, buf)
	local meta = minetest.get_meta(pos)
	local stacks, total = all_liquids(pos)

	if not stacks[buf] or stacks[buf]:is_empty() then
		return false
	end

	local current_one = stacks[1]
	local new_one = stacks[buf]

	meta:set_string("buffer1", new_one:to_string())
	meta:set_string("buffer" .. buf, current_one:to_string())

	return true
end

-- Reorganize the buffers, remove empty ones
local function clean_buffer_list (pos)
	local meta = minetest.get_meta(pos)
	local stacks, total = all_liquids(pos)
	local new = {}

	for i,v in pairs(stacks) do
		if not v:is_empty() then
			table.insert(new, v)
		end
	end

	for i, v in pairs(new) do
		meta:set_string("buffer" .. i, v:to_string())
	end

	meta:set_int("buffers", #new)
end

-- Returns how much of the first buffer fluid can be extracted
local function can_take_liquid (pos, want_mb)
	local meta = minetest.get_meta(pos)
	local stacks = all_liquids(pos)
	local found = stacks[1]

	if found and found:is_empty() then
		clean_buffer_list(pos)
		return "", 0
	end

	if not found then return "", 0 end

	local count = 0
	if found:get_count() < want_mb then
		count = found:get_count()
	else
		count = want_mb
	end

	return found:get_name(), count
end


-- Take liquid from the first buffer
local function take_liquid (pos, want_mb)
	local meta = minetest.get_meta(pos)
	local stacks = all_liquids(pos)
	local found = stacks[1]
	local fluid,count = can_take_liquid(pos, want_mb)

	if fluid == "" or count == 0 or fluid ~= found:get_name() then
		return fluid, 0
	end

	found = ItemStack(fluid)
	found:set_count(count)

	meta:set_string("buffer1", found:to_string())

	return fluid, count
end

-- Calculate furnace fluid capacity
local function total_capacity (pos)
	return 8000 -- TODO
end

-- Can you fit this liquid inside the furnace
local function can_put_liquid (pos, liquid)
	local stacks, storage = all_liquids(pos)
	local total = total_capacity(pos)
	local append = liquid:get_count()

	if total == storage then
		append = 0
	elseif storage + liquid:get_count() > total then
		append = total - storage
	end

	return append
end

-- Returns leftovers
local function put_liquid (pos, liquid)
	local stacks, storage = all_liquids(pos)
	local total = total_capacity(pos)
	local append = can_put_liquid(pos, liquid)
	local leftovers = liquid:get_count() - append

	if append == 0 then
		return leftovers
	end

	-- Find a buffer, if not available, create a new one
	local buf = nil
	for i,v in pairs(stacks) do
		if v:get_name() == liquid:get_name() then
			buf = i
			break
		end
	end

	if not buf then
		buf = #stacks + 1
	end

	if stacks[buf] then
		local st = stacks[buf]
		local stc = st:get_count() + append
		st:set_count(stc)
		meta:set_string("buffer" .. buf, st:to_string())
	else
		liquid:set_count(append)
		meta:set_string("buffer" .. buf, liquid:to_string())
	end

	return leftovers
end

--------------------------
-- Controller Operation --
--------------------------

-- Detect a structure based on controller
local function detect_structure (pos)
	local node = minetest.get_node(pos)
	local fd_to_d = minetest.facedir_to_dir(node.param2)
	local back = vector.add(pos, minetest.facedir_to_dir(node.param2))
	local op_port_pos
	local dir
	local center

	if back.x > pos.x then
		op_port_pos = {x = back.x + 3, y = back.y, z = back.z}
		left_port_pos = {x = back.x + 1, y = back.y, z = back.z + 2}
		right_port_pos = {x = back.x + 1, y = back.y, z = back.z - 2}
		center = {x = back.x + 1, y = back.y, z = back.z}
		dir = "X-positive"
		orient = "x-oriented"
	end -- x positive

	if back.x < pos.x then
		op_port_pos = {x = back.x - 3, y = back.y, z = back.z}
		left_port_pos = {x = back.x - 1, y = back.y, z = back.z - 2}
		right_port_pos = {x = back.x - 1, y = back.y, z = back.z + 2}
		center = {x = back.x - 1, y = back.y, z = back.z}
		dir = "X-negative"
		orient = "x-oriented"
	end -- x negative

	if back.z > pos.z then
		op_port_pos = {x = back.x, y = back.y, z = back.z + 3}
		left_port_pos = {x = back.x - 2, y = back.y, z = back.z + 1}
		right_port_pos = {x = back.x + 2, y = back.y, z = back.z + 1}
		center = {x = back.x, y = back.y, z = back.z + 1}
		dir = "Z-positive"
		orient = "z-oriented"
	end -- z positive

	if back.z < pos.z then
		op_port_pos = {x = back.x, y = back.y, z = back.z - 3}
		left_port_pos = {x = back.x + 2, y = back.y, z = back.z - 1}
		right_port_pos = {x = back.x - 2, y = back.y, z = back.z - 1}
		center = {x = back.x, y = back.y, z = back.z - 1}
		dir = "Z-negative"
		orient = "z-oriented"
	end -- z negative

	if minetest.get_node(op_port_pos).name == "multifurnace:port" then
		minetest.chat_send_all("Opposite port is found")
	else
		minetest.chat_send_all("Opposite port is not found. Abort operation")
		return false
	end

	if minetest.get_node(left_port_pos).name == "multifurnace:port" then
		minetest.chat_send_all("Left port is found")
	else
		minetest.chat_send_all("Left port is not found. Abort operation")
		return false
	end

	if minetest.get_node(right_port_pos).name == "multifurnace:port" then
		minetest.chat_send_all("Right port is found")
	else
		minetest.chat_send_all("Right port is not found. Abort operation")
		return false
	end

	if (orient == "x-oriented" and (minetest.get_node({x = pos.x, y = pos.y, z = pos.z + 1}).name == "air" 
	 or minetest.get_node({x = pos.x, y = pos.y, z = pos.z - 1}).name == "air"))
	 or (orient == "z-oriented" and (minetest.get_node({x = pos.x + 1, y = pos.y, z = pos.z}).name == "air" 
	 or minetest.get_node({x = pos.x - 1, y = pos.y, z = pos.z}).name == "air")) then
		minetest.chat_send_all("Wrong structure. Abort operation")
		return false
	end

	if (orient == "x-oriented" and (minetest.get_node({x = op_port_pos.x, y = op_port_pos.y, z = op_port_pos.z + 1}).name == "air" 
	 or minetest.get_node({x = op_port_pos.x, y = op_port_pos.y, z = op_port_pos.z - 1}).name == "air"))
	 or (orient == "z-oriented" and (minetest.get_node({x = op_port_pos.x + 1, y = op_port_pos.y, z = op_port_pos.z}).name == "air" 
	 or minetest.get_node({x = op_port_pos.x - 1, y = op_port_pos.y, z = op_port_pos.z}).name == "air")) then
		minetest.chat_send_all("Wrong structure. Abort operation")
		return false
   	end

	if (orient == "z-oriented" and (minetest.get_node({x = left_port_pos.x, y = left_port_pos.y, z = left_port_pos.z + 1}).name == "air" 
	 or minetest.get_node({x = left_port_pos.x, y = left_port_pos.y, z = left_port_pos.z - 1}).name == "air"))
	 or (orient == "x-oriented" and (minetest.get_node({x = left_port_pos.x + 1, y = left_port_pos.y, z = left_port_pos.z}).name == "air" 
	 or minetest.get_node({x = left_port_pos.x - 1, y = left_port_pos.y, z = left_port_pos.z}).name == "air")) then
		minetest.chat_send_all("Wrong structure. Abort operation")
		return false
	end

	if (orient == "z-oriented" and (minetest.get_node({x = right_port_pos.x, y = right_port_pos.y, z = right_port_pos.z + 1}).name == "air" 
	 or minetest.get_node({x = right_port_pos.x, y = right_port_pos.y, z = right_port_pos.z - 1}).name == "air"))
	 or (orient == "x-oriented" and (minetest.get_node({x = right_port_pos.x + 1, y = right_port_pos.y, z = right_port_pos.z}).name == "air" 
	 or minetest.get_node({x = right_port_pos.x - 1, y = right_port_pos.y, z = right_port_pos.z}).name == "air")) then
		minetest.chat_send_all("Wrong structure. Abort operation")
		return false
	end

	minetest.chat_send_all(dir.."; "..node.name.."; "..pos.x..":"..pos.y..":"..pos.z.."; "..back.x..":"..back.y..":"..back.z)
	--minetest.set_node({x=back.x, y=back.y, z=back.z}, {name="default:mese"})

	local minp1 = { x = center.x - 1, y = center.y - 1, z = center.z - 1 }
	local maxp1 = { x = center.x + 1, y = center.y - 1, z = center.z + 1 }
	local minp2 = { x = center.x - 1, y = center.y, z = center.z - 1 }
	local maxp2 = { x = center.x + 1, y = center.y + 1, z = center.z + 1 }
	local minp3 = { x = center.x - 2, y = center.y + 1, z = center.z - 2 }
	local maxp3 = { x = center.x + 2, y = center.y + 1, z = center.z + 2 }

	local _, air = minetest.find_nodes_in_area(minp2, maxp2, "air")
	local _, bricks1 = minetest.find_nodes_in_area(minp1, maxp1, "metal_melter:heated_bricks")
	local _, bricks2 = minetest.find_nodes_in_area(minp3, maxp3, "metal_melter:heated_bricks")
	if air["air"] ~= 18 or bricks1["metal_melter:heated_bricks"] ~= 9 or bricks2["metal_melter:heated_bricks"] < 9 then
		minetest.chat_send_all("Wrong structure. Abort operation")
		return false
	end
	minetest.chat_send_all("Right structure. Operation's done")
	return true
end

-- If pos is part of the structure, this will return a position
local function get_controller (pos)
	-- body
end

local function controller_timer (pos, elapsed)
	local refresh = false
	local meta = minetest.get_meta(pos)

	return refresh
end

function part_builder.get_formspec()
	return "size[8,8.5]"..
		default.gui_bg..
		default.gui_bg_img..
		default.gui_slots..
		"label[0,0;Part Builder]"..
		"list[context;pattern;1,1.5;1,1;]"..
		"list[context;input;2,1;1,2;]"..
		"list[context;output;6,1.5;1,1;]"..
		"image[4,1.5;1,1;gui_furnace_arrow_bg.png^[transformR270]"..
		"list[current_player;main;0,4.25;8,1;]"..
		"list[current_player;main;0,5.5;8,3;8]"..
		"listring[current_player;main]"..
		"listring[context;pattern]"..
		"listring[current_player;main]"..
		"listring[context;input]"..
		"listring[current_player;main]"..
		"listring[context;output]"..
		"listring[current_player;main]"..
		default.get_hotbar_bg(0, 4.25)
end

local state

local function on_construct(pos)
	if state ~= true then return nil end
	local meta = minetest.get_meta(pos)
	meta:set_string("formspec", part_builder.get_formspec())

	-- Create inventory
	local inv = meta:get_inventory()
	inv:set_size('pattern', 1)
	inv:set_size('input', 2)
	inv:set_size('output', 1)
end

-------------------
-- Registrations --
-------------------

minetest.register_node("multifurnace:controller", {
	description = "Multifurnace Controller",
	tiles = {
		"metal_melter_heatbrick.png", "metal_melter_heatbrick.png", "metal_melter_heatbrick.png",
		"metal_melter_heatbrick.png", "metal_melter_heatbrick.png", "metal_melter_heatbrick.png^multifurnace_controller_face.png",
	},
	groups = {cracky = 3, multifurnace = 1},
	paramtype2 = "facedir",
	is_ground_content = false,
	on_timer = controller_timer,
	on_rightclick = function (pos)
		if detect_structure(pos) == true then state = true end
	end

})

minetest.register_node("multifurnace:port", {
	description = "Multifurnace Port",
	tiles = {
		"metal_melter_heatbrick.png", "metal_melter_heatbrick.png", "metal_melter_heatbrick.png",
		"metal_melter_heatbrick.png", "metal_melter_heatbrick.png^multifurnace_intake_back.png",
		"metal_melter_heatbrick.png^multifurnace_intake_face.png",
	},
	groups = {cracky = 3, multifurnace = 2, fluid_container = 1},
	paramtype2 = "facedir",
	is_ground_content = false,
})
