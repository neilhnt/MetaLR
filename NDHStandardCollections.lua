--[[-------------------------------------------------------------------------
NDHStandardCollections.lua
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
  if (sources[1]:type() ~= 'LrCollectionSet') then
    LrDialogs.message("NDH", sources[1].type())
    return
  end

  for j, yc in ipairs(sources) do
    local root = yc:getName();
    local collections = catalog:createCollectionSet('Collections', nil, true);

    LrDialogs.message("NDH", string.format("Creating standard collections in Year Collection Set %s", root))

    catalog:withWriteAccessDo("Create collection", function()
    
      for i, base in ipairs(StandardNames) do
        local name = string.format("%s %s", root, base)
        local c = catalog:createCollection(name, yc, true)
	if (c == nil) then
	  LrDialogs.message("NDH", string.format("Failed %s", name))
	  return;
	end
      end

    end)

  end

end
        
-- Run main()
LrTasks.startAsyncTask(main)
