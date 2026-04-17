utf8_to_html = require("utf8_to_html")

DEFAULT_EXPORT_PATH = "/tmp/temp"

-- Helper function to get mouse position
function get_mouse_position()
  local hasLgi, lgi = pcall(require, "lgi")
  if not hasLgi then
    return nil, nil
  end
  local Gdk = lgi.Gdk
  local display = Gdk.Display.get_default()
  if not display then
    return nil, nil
  end
  local seat = display:get_default_seat()
  if not seat then
    return nil, nil
  end
  local pointer = seat:get_pointer()
  if not pointer then
    return nil, nil
  end
  local screen, x, y = pointer:get_position()
  return x, y
end

-- Register Toolbar
function initUi()

  app.registerUi({menu="Previous Bookmark", toolbarId="CUSTOM_PREVIOUS_BOOKMARK", callback="search_bookmark", mode=-1, iconName="go-previous"})
  app.registerUi({menu="New Bookmark", toolbarId="CUSTOM_NEW_BOOKMARK", callback="dialog_new_bookmark", iconName="bookmark-new-symbolic", ["accelerator"]="<Ctrl>B"})
  app.registerUi({menu="New Bookmark (No dialog)", toolbarId="CUSTOM_NEW_BOOKMARK_NO_DIALOG", callback="new_bookmark", iconName="bookmark-new-symbolic"})
  app.registerUi({menu="Next Bookmark", toolbarId="CUSTOM_NEXT_BOOKMARK", callback="search_bookmark", mode=1, iconName="go-next"})
  app.registerUi({menu="View Bookmarks", toolbarId="CUSTOM_VIEW_BOOKMARKS", callback = "view_bookmarks", iconName="user-bookmarks-symbolic", ["accelerator"]="<Ctrl><Shift>B"})
  app.registerUi({menu="Export to PDF with Bookmarks", toolbarId="CUSTOM_EXPORT_WITH_BOOKMARKS", callback="export", iconName="xopp-document-export-pdf"})

  sep = package.config:sub(1,1)
  sourcePath = debug.getinfo(1).source:match("@?(.*" .. sep .. ")")
  if sep == "\\" then
    DEFAULT_EXPORT_PATH = "%TEMP%\\temp"
  end
end

function new_bookmark(name)

  local structure = app.getDocumentStructure()

  local currentPage = structure.currentPage
  local currentLayerID = structure.pages[currentPage].currentLayer
  local layerCount = #structure.pages[currentPage].layers

  -- Go to the bottom layer first, then create new layer below it
  app.setCurrentLayer(1)
  app.activateAction("layer-new-below-current")
  
  if type(name) == "string" then
    app.setCurrentLayerName("Bookmark::" .. name)
  else
    app.setCurrentLayerName("Bookmark::")
  end
  app.setLayerVisibility(false)
  
  -- Restore the original layer (adding 1 because we added a layer below)
  app.setCurrentLayer(currentLayerID + 1)
end

function delete_layer(page, layerID)
  local structure = app.getDocumentStructure()

  app.setCurrentPage(page)
  local currentLayerID = structure.pages[page].currentLayer
  app.setCurrentLayer(layerID)
  app.layerAction("ACTION_DELETE_LAYER")
  if currentLayerID > layerID then
    app.setCurrentLayer(currentLayerID - 1)
  else
    app.setCurrentLayer(currentLayerID)
  end
end

-- mode = -1 for searching backwards, or 1 for searching forwards
function search_bookmark(mode)

  local structure = app.getDocumentStructure()
  local currentPage = structure.currentPage
  local numPages = #structure.pages
  local page = currentPage
  local nextBookmark

  repeat
    page = page + mode
    if page == numPages + 1 then page = 1 end
    if page == 0 then page = numPages end
    for u,v in pairs(structure.pages[page].layers) do
      if v.name:sub(1,10) == "Bookmark::" then
        nextBookmark = page
        break
      end
    end
    if nextBookmark ~= nil then break end
  until page == currentPage

  if nextBookmark == nil then
    app.openDialog("No bookmark found.", {"Ok"}, "")
    return
  end

  app.setCurrentPage(nextBookmark)
  app.scrollToPage(nextBookmark)

end

