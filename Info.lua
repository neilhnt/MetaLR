
--[[----------------------------------------------------------------------------

--------------------------------------------------------------------------------

Info.lua

Adds menu items to Lightroom.

------------------------------------------------------------------------------]]

return {

	LrSdkVersion = 9.0,
	LrSdkMinimumVersion = 3.0, -- minimum SDK version required by this plug-in

	LrToolkitIdentifier = 'com.tamarackmountain.NDH',
	LrPluginName = LOC "NDH v1.0.0",
	
	-- Add the menu item to the Library menu.
	
	LrLibraryMenuItems = {
	    {
	        title = "NDH Collections to Keywords",
		file = "NDHCollectionsToKeywords.lua",
	    },
	    {
		title = "NDH Folders to Collections",
		file = "NDHFoldersToCollections.lua",
	    },
	    {
	        title = "NDH Picks to Collections",
		file = "NDHPicksToCollections.lua",
	    },
	    {
	        title = "NDH Create Standard Collections",
		file = "NDHStandardCollections.lua",
	    },
	    {
	        title = "NDH Update Standard Collections",
		file = "NDHUpdateStandardCollections.lua",
	    },
	    {
	        title = "NDH Get Data",
		file = "NDHData.lua",
	    },
	    {
	        title = "NDH Fix Auto White",
		file = "NDHWhite.lua",
	    },
	    {
	        title = "NDH Auto Develop",
		file = "NDHAuto.lua",
	    },
--[[
	    {
	        title = "NDH UTC from GPS",
		file = "NDHUTCFromGPS.lua",
	    },
]]
	    {
	        title = "NDH Create CSV",
		file = "NDHCreateCSV.lua",
	    },
--[[
	    {
	        title = "NDH Load Captions",
		file = "NDHLoadCaptions.lua",
	    },
]]
	    {
	        title = "NDH Load Metadata",
		file = "NDHLoadMetadata.lua",
	    },
	    {
	        title = "NDH Select Simultaneous Dups",
		file = "NDHSelectSimulDups.lua",
	    },
--[[
	    {
		title = "NDH Output",
		file = "NDHShowCustomDialog.lua",
	    },
]]
--[[
	    {
	        title = "NDH Collections LEGACY",
		file = "NDH.lua",
	    },
]]
	},
	
	VERSION = { major=1, minor=0, revision=0, build="YYYYMMDDHHmm-0001", },

}


	
