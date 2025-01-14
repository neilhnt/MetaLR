--[[-------------------------------------------------------------------------
NDHUpdateStandardCollections.lua
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

local StandardNames = {
  "0 Top Picks",
  "Activities",
  "Art and Painting",
  "Birds and Animals",
  "Landscapes",
  "Flowers",
  "Nature",
  "Night Scenes",
  "Clouds and Sky",
  "Sun and Moon",
  "Z Book Bentleys",
  "Z Book Charlie Doris",
  "Z Book Cliffe Betsy",
  "Z Book Howers",
  "Z Book Pete Ann",
  "Z Book Sherie",
  "Z Book Stef",
  "Z Book Rich Lynn",
  "Z Book Dan Angela",
  "Z Book Katie Neil",
  "Z Book Shirley"
}

--[[
This is the entry point function that's called when the Lightroom menu item is selected
]]

local function main ()
  log(" Starting")
  local catalog = LrApplication.activeCatalog()
  local sources = catalog:getActiveSources()
  if (sources == nil) then
    log("No sources")
    LrDialogs.message("NDH", "Usage: Select Year-Collection in which to create standard collections")
    return
  end

  -- Find the master "Collections" collection set
  local masterCollectionsSet = catalog.createCollection("Collections", nil, true)

  -- For each standard collection name

    -- If sources are specified, then iterate over sources - otherwise iterate over all top level NNNN collection sets.

      -- Build list of photos in each NNNN collection set

    -- End loop building list of photos

    -- Get or create the standard named collection within the "Collections" collection set

    -- Get current photos and mark any that are not in the update list

    -- Add update list photos to the standard collection

  -- End iteration of standard collection name


  if (sources[1]:type() ~= 'LrCollectionSet') then
    LrDialogs.message("NDH", sources[1].type())
    return
  end

--[[    

    -- Get any photos already in collection
    local photos = c:getPhotos()
    if (photos ~= nil and #photos > 0) then
      -- Create or get "TOP <Collection>"
      catalog:withWriteAccessDo("Create collection", function()
	local s = catalog:createCollection(base, collections, true)
	-- LrDialogs.message("NDH", string.format("Created collection Collections/%s", base))
	if (s == nil) then
	  LrDialogs.message("NDH", string.format("Failed to create collection Collections/%s", base))
	  return
	end
	s:addPhotos(photos)
      end)
    end
]]

end