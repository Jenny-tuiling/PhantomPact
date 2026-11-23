local profiles=require('profiles')
local web=require('web_skins')
web.registerProfiles(profiles)
local appearance=require('appearance')
web.start(profiles,appearance)
_G.PBZWebSkins=web
