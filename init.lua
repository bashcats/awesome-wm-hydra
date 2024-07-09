local gears = require("gears")
local awful = require("awful")
local beautiful = require("beautiful")
local naughty = require("naughty")
local wibox = require("wibox")
local math = require("math")
local dpi = require("beautiful.xresources").apply_dpi

local key_table_froms_list = function(t)
	local result = {}
	for i, v in ipairs(t) do
		result[v] = i
	end
	return result
end
--- Cached objects
local wbox
local title_widget
local layout_widgets
local num_columns = 3
local hydra_colors = key_table_froms_list({
	"red",
	"green",
	"blue",
	"amaranth",
})

local hidden = {}

local function debug_print(str)
	naughty.notify({
		preset = naughty.config.presets.normal,
		title = "Debug",
		text = str,
	})
end

local function print_error(str)
	naughty.notify({
		preset = naughty.config.presets.critical,
		title = "Error",
		text = str,
	})
end

local function key_to_string(mod, key)
	if key == " " then
		key = "space"
	end

	local mod_copy = {}
	for _, modifier in ipairs(mod) do
		table.insert(mod_copy, modifier)
	end

	table.sort(mod_copy)

	if #mod_copy > 0 then
		key = table.concat(mod_copy, "-") .. "-" .. key
	end
	-- to lower case
	key = key:lower()
	return key
end

local function colorize(text, fg, bg)
	if fg == nil then
		fg = ""
	else
		fg = ' foreground="' .. fg .. '"'
	end
	if bg == nil then
		bg = ""
	else
		bg = ' background="' .. bg .. '"'
	end
	return "<span" .. fg .. bg .. ">" .. text .. "</span>"
end

local function bold(text)
	return "<b>" .. text .. "</b>"
end

local function escape_markup(text)
	return text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end

