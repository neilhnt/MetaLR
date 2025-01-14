--[[-------------------------------------------------------------------------
NDHExpandPicks.lua

Choose a folder or collection
Pick one or many photos (e.g. using GPS coordinates near some location)
This script finds all photos in the folder or collection shot within <DeltaTime> of the selected photos.
Or all photos in the folder or collection shot within <DeltaDistance> of the selected photos.
SHOULD take into account timezone differences.

Method
	Create empty array of time windows { from, to }
	Iterate over all picks in time order
		# Expand by time
		Get phototime
		Iterate over all times
			If phototime within times->from..to then last
			If phototime within delta_time < from then
			     from = time - delta_time
			elseif photogrime within delta_time > to then
			     to = time + delta_time
			else
				add entry top times table phototime-delta_time, phototime+delta_time
			end
		end
	end

---------------------------------------------------------------------------]]

-- Set the names of root keyword and root collection set - can be edited to taste
local LrApplication = import 'LrApplication'
local LrFunctionContext = import 'LrFunctionContext'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrLogger = import 'LrLogger'
local LrTasks = import 'LrTasks'
 
-- Set up the logger
local logger = LrLogger('NDH')
logger:enable("print") -- set to "logfile" to write to ~/Documents/lrClassicLogs/NDH.log
local log = logger:quickf('info')

--[[
This is the entry point function that's called when the Lightroom menu item is selected
]]

local function main ()
  log(" Starting")
  local catalog = LrApplication.activeCatalog()
  local sources = catalog:getActiveSources()
  if (sources == nil) then
    log("No sources")
    LrDialogs.message("NDH", "Usage: Select one or more collections to subset by picks")
    return
  end
  
  -- Iterate over all selected collections...
  for i, s in ipairs(sources) do
    local t
    if (type(s) == 'string') then t = s else t = s:type() end
    if (t == 'LrCollection') then
      local collection = string.format("%s",s:getName())
      local photos = s:getPhotos();
      local picks = {}
      for k, photo in ipairs(photos) do
	local pickstatus = photo:getRawMetadata('pickStatus')
	local rating = photo:getRawMetadata('rating')
	if (rating == nil) then rating = 0 end
	if (pickstatus > 0 or rating > 2) then
	  picks[#picks+1] = photo
	end
      end
      local msg = string.format("Source %d: %s, contains %d photos, %d picks", i, s:getName(), #photos, #picks)
      local proceed = LrDialogs.confirm("NDH", msg, 'OK', 'Cancel', 'Skip')
      if (proceed == 'ok') then
        -- Find Year-CollectionSet
	local yc = nil
	local parent = s:getParent()
	while (parent ~= nil) do
	  yc = parent
	  parent = parent:getParent()
	end
	if (yc == nil or string.find(yc:getName(), "%d%d%d%d") ~= 1) then
	  -- Create or get rootkey and rootcollection
  	  catalog:withWriteAccessDo("Create collection set", function()
    	    yc = catalog:createCollectionSet('NDHCollections', nil, true) -- Create or get existing collection
	  end)
	end
	      
	-- Add (picked) photos to collection
	if (#picks > 0) then
	  LrDialogs.message(string.format("Adding %d picks to %s", #picks, collection))
	  catalog:withWriteAccessDo("Add photos", function()
	    coll = catalog:createCollection(collection, yc, true) -- Create or get existing collection
	    if (coll == nil) then
	      LrDialogs.message("NDH", string.format("Couldn't create collection %s in %s", collection, yc:getName()))
	      return;
	    end
	    coll:addPhotos(picks)
	  end)
	end
      elseif (proceed == 'skip') then
	-- loop around for next collection if any
      elseif (proceed == 'cancel') then
	return
      end	
    else
      LrDialogs.message("NDH", string.format("Usage: Selected source %s is not a collection", t))
      return
    end

  end

  LrDialogs.message("NDH", "Done")
 
end

-- Run main()
LrTasks.startAsyncTask(main)
