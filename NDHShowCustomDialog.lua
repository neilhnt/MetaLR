--[[----------------------------------------------------------------------------

ADOBE SYSTEMS INCORPORATED
 Copyright 2007 Adobe Systems Incorporated
 All Rights Reserved.

NOTICE: Adobe permits you to use, modify, and distribute this file in accordance
with the terms of the Adobe license agreement accompanying it. If you have received
this file from a source other than Adobe, then your use, modification, or distribution
of it requires the prior written permission of Adobe.

--------------------------------------------------------------------------------

NDHShowCustomDialog.lua
From the Hello World sample plug-in. Displays a custom dialog and writes debug info.

------------------------------------------------------------------------------]]

require 'NDHutils'

-- Access the Lightroom SDK namespaces.
local LrFunctionContext = import 'LrFunctionContext'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrPrefs = import 'LrPrefs'


local function showCustomDialog()

	LrFunctionContext.callWithContext( "showCustomDialog", function( context )

	    -- Load plugin preferences
	    local f = LrView.osFactory()
	    local prefs = LrPrefs.prefsForPlugin( nil )
	    -- Set defaults if never set before
	    if (prefs.isChecked == nil) then
	      prefs.isChecked = false
	    end
	    if (prefs.gpxfile == nil) then
	      prefs.gpxfile = '/Users/neilhunt/DriveNeil/0 Personal Folders/Maps/Split/YEAR/2024GPX.gpx'
	    end

	    -- Create a bindable table.  Whenever a field in this table changes
	    -- then notifications will be sent.
	    -- local props = LrBinding.makePropertyTable( context )
	    -- props.isChecked = false
	    -- props.gpxfile = '/Users/neilhunt/DriveNeil/0 Personal Folders/Maps/Split/YEAR/2024GPX.gpx'
	    
	    -- Create the contents for the dialog.
	    local c = f:row {
	
		    -- Bind the table to the view.  This enables controls to be bound
		    -- to the named field of the 'props' table.
		    
		    bind_to_object = prefs,
				
		    -- Add a checkbox and an edit_field.
		    
		    f:checkbox {
			    title = "Use GPX location and trackname",
			    value = LrView.bind( "isChecked" ),
		    },
		    f:edit_field {
		            width = 500,
			    value = LrView.bind("gpxfile"), -- "/Users/neilhunt/DriveNeil/0 Personal Folders/Maps/Split/YEAR/2024GPX.gpx",
			    enabled = LrView.bind( "isChecked" )
		    },
		    f:push_button {
		            title = "Browse",
			    action = function()
			      local files = LrDialogs.runOpenPanel{title = 'GPX File location',
  		  	                                             allowsMultipleSelection = false,
			                                             canChooseDirectories = false,
  	                                                             initialDirectory = '/Users/neilhunt/DriveNeil/0 Personal Folders/Maps/Split/YEAR/2024GPX.gpx'
								    }
                              if (files) then
			        prefs.gpxfile = files[1]
			        prefs.isChecked = true;
			      end
			      LrDialogs.message("Load GPX file", prefs.gpxfile)
			    end
		    },
	    }
	
	    LrDialogs.presentModalDialog {
			    title = "Create CSV with Metadata",
			    contents = c
		    }


	end) -- end main function

end



-- Now display the dialogs.
showCustomDialog()
