--[[
LuCI - Lua Configuration Interface

Copyright 2009 Steven Barth <steven@midlink.org>
Copyright 2009 Jo-Philipp Wich <xm@subsignal.org>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id$
]]--

local fs = require "nixio.fs"
local sys = require "luci.sys"
local cursor = require "luci.model.uci".inst
local state = require "luci.model.uci".inst_state
cursor:unload("wireless")

local device = cursor:get("wireless", "ap", "device")
local hwtype = cursor:get("wireless", device, "type")

local nsantenna = cursor:get("wireless", device, "antenna")

local iw = nil
local tx_powers = nil
local chan = sys.wifi.channels()

state:foreach("wireless", "wifi-iface",
	function(s)
		if s.device == device and not iw then
			iw = sys.wifi.getiwinfo(s.ifname or s.device)
			chan = sys.wifi.channels(s.ifname or s.device)
			tx_powers = iw.txpwrlist or { }
		end
	end)

m = Map("wireless", "Configure Access Point",
"The private Access Point is about to be created. You only need to provide "..
"a network name and a password to finish this step and - if you like - tweak "..
"some of the advanced settings.")

--- Device Settings ---
s = m:section(NamedSection, device, "wifi-device", "Device Configuration")
s.addremove = false

s:tab("general", translate("General Settings"))

ch = s:taboption("general", Value, "channel", translate("Channel"))
ch:value("auto", translate("automatic"))
for _, f in ipairs(chan) do
	ch:value(f.channel, "%i (%.3f GHz)" %{ f.channel, f.mhz })
end



