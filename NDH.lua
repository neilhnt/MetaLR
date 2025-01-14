--[[-------------------------------------------------------------------------
NDH.lua

Exploring LRSDK

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
    LrDialogs.message("NDH", "Usage: Select one or more collections against which to create keywords")
    return
  end

  -- Get root name for keywords and sub collections:
  --[[
  LrFunctionContext.callWithContext( "showCustomDialog", function( context )
    local f = LrView.osFactory()
    -- Create a bindable table.  Whenever a field in this table changes then notifications will be sent.
    local props = LrBinding.makePropertyTable( context )
    props.isChecked = false
    -- Create the contents for the dialog.
    local c = f:row {
       -- Bind the table to the view.  This enables controls to be bound to the named field of the 'props' table.
       bind_to_object = props,
       -- Add a checkbox and an edit_field.
       f:checkbox {
			    title = "Enable",
			    value = LrView.bind( "isChecked" ),
		    },
		    f:edit_field {
			    value = "Some Text",
			    enabled = LrView.bind( "isChecked" )
		    }
	    }
       LrDialogs.presentModalDialog {
         title = "NDH",
         contents = c
       }
  end) -- end callWithContext
]]

  -- Create or get rootkey and rootcollection
  local rootkey
  catalog:withWriteAccessDo("Create keyword", function()
    rootkey = catalog:createKeyword('NDHKeywords', {}, true, nil, true) -- Create or get existing keyword
  end)
  local rootcollection
  catalog:withWriteAccessDo("Create collection", function()
    rootcollectionset = catalog:createCollectionSet('NDHCollections', nil, true) -- Create or get existing collection
  end)
  
  -- Iterate over all selected collections...
  for i, s in ipairs(sources) do
    local t
    if (type(s) == 'string') then t = s else t = s:type() end
    if (t == 'LrCollection') then
      local keyword = string.format("Collection:%s", s:getName())
      local collection = string.format("%s",s:getName())
      local key = nil
      local photos = s:getPhotos();
      local msg = string.format("Source %d: %s, contains %d photos; applying keyword: %s", i, s:getName(), #photos, keyword)
      local proceed = LrDialogs.confirm("NDH", msg, 'OK', 'Cancel', 'Skip')
      if (proceed == 'ok') then
	-- Get or Create the keyword in the catalog.
	catalog:withWriteAccessDo("Create keyword", function()
	  key = catalog:createKeyword(keyword, {}, true, rootkey, true) -- Create or get existing keyword
	  -- LrDialogs.message("NDH", string.format("Keyword %s created %s", keyword, key:getName()))
	end)
	-- Do the work on each photo:
	picks = {}
	catalog:withWriteAccessDo("Add Keyword", function()
	  for k, photo in ipairs(photos) do
	    photo:addKeyword(key)
	    local pickstatus = photo:getRawMetadata('pickStatus')
	    local rating = photo:getRawMetadata('rating')
	    if (rating == nil) then rating = 0 end
	    if (pickstatus > 0 or rating > 2) then
	      picks[#picks+1] = photo
	    end
	  end
	end)
	-- Add (picked) photos to collection
	if (#picks > 0) then
	  LrDialogs.message(string.format("Adding %d picks to %s", #picks, collection))
	  catalog:withWriteAccessDo("Create collection", function()
	    coll = catalog:createCollection(collection, rootcollectionset, true) -- Create or get existing collection
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
 
end

-- Run main()
LrTasks.startAsyncTask(main)




--[[
This was the old stuff
LrTasks.startAsyncTask(function ()
  local catalog = LrApplication.activeCatalog()
  -- local source = catalog.getActiveSources() 
  local photo = catalog:getTargetPhoto()
  if photo == nil then
    LrDialogs.message("Hello World", "Please select a photo")
    return
  end
 
  local filename = photo:getFormattedMetadata("fileName")
  local msg = string.format("The selected photo's filename is %q", filename)
  LrDialogs.message("Hello World", msg)
end)
]]