function dialog_new_bookmark()
  local hasLgi, lgi = pcall(require, "lgi")
  if not hasLgi then
    new_bookmark()
    return
  end

  local Gtk = lgi.require("Gtk", "3.0")
  local Gdk = lgi.Gdk
  local assert = lgi.assert
  local builder = Gtk.Builder()
  assert(builder:add_from_file(sourcePath .. "dlgNew.glade"))
  local ui = builder.objects
  local dialog = ui.dlgNew
  local title = "Xournalpp - New bookmark"
  local defaultName=""

  dialog:set_title(title)
  ui.entryName:set_text(defaultName)

  -- Position dialog at mouse location
  local mouse_x, mouse_y = get_mouse_position()
  if mouse_x and mouse_y then
    dialog:show_all()
    local width = dialog:get_allocated_width()
    local height = dialog:get_allocated_height()
    dialog:move(mouse_x - width / 2, mouse_y - height / 2)
  end

  local function ok()
    local name = ui.entryName:get_text()
    new_bookmark(name)
    dialog:destroy()
  end

  function ui.btnNewOk.on_clicked()
    ok()
  end

  function ui.entryName.on_activate()
    ok()
  end

  function ui.btnNewCancel.on_clicked()
    dialog:destroy()
  end

  if not mouse_x or not mouse_y then
    dialog:show_all()
  end
end

function view_bookmarks()

  local hasLgi, lgi = pcall(require, "lgi")
  if not hasLgi then
    app.openDialog("You need to have the Lua lgi-module installed and included in your Lua package path in order view bookmarks\n", {"OK"}, "")
    return
  end

  local Gtk = lgi.require("Gtk", "3.0")
  local Gdk = lgi.Gdk
  local assert = lgi.assert
  local builder = Gtk.Builder()
  assert(builder:add_from_file(sourcePath .. "dlgBookmarks.glade"))
  local ui = builder.objects
  local dialog = ui.dlgBookmarks
  local title = "Xournalpp - Bookmarks Manager"
  dialog:set_title(title)

  local column = {
    PAGE = 1,
    DISPLAY_NAME = 2,
    NAME = 3,
    LAYER_ID = 4,
  }

  local store = Gtk.ListStore.new {
    [column.PAGE] = lgi.GObject.Type.UINT,
    [column.DISPLAY_NAME] = lgi.GObject.Type.STRING,
    [column.NAME] = lgi.GObject.Type.STRING,
    [column.LAYER_ID] = lgi.GObject.Type.UINT,
  }

  local structure
  local numPages

  local function updateTable()
    structure = app.getDocumentStructure()
    numPages = #structure.pages
    store:clear()
    for page=1, numPages do
      local pageBookmarks = {}
      
      -- First, collect all bookmarks for this specific page
      for u,v in pairs(structure.pages[page].layers) do
        if v.name:sub(1,10) == "Bookmark::" then
          local displayName = v.name:sub(11)
          if displayName == "" then displayName = "(No name)" end
          
          table.insert(pageBookmarks, {
            page = page,
            displayName = displayName,
            name = v.name:sub(11),
            layerID = u
          })
        end
      end
      
      -- Second, sort them alphabetically by their display name
      table.sort(pageBookmarks, function(a, b)
        return a.displayName:lower() < b.displayName:lower()
      end)
      
      -- Third, append them to the store
      for _, b in ipairs(pageBookmarks) do
        store:append({b.page, b.displayName, b.name, b.layerID})
      end
    end
  end

  updateTable()

  -- Create an editable text renderer for inline renaming
  local nameRenderer = Gtk.CellRendererText { editable = true }
  
  function nameRenderer:on_edited(path_str, new_text)
    -- Convert the string path into a real GtkTreePath so we can find the item!
    local path = Gtk.TreePath.new_from_string(path_str)
    local success, iter = store:get_iter(path)
    
    -- Handle LGI return type quirk (sometimes returns iter directly instead of boolean success)
    if type(success) == "userdata" then iter = success end
    
    if iter then
      local page = store[iter][column.PAGE]
      local layerID = store[iter][column.LAYER_ID]
      
      -- Use the exact logic from the old "Edit" button
      local current_structure = app.getDocumentStructure()
      app.setCurrentPage(page)
      local currentLayerID = current_structure.pages[page].currentLayer
      
      app.setCurrentLayer(layerID)
      app.setCurrentLayerName("Bookmark::" .. new_text)
      app.setCurrentLayer(currentLayerID)
      
      -- Update the UI Table to reflect the new name and re-sort
      updateTable()
    end
  end

  -- Initialize TreeView
  local treeView = Gtk.TreeView {
    model = store,
    Gtk.TreeViewColumn {
      title = "Page",
      sizing = "FIXED",
      fixed_width = 70,
      {
        Gtk.CellRendererText {},
        {text = column.PAGE},
      },
    },
  }

  -- Explicitly configure the Name column to guarantee correct layout order
  local nameColumn = Gtk.TreeViewColumn { title = "Name" }
  
  -- 1. Pack the editable text on the LEFT, and do NOT let it expand
  nameColumn:pack_start(nameRenderer, false)
  nameColumn:add_attribute(nameRenderer, "text", column.DISPLAY_NAME)
  
  -- 2. Pack the dummy invisible renderer on the RIGHT, and DO let it expand to fill space
  local dummyRenderer = Gtk.CellRendererText {}
  nameColumn:pack_start(dummyRenderer, true)
  
  -- 3. Add the properly structured column to the treeView
  treeView:append_column(nameColumn)

  ui.scrolledWindow:add(treeView)

  function treeView:on_row_activated(path, tv_column)
    local model = self:get_model()
    local iter = model:get_iter(path)
    if iter then
      local page = model[iter][column.PAGE]
      app.setCurrentPage(page)
      app.scrollToPage(page)
      dialog:destroy()
    end
  end

  local mouse_x, mouse_y = get_mouse_position()
  if mouse_x and mouse_y then
    dialog:show_all()
    local width = dialog:get_allocated_width()
    local height = dialog:get_allocated_height()
    dialog:move(mouse_x - width / 2, mouse_y - height / 2)
  end

  function ui.btnNew.on_clicked()
    new_bookmark("")
    updateTable()
  end

  function ui.btnDelete.on_clicked()
    local model, iter = treeView:get_selection():get_selected()
    if not iter then return end
    local page, layerID = model[iter][column.PAGE], model[iter][column.LAYER_ID]
    delete_layer(page, layerID)
    updateTable()
  end

  function ui.btnDone.on_clicked()
    dialog:destroy()
  end

  if not mouse_x or not mouse_y then
    dialog:show_all()
  end
