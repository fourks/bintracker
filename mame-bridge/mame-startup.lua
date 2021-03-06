-- This file is part of Bintracker.
-- Copyright (c) utz/irrlicht project 2019-2020
-- See LICENSE for license details.

-- io.stdin:setvbuf'line'

local listener = emu.thread()
local started = false

local print_machine_info = function ()
   print("System: ", emu.gamename())
   print("driver: ", emu.romname())
   print("\nMachine devices [manager:machine().devices]")
   for k,v in pairs(manager:machine().devices) do print(k) end
   print("\nMachine options")
   -- appearantly this is the same as calling manager:options().entries
   for k,v in pairs(manager:machine():options().entries) do
      print(k, "=", v:value())
   end
   local cpu = manager:machine().devices[":maincpu"]
   print("\nCPU State Registers\nState:")
   for k,v in pairs(cpu.state) do print(k, v.value) end
   -- print("\nSpaces:")
   -- for k,v in pairs(cpu.spaces) do print(k) end
   -- print("\nItems:")
   -- for k,v in pairs(cpu.items) do print(k) end
   print("\nMemory layout")
   for k,v in pairs(cpu.spaces) do print(k) end
end

local machine_set_pc = function (addr)
   -- print "setting pc"
   manager:machine().devices[":maincpu"].state["PC"].value = tonumber(addr)
end

local machine_load_bin = function (addr, data)
   local datatbl = {string.byte(data, 1, #data)}
   local mem = manager:machine().devices[":maincpu"].spaces["program"]
   for i = 1, #datatbl do
      mem:write_u8(addr, datatbl[i])
      -- print(tostring(mem:read_u8(addr)))
      addr = addr + 1
   end
end

local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local base64_decode = function (data)
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f = '' , (b:find(x)-1)
        for i = 6, 1, -1 do r = r..(f % 2^i - f% 2^(i-1) > 0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i = 1, 8 do c = c + (x:sub(i ,i) == '1' and 2^(8-i) or 0) end
            return string.char(c)
    end))
end

-- extract a numeric argument from a remote command string. The numeric argument
-- must be at the beginning of the string, and must be terminated with a `%`
-- character.
local get_numeric_arg = function (argstr)
   local res = ""
   while string.sub(argstr, 1, 1) ~= "%" do
      res = res..string.sub(argstr, 1, 1)
      argstr = string.sub(argstr, 2)
   end
   -- print(res)
   return tonumber(res)
end

local get_data_arg = function (argstr)
   while string.sub(argstr, 1, 1) ~= "%" do
      argstr = string.sub(argstr, 2)
   end
   -- print(string.sub(argstr, 2))
   return string.sub(argstr, 2)
end

local machine_run_bin = function (argstr)
   local addr = get_numeric_arg(argstr)
   -- local data = get_data_arg(argstr)
   emu.pause()
   machine_load_bin(addr, base64_decode(get_data_arg(argstr)))
   machine_set_pc(addr)
   emu.unpause()
end

local machine_reset = function (reset_type)
   if reset_type == "h" then
      manager:machine():hard_reset()
   elseif reset_type == "s" then
      manager:machine():soft_reset()
   end
end

-- Table of remote commands that Bintracker may send. The following commands
-- are recognized:
-- q - Quit emulator
-- p - Pause emulator
-- u - Unpause emulator
-- x argstr - eXecute argstr as code
local remote_commands = {
   ["b"] = machine_run_bin,
   ["i"] = print_machine_info,
   ["q"] = function () manager:machine():exit() end,
   ["p"] = emu.pause,
   ["r"] = machine_reset,
   ["s"] = machine_set_pc,
   ["u"] = emu.unpause,
   ["x"] = function (argstr) loadstring(argstr)() end
}

-- Attempt to destructure and run the remote command `cmd`. Takes the first
-- letter of `cmd` as key and looks up the associated function in
-- `remote_commands`. When successful, runs the function with the remainder of
-- `cmd` as argument.
local dispatch_remote_command = function(cmd)
   print("got command: ", cmd)
   local exec_cmd = remote_commands[string.sub(cmd, 1, 1)]
   if exec_cmd then exec_cmd(string.sub(cmd, 2)) end
end

-- -- not implemented yet in MAME 0.209?
-- emu.register_mandatory_file_manager_override(
--    function()
--       print("have mandatory file callback")
--    end
-- )

-- Register a period callback from the main emulation thread. On first run, it
-- starts a thread that listens to stdin, and returns the received input once it
-- receives a newline. The callback procedure attempts to run the input from the
-- listener as a remote command, then restarts the listener thread.
emu.register_periodic(
   function()
      if listener.busy then
	 return
      elseif listener.yield then
	 return
      elseif started then
	 dispatch_remote_command(listener.result)
      end
      listener:start([[ return io.stdin:read() ]])
      started = true
   end
)