s:tab("expert", translate("Expert Settings"))
if hwtype == "mac80211" then
	tp = s:taboption("expert",
		(tx_powers and #tx_powers > 0) and ListValue or Value,
		"txpower", translate("Transmission Power"), "dBm")

	tp.rmempty = true
	tp:value("", translate("automatic"))
	for _, p in ipairs(iw and iw.txpwrlist or {}) do
		tp:value(p.dbm, "%i dBm (%i mW)" %{ p.dbm, p.mw })
	end
elseif hwtype == "atheros" then
	tp = s:taboption("expert",
		(#tx_powers > 0) and ListValue or Value,
		"txpower", translate("Transmission Power"), "dBm")

	tp.rmempty = true
	tp:value("", translate("automatic"))
	for _, p in ipairs(iw.txpwrlist) do
		tp:value(p.dbm, "%i dBm (%i mW)" %{ p.dbm, p.mw })
	end

	mode = s:taboption("expert", ListValue, "hwmode", translate("Communication Protocol"))
	mode:value("", translate("automatic"))
	mode:value("11g", "802.11g")
	mode:value("11b", "802.11b")
	mode:value("11bg", "802.11b+g")
	mode:value("11a", "802.11a")
	mode:value("11gst", "802.11g + Turbo")
	mode:value("11ast", "802.11a + Turbo")
	
	if nsantenna then -- NanoFoo
		local ant = s:taboption("expert", ListValue, "antenna", translate("Transmitter Antenna"))
		ant:value("auto")
		ant:value("vertical")
		ant:value("horizontal")
		ant:value("external")
		ant.default = "auto"
	end
elseif hwtype == "broadcom" then
	tp = s:taboption("expert",
		(#tx_powers > 0) and ListValue or Value,
		"txpower", translate("Transmit Power"), "dBm")

	tp.rmempty = true
	tp:value("", translate("automatic"))
	for _, p in ipairs(iw.txpwrlist) do
		tp:value(p.dbm, "%i dBm (%i mW)" %{ p.dbm, p.mw })
	end	

	mp = s:taboption("expert", ListValue, "macfilter", translate("MAC-Address Filter"))
	mp:value("", translate("disable"))
	mp:value("allow", translate("Allow listed only"))
	mp:value("deny", translate("Allow all except listed"))
	ml = s:taboption("expert", DynamicList, "maclist", translate("MAC-List"))
	ml:depends({macfilter="allow"})
	ml:depends({macfilter="deny"})

	s:taboption("expert", Flag, "frameburst", translate("Allow Burst Transmissions"))
elseif hwtype == "prism2" then
	s:taboption("expert", Value, "txpower", translate("Transmission Power"), "att units").rmempty = true
end




s = m:section(NamedSection, "ap", "wifi-iface", "Access Point Details")
s.addremove = false

s:tab("general", translate("General Settings"))
s:tab("expert", translate("Expert Settings"))

s:taboption("general", Value, "ssid", translate("Network Name (<abbr title=\"Extended Service Set Identifier\">ESSID</abbr>)"))

mode = s:taboption("expert", ListValue, "mode", translate("Operating Mode"))
mode.override_values = true
mode:value("ap", translate("Access Point"))

encr = s:taboption("expert", ListValue, "encryption", translate("Encryption"))


if hwtype == "mac80211" then
	-- Empty
elseif hwtype == "atheros" then
	mode:value("ap-wds", "%s (%s)" % {translate("Access Point"), translate("WDS")})
	mode:value("wds", translate("Static WDS"))
	
	function mode.write(self, section, value)
		if value == "ap-wds" then
			ListValue.write(self, section, "ap")
			self.map:set(section, "wds", 1)
		else
			ListValue.write(self, section, value)
			self.map:del(section, "wds")
		end
	end

	function mode.cfgvalue(self, section)
		local mode = ListValue.cfgvalue(self, section)
		local wds  = self.map:get(section, "wds") == "1"
		return mode == "ap" and wds and "ap-wds" or mode
	end
	
	mp = s:taboption("expert", ListValue, "macpolicy", translate("MAC-Address Filter"))
	mp:value("", translate("disable"))
	mp:value("deny", translate("Allow listed only"))
	mp:value("allow", translate("Allow all except listed"))
	ml = s:taboption("expert", DynamicList, "maclist", translate("MAC-List"))
	ml:depends({macpolicy="allow"})
	ml:depends({macpolicy="deny"})
	
		
	hidden = s:taboption("expert", Flag, "hidden", translate("Hide Access Point"))
	hidden:depends({mode="ap"})
	hidden:depends({mode="ap-wds"})
	
	isolate = s:taboption("expert", Flag, "isolate", translate("Prevent communication between clients"))
	isolate:depends({mode="ap"})
	
	s:taboption("expert", Flag, "bursting", translate("Allow Burst Transmissions"))
elseif hwtype == "broadcom" then
	mode:value("wds", translate("WDS"))

	hidden = s:taboption("expert", Flag, "hidden", translate("Hide Access Point"))
	hidden:depends({mode="ap"})
	hidden:depends({mode="wds"})
	
	isolate = s:taboption("expert", Flag, "isolate", translate("Prevent communication between clients"))
	isolate:depends({mode="ap"})
elseif hwtype == "prism2" then
	mode:value("wds", translate("WDS"))

	mp = s:taboption("expert", ListValue, "macpolicy", translate("MAC-Address Filter"))
	mp:value("", translate("disable"))
	mp:value("deny", translate("Allow listed only"))
	mp:value("allow", translate("Allow all except listed"))
	
	ml = s:taboption("expert", DynamicList, "maclist", translate("MAC-List"))
	ml:depends({macpolicy="allow"})
	ml:depends({macpolicy="deny"})
	
	hidden = s:taboption("expert", Flag, "hidden", translate("Hide Access Point"))
	hidden:depends({mode="ap"})
	hidden:depends({mode="wds"})
end

-- Encryption --


encr.override_values = true
encr.override_depends = true
encr:value("none", "No Encryption")
encr:value("wep", "WEP", {mode="ap"}, {mode="sta"}, {mode="ap-wds"})

if hwtype == "atheros" or hwtype == "mac80211" or hwtype == "prism2" then
	local hostapd = fs.access("/usr/sbin/hostapd") or os.getenv("LUCI_SYSROOT")

	if hostapd then
		--s:taboption("expert", Flag, "_alloweap", "Allow EAP / 802.11i authentication")
		
		encr:value("psk", "WPA", {mode="ap"}, {mode="ap-wds"})
		encr:value("wpa", "WPA-EAP", {mode="ap"}, {mode="ap-wds"})
		encr:value("psk-mixed", "WPA + WPA2", {mode="ap"}, {mode="ap-wds"})
		encr:value("psk2", "WPA2", {mode="ap"}, {mode="ap-wds"})
		encr:value("wpa2", "WPA2-EAP (802.11i)", {mode="ap"}, {mode="ap-wds"})
		encr.default = "psk-mixed"
	end
elseif hwtype == "broadcom" then
	encr:value("psk", "WPA")
	encr:value("psk+psk2", "WPA + WPA2")
	encr:value("psk2", "WPA2")
	encr.default = "psk+psk2"
end

server = s:taboption("general", Value, "server", translate("Radius-Server"))
server:depends({mode="ap", encryption="wpa"})
server:depends({mode="ap", encryption="wpa2"})
server:depends({mode="ap-wds", encryption="wpa"})
server:depends({mode="ap-wds", encryption="wpa2"})
server.rmempty = true

port = s:taboption("general", Value, "port", translate("Radius-Port"))
port:depends({mode="ap", encryption="wpa"})
port:depends({mode="ap", encryption="wpa2"})
port:depends({mode="ap-wds", encryption="wpa"})
port:depends({mode="ap-wds", encryption="wpa2"})
port.rmempty = true

key = s:taboption("general", Value, "key", translate("Password"))
key:depends("encryption", "wep")
key:depends("encryption", "psk")
key:depends("encryption", "psk2")
key:depends("encryption", "psk+psk2")
key:depends("encryption", "psk-mixed")
key:depends({mode="ap", encryption="wpa"})
key:depends({mode="ap", encryption="wpa2"})
key:depends({mode="ap-wds", encryption="wpa"})
key:depends({mode="ap-wds", encryption="wpa2"})
key.rmempty = true
key.password = true

if hwtype == "atheros" or hwtype == "mac80211" or hwtype == "prism2" then
	nasid = s:taboption("general", Value, "nasid", translate("NAS ID"))
	nasid:depends({mode="ap", encryption="wpa"})
	nasid:depends({mode="ap", encryption="wpa2"})
	nasid:depends({mode="ap-wds", encryption="wpa"})
	nasid:depends({mode="ap-wds", encryption="wpa2"})
	nasid.rmempty = true
end
return m