end

function export()

  if not os.execute("pdftk") then
    app.openDialog("pdftk is missing.", {"OK"}, "")
    return
  end
  local structure = app.getDocumentStructure()

  local defaultName = DEFAULT_EXPORT_PATH
  local xopp_name = structure.xoppFilename
  if xopp_name ~= nil and xopp_name ~= "" then
    defaultName = xopp_name:match("(.+)%..+$")
  end
  defaultName = defaultName .. "_export.pdf"
  local path = app.saveAs(defaultName)
  if path == nil then return end

  local tempData = os.tmpname()
  if sep == "\\" then tempData = tempData:sub(2) end --on windows, the first character breaks tmpname for some reason
  local tempPdf = tempData .. "_1337__.pdf" -- if this breaks something, it'd be very impressive

  app.export({outputFile = tempPdf})

  os.execute("pdftk \"" .. tempPdf .. "\" dump_data output \"" .. tempData .. "\"")

  local file = io.open(tempData,"a+")
  local bookmarkTable = {}
  local numPages = #structure.pages
  
  -- Extract and Sort Exported Bookmarks by Page & Alphabetical Name
  for page=1, numPages do
    local pageBookmarks = {}
    for u,v in pairs(structure.pages[page].layers) do
      if v.name:sub(1,10) == "Bookmark::" then
        table.insert(pageBookmarks, {
          page = page, 
          name = utf8_to_html(v.name:sub(11)),
          rawName = v.name:sub(11)
        })
      end
    end
    
    table.sort(pageBookmarks, function(a, b)
      local aName = a.rawName == "" and "(No name)" or a.rawName
      local bName = b.rawName == "" and "(No name)" or b.rawName
      return aName:lower() < bName:lower()
    end)
    
    for _, b in ipairs(pageBookmarks) do
      table.insert(bookmarkTable, b)
    end
  end
  
  for u, bookmark in pairs(bookmarkTable) do
    file:write("BookmarkBegin\n")
    file:write("BookmarkTitle: " .. bookmark.name .. "\n")
    file:write("BookmarkLevel: 1\n")
    file:write("BookmarkPageNumber: " .. bookmark.page .. "\n")
  end
  file:close()

  os.execute("pdftk \"" .. tempPdf .. "\" update_info \"" .. tempData .. "\" output \"" .. path .."\"")

  os.remove(tempData)
  os.remove(tempPdf)
end