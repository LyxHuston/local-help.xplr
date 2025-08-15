local xplr = xplr

local function setup(args)
	local help_key_data = {
		help = 'open local help',
		messages = {
			{
				CallLuaSilently = "custom.local_help.switch_to_help"
			},
		},
	}

	args = args or {}

	xplr.config.general.global_key_bindings.on_key[args.key or "ctrl-h"] = help_key_data

	local input_buffer_height = args.input_buffer_height or 3

	local help_data = {}

	xplr.config.modes.custom.local_help = {
		name = "Local Help",
		extra_help = "Displays help for the current mode.",
		layout = {
			Dynamic = "custom.local_help.layout"
		},
		key_bindings = {
			on_key = {
				esc = {
					help = "Leave local help",
					messages = { { CallLuaSilently = "custom.local_help.leave_help" } }
				},
				enter = {
					help = "Use currently hovered command",
					messages = { { CallLuaSilently = "custom.local_help.use_hovered" } }
				},
				down = {
					help = "Move focus down one",
					messages = { { CallLuaSilently = "custom.local_help.down_focus" } }
				},
				up = {
					help = "Move focus up one",
					messages = { { CallLuaSilently = "custom.local_help.up_focus" } }
				}
			},
			default = {
				messages = {
					"UpdateInputBufferFromKey",
					{ CallLuaSilently = "custom.local_help.gen_filtered_table" },
					{ CallLuaSilently = "custom.local_help.seat_focus" },
					"Refresh"
				}
			}
		}
	}

	local function seat_focus()
		local dat = help_data[#help_data]
		local focus = dat.focus
		local prev = dat.filtered_table[1] or 1
		for i, val in ipairs(dat.filtered_table) do
			if val == focus then
				return i
			elseif val > focus then
				dat.focus = prev
				return i
			end
			prev = val
		end
		dat.focus = prev
	end

	local function add_key_to_help_table(help_table, key, help, messages)
		help = help or ""
		for _, entry in pairs(help_table) do
			if entry.help == help and entry.messages == messages then
				table.insert(entry._keys, key)
				return
			end
		end
		table.insert(help_table, {
				_keys = { key },
				help = help,
				messages = messages
		})
	end

	local function help_key(first, second)
		return first.help < second.help
	end

	local function highlight(x)
		return "\x1b[30;1;47m" .. x .. "\x1b[0m"
	end

	xplr.fn.custom.local_help = {
		seat_focus = function(_)
			seat_focus()
			return {
				{ LogInfo = tostring(help_data[#help_data].focus) }
			}
		end,

		use_hovered = function(_)
			local dat = help_data[#help_data]
			local focus = dat.table[dat.focus]
			local m = focus.messages
			local messages = {
				{ CallLuaSilently = "custom.local_help.leave_help" },
			}
			for _, v in ipairs(m) do
				table.insert(messages, v)
			end
			return messages
		end,

		layout = function(ctx)
			local dat = help_data[#help_data]
			local mode = dat.mode
			local d = {}
			for _, val in ipairs({ "name", "help", "extra_help" }) do
				local header_line = mode[val]
				if header_line ~= nil then
					table.insert(d, header_line)
				end
			end

			local t = dat.table
			local filtered = dat.filtered_table
			local tablesize = math.min(
				ctx.layout_size.height - (#d + 2) - 1 - 2 - 1,
				#filtered
			)
			if dat.focus < dat.scrolltop + 3 then
				dat.scrolltop = math.max(dat.focus - 3, 1)
			elseif dat.focus - tablesize > dat.scrolltop - 3 then
				dat.scrolltop = math.min(
					dat.focus - tablesize + 3,
					#filtered - tablesize + 1
				)
			end

			local first_col_width = 0
			for _, v in pairs(t) do
				local l = #v.keys
				if l > first_col_width then
					first_col_width = l
				end
			end

			local rows = {}
			for i = dat.scrolltop, math.min(dat.scrolltop + tablesize, #filtered) do
				local j = filtered[i]
				local v = t[j]
				if v == nil then
					table.insert(rows, {
							tostring(i)
								.. " "
								.. tostring(j)
								.. " "
								.. tostring(#filtered),
							" " .. tostring(#t)
					})
				else
					local row = ""
					row = row .. v.keys
					row = row .. string.rep(" ", first_col_width - #v.keys)
					row = row .. " | "
					row = row .. v.help
					if j == dat.focus then
						row = row .. string.rep(" ", ctx.layout_size.width - #row)
						table.insert(rows, { highlight(row) })
					else
						table.insert(rows, { row })
					end
				end
			end

			return {
				CustomLayout = {
					Vertical = {
						config = {
							margin = 0,
							horizontal_margin = 0,
							vertical_margin = 0,
							constraints = {
								-- somewhat bad estimate: when a line goes over length
								{ Length = #d + 2 },
								{ Percentage = 100 },
								{ Min = input_buffer_height }
							}
						},
						splits = {
							-- header
							{
								Static = {
									CustomParagraph = {
										body = table.concat(d, "\n")
									}
								}
							},
							-- help area
							{
								Static = {
									CustomTable = {
										widths = {
											{ Percentage = 100 },
										},
										body = rows,
									}
								}
							},
							-- filter
							"InputAndLogs"
						}
					}
				}
			}
		end,

		gen_filtered_table = function(app)
			local filter_string = app.input_buffer
			local h = help_data[#help_data]
			local t = h.table

			local filtered_table = {}
			for i, val in ipairs(t) do
				if
					filter_string == nil
					or
					filter_string == ""
					or
					val.help:match(filter_string) ~= nil
					or
					val.keys:match(filter_string) ~= nil
				then
					table.insert(filtered_table, i)
				end
			end
			h.filtered_table = filtered_table
		end,

		switch_to_help = function(app)
			local mode = app.mode
			local help_table = {}
			for key, val in pairs(mode.key_bindings.on_key) do
				add_key_to_help_table(help_table, key, val.help, val.messages)
			end
			table.sort(help_table, help_key)
			for _, val in pairs(help_table) do
				table.sort(val._keys)
				val.keys = table.concat(val._keys, ", ")
			end
			table.insert(help_data, {
					mode = mode,
					focus = 1,
					scrolltop = 1,
					table = help_table
			})
			return {
				"ClearScreen",
				{ SetInputBuffer = "" },
				{ CallLuaSilently = "custom.local_help.gen_filtered_table" },
				{ SwitchModeCustom = "local_help" },
				"Refresh"
			}
		end,

		leave_help = function(_)
			table.remove(help_data)
			return {
				"PopMode"
			}
		end,

		down_focus = function(_)
			local dat = help_data[#help_data]
			local i = seat_focus()
			dat.focus = dat.filtered_table[math.min(i + 1, #dat.filtered_table)]
			return {
				"Refresh"
			}
		end,

		up_focus = function(_)
			local dat = help_data[#help_data]
			local i = seat_focus()
			dat.focus = dat.filtered_table[math.max(i - 1, 1)]
			return {
				"Refresh"
			}
		end
	}

end

return {
  setup = setup,
}