local function start(args)
	local config = args.config
	if not config then
		error("config not given")
	end
	local activation_key = args.activation_key
	if not activation_key then
		error("activation_key not given")
	end
	local current_hydra_color
	if args.hydra_color then
		current_hydra_color = hydra_colors[args.hydra_color]
		if not current_hydra_color then
			error("invalid hydra_color; allowed: 'red', 'green', blue', 'amaranth'")
		end
	else
		current_hydra_color = hydra_colors.green
	end

	local current_key_table = config
	current_hydra_color = current_key_table.color and hydra_colors[current_key_table.color] or current_hydra_color

	local ignored_mod = args.ignored_mod or nil
	local hide_first_level = args.hide_first_level or false
	local key_fg = args.key_fg or beautiful.fg_normal
	local key_bg = args.key_bg or "#eeeeee"
	local key_control_fg = args.key_control_fg or "#00bb00"
	local key_shift_fg = args.key_shift_fg or "#4488ff"
	local key_modifier_fg = args.key_modifier_fg or "#aa4444"
	local activation_fg = args.activation_fg or "#44aaff"
	local nested_fg = args.nested_fg or "#4488aa"
	local nested_bg = args.nested_bg or nil
	local focused_fg = args.focused_fg or nil
	local focused_bg = args.focused_bg or "#dddddd"

	local breadcrumbs = {}
	local focused_key = nil

	local initial_screen = awful.screen.focused()

	local margin_size = dpi(6)
	local title_height = dpi(22)
	local key_height = dpi(15)
	local main_width = dpi(800)
	local y_anchor_pos = 0.75

	local colorized_control = colorize("C", key_control_fg)
	local colorized_shift = colorize("S", key_shift_fg)
	local colorized_mod1 = colorize("A", key_modifier_fg)
	local colorized_mod4 = colorize("Super", key_modifier_fg)
	local colorized_mod3 = colorize("Mod3", key_modifier_fg)

	local function key_string_to_label(key_string)
		key_string = key_string:gsub("control", colorized_control)
		key_string = key_string:gsub("shift", colorized_shift)
		key_string = key_string:gsub("mod1", colorized_mod1)
		key_string = key_string:gsub("mod4", colorized_mod4)
		key_string = key_string:gsub("mod3", colorized_mod3)
		return colorize(bold(" " .. key_string .. " "), key_fg, key_bg)
	end

	local function stylize_nested(description)
		return colorize(bold(description), nested_fg, nested_bg)
	end

	local function update_ui()
		if hide_first_level and #breadcrumbs == 0 then
			return
		end

		if not wbox then
			wbox = wibox({
				ontop = true,
				type = "dock",
				border_width = beautiful.border_width,
				border_color = beautiful.border_focus,
				placement = awful.placement.centered,
			})
			wbox.screen = initial_screen
			wbox:set_fg(beautiful.fg_normal)
			wbox:set_bg(beautiful.bg_normal .. "e2")

			local container_inner = wibox.layout.align.vertical()
			local container_layout =
				wibox.container.margin(container_inner, margin_size, margin_size, margin_size, margin_size)
			container_layout = wibox.container.background(container_layout)

			wbox:set_widget(container_layout)
			layout_widgets = {}
			for i = 1, num_columns do
				local layout_widget = wibox.layout.fixed.vertical()
				table.insert(layout_widgets, layout_widget)
			end
			title_widget = wibox.widget({
				markup = "",
				valign = "bottom",
				align = "center",
				forced_height = title_height,
				widget = wibox.widget.textbox,
			})
			container_inner:set_bottom(title_widget)
			local args = {
				layout = wibox.layout.flex.horizontal,
				forced_width = main_width,
			}
			for _, layout_widget in ipairs(layout_widgets) do
				table.insert(args, layout_widget)
			end
			container_inner:set_middle(wibox.widget(args))
		else
			for _, layout_widget in ipairs(layout_widgets) do
				layout_widget:reset()
			end
		end

		-- build title widget markup using breadcrumbs
		local title_markup = colorize(bold(activation_key), activation_fg)
		for i, v in ipairs(breadcrumbs) do
			title_markup = title_markup .. " " .. key_string_to_label(escape_markup(v[1]))
		end
		if #breadcrumbs > 0 then
			local v = breadcrumbs[#breadcrumbs]
			title_markup = title_markup .. " - " .. stylize_nested(escape_markup(v[2]))
		end
		title_widget.markup = title_markup

		-- Set geometry always, the screen might have changed.
		local wa = initial_screen.workarea
		local x = math.ceil(wa.x + wa.width / 2 - main_width / 2) -- Center align
		wbox:geometry({
			x = x,
			width = main_width,
		})
		local wbox_height = title_height

		local keys = {}
		for k, _ in pairs(current_key_table) do
			table.insert(keys, { k, key_string_to_label(escape_markup(k)) })
		end
		table.sort(keys, function(a, b)
			return a[2] < b[2]
		end)

		-- loop through each key
		local current_column = 1
		for _, entry in ipairs(keys) do
			local k = entry[1]
			local label = entry[2]
			local v = current_key_table[k]
			local description = v[1]
			if description ~= hidden then
				description = escape_markup(description)
				local child = v[2]
				local child_is_function = type(child) == "function"
				if not child_is_function then
					description = stylize_nested(description .. "...")
				end
				local height = key_height
				local markup = label .. " - " .. description
				if focused_key == k then
					markup = colorize(markup, focused_fg, focused_bg)
				end
				local key_widget = wibox.widget({
					markup = markup,
					valign = "center",
					align = "left",
					forced_height = height,
					widget = wibox.widget.textbox,
				})
				layout_widgets[current_column]:add(key_widget)
				if current_column == 1 then
					wbox_height = wbox_height + height
				end
				current_column = current_column + 1
				if current_column > num_columns then
					current_column = 1
				end
			end
		end

		local h = wbox_height + margin_size * 2
		wbox.screen = initial_screen
		wbox:geometry({
			height = h,
			y = wa.y + wa.height * y_anchor_pos - h,
		})
		wbox.visible = true
	end

	local grabber

	local function stop()
		if wbox then
			wbox.visible = false
		end
		awful.keygrabber.stop(grabber)
		grabber = nil
		breadcrumbs = {}
	end

	update_ui()

	grabber = awful.keygrabber.run(function(mod, key, event)
		if event == "release" then
			if current_hydra_color == hydra_colors.green then
				if key == activation_key then
					stop()
				end
			end
			return
		end

		local mod_copy = {}
		for _, modifier in ipairs(mod) do
			if modifier ~= ignored_mod and modifier ~= "Mod2" then
				table.insert(mod_copy, modifier)
			end
		end
		mod = mod_copy

		local key_string = key_to_string(mod, key)
		-- debug_print("grabber: mod: " .. table.concat(mod, ',')
		--     .. ", key: " .. tostring(key)
		--     .. ", event: " .. tostring(event)
		--     .. ", key_string: " .. key_string)

		local child = current_key_table[key_string]

		if not child then
			if current_hydra_color == hydra_colors.red then
				if key_string ~= activation_key or key_string ~= ignored_mod then
					stop()
				end
			end
		else
			local description = child[1]
			local child_color = child.color and hydra_colors[child.color] or current_hydra_color
			child = child[2]
			if type(child) == "function" then
				local status, err = pcall(child)
				-- if not status then (unused status)
				if err then
					print_error("Error: " .. err)
				end
				focused_key = key_string
				update_ui()
				if child_color == hydra_colors.blue then
					stop()
				end
			else
				table.insert(breadcrumbs, { key, description })
				current_key_table = child
				focused_key = nil
				update_ui()
			end
		end
	end)
end

return {
	start = start,
	hidden = hidden,
}